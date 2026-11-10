// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SentinelRegistry} from "../contracts/SentinelRegistry.sol";

contract SentinelRegistryTest is Test {
    SentinelRegistry internal registry;
    address internal wallet = address(0xA11CE);
    address internal agent = address(0xA6E77);
    address internal target = address(0x7A9E7);

    function setUp() public {
        registry = new SentinelRegistry();
    }

    // ---------------------------------------------------------------
    // Policy set / get
    // ---------------------------------------------------------------

    function testSetAndGetPolicy() public {
        vm.prank(wallet);
        registry.setPolicy(true, false, 0.01 ether, 5);

        SentinelRegistry.Policy memory p = registry.getPolicy(wallet);
        assertTrue(p.exists);
        assertTrue(p.freeOnly);
        assertFalse(p.paused);
        assertEq(p.maxValuePerTx, 0.01 ether);
        assertEq(p.dailyTxCap, 5);
    }

    function testPolicyDefaultsToMissing() public view {
        SentinelRegistry.Policy memory p = registry.getPolicy(wallet);
        assertFalse(p.exists);
    }

    // ---------------------------------------------------------------
    // Log append
    // ---------------------------------------------------------------

    function testWalletCanLogOwnDecision() public {
        vm.prank(wallet);
        uint256 id = registry.logDecision(
            wallet,
            target,
            SentinelRegistry.ActionKind.MINT,
            SentinelRegistry.Verdict.BLOCK,
            SentinelRegistry.ReasonCode.QUOTA_USED,
            bytes32(0)
        );
        assertEq(id, 0);
        assertEq(registry.decisionsCount(), 1);

        SentinelRegistry.Decision memory d = registry.getDecision(0);
        assertEq(d.wallet, wallet);
        assertEq(d.target, target);
        assertEq(uint8(d.verdict), uint8(SentinelRegistry.Verdict.BLOCK));
        assertEq(uint8(d.reason), uint8(SentinelRegistry.ReasonCode.QUOTA_USED));
        assertEq(d.txHash, bytes32(0));
    }

    function testAuthorizedLoggerCanLog() public {
        vm.prank(wallet);
        registry.setLogger(agent, true);

        bytes32 execTx = bytes32(uint256(0xBEEF));
        vm.prank(agent);
        registry.logDecision(
            wallet,
            target,
            SentinelRegistry.ActionKind.CLAIM,
            SentinelRegistry.Verdict.PASS,
            SentinelRegistry.ReasonCode.NONE,
            execTx
        );
        assertEq(registry.decisionsCount(), 1);
    }

    function testStrangerCannotLog() public {
        vm.prank(address(0xBAD));
        vm.expectRevert("logger not authorized");
        registry.logDecision(
            wallet,
            target,
            SentinelRegistry.ActionKind.MINT,
            SentinelRegistry.Verdict.BLOCK,
            SentinelRegistry.ReasonCode.NO_CODE,
            bytes32(0)
        );
    }

    function testBlockRequiresReason() public {
        vm.prank(wallet);
        vm.expectRevert("BLOCK requires a reason");
        registry.logDecision(
            wallet,
            target,
            SentinelRegistry.ActionKind.MINT,
            SentinelRegistry.Verdict.BLOCK,
            SentinelRegistry.ReasonCode.NONE,
            bytes32(0)
        );
    }

    // ---------------------------------------------------------------
    // Daily-cap accounting + enforcement view
    // ---------------------------------------------------------------

    function testExecutionConsumesDailyCap() public {
        vm.prank(wallet);
        registry.setPolicy(true, false, 0, 1);

        // BLOCK entries never consume the cap.
        vm.prank(wallet);
        registry.logDecision(
            wallet,
            target,
            SentinelRegistry.ActionKind.MINT,
            SentinelRegistry.Verdict.BLOCK,
            SentinelRegistry.ReasonCode.SIMULATION_FAILED,
            bytes32(0)
        );
        assertEq(registry.executedOnDay(wallet, block.timestamp / 1 days), 0);

        // One execution consumes it.
        vm.prank(wallet);
        registry.logDecision(
            wallet,
            target,
            SentinelRegistry.ActionKind.MINT,
            SentinelRegistry.Verdict.PASS,
            SentinelRegistry.ReasonCode.NONE,
            bytes32(uint256(0x1))
        );
        assertEq(registry.executedOnDay(wallet, block.timestamp / 1 days), 1);

        // evaluate() now blocks further executions today.
        (SentinelRegistry.Verdict v, SentinelRegistry.ReasonCode r) = registry.evaluate(wallet, 0, true);
        assertEq(uint8(v), uint8(SentinelRegistry.Verdict.BLOCK));
        assertEq(uint8(r), uint8(SentinelRegistry.ReasonCode.DAILY_CAP_REACHED));
    }

    function testEvaluateFreeOnlyBlocksPaid() public {
        vm.prank(wallet);
        registry.setPolicy(true, false, 1 ether, 0);
        (SentinelRegistry.Verdict v, SentinelRegistry.ReasonCode r) = registry.evaluate(wallet, 1, true);
        assertEq(uint8(v), uint8(SentinelRegistry.Verdict.BLOCK));
        assertEq(uint8(r), uint8(SentinelRegistry.ReasonCode.NOT_FREE));
    }

    function testEvaluateNoPolicyFailsClosed() public view {
        (SentinelRegistry.Verdict v,) = registry.evaluate(wallet, 0, true);
        assertEq(uint8(v), uint8(SentinelRegistry.Verdict.BLOCK));
    }

    function testEvaluatePausedBlocks() public {
        vm.prank(wallet);
        registry.setPolicy(false, true, 1 ether, 0);
        (SentinelRegistry.Verdict v, SentinelRegistry.ReasonCode r) = registry.evaluate(wallet, 0, true);
        assertEq(uint8(v), uint8(SentinelRegistry.Verdict.BLOCK));
        assertEq(uint8(r), uint8(SentinelRegistry.ReasonCode.POLICY_PAUSED));
    }
}
