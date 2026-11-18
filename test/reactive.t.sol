// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title Sentinel reactive integration tests
/// @notice Local anvil simulation of the full Sepolia -> Lasna -> Sepolia
///         loop. A mock system contract is etched at the real Reactive
///         SYSTEM address (0x8888...8888) so the reactor's subscribe() and
///         requestCallbackV_1_0() calls are recorded and assertable. The only
///         part this cannot prove is the REAL Reactive network delivering
///         react() — that needs Lasna after funding.
import { Test } from "forge-std/Test.sol";
import { SentinelRegistry } from "../contracts/SentinelRegistry.sol";
import { SentinelReactor } from "../contracts/reactive/SentinelReactor.sol";
import { SentinelBreaker } from "../contracts/reactive/SentinelBreaker.sol";
import { IReactive } from "reactive-lib-omni/interfaces/IReactive.sol";
import { ISystemContract } from "reactive-lib-omni/interfaces/ISystemContract.sol";
import { IPayable } from "reactive-lib-omni/interfaces/IPayable.sol";

/// @notice Minimal stand-in for the Reactive system contract. Records every
///         subscription and callback request the reactor makes.
contract MockSystem {
    uint256 public subscribeCount;
    uint256 public lastChainId;
    address public lastContract;
    uint256 public lastTopic0;
    uint256 public callbackCount;
    uint256 public lastCallbackChainId;
    address public lastRecipient;
    uint64 public lastGasLimit;
    bytes public lastPayload;

    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256,
        uint256,
        uint256
    ) external {
        subscribeCount++;
        lastChainId = chainId_;
        lastContract = contract_;
        lastTopic0 = topic0_;
    }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory config_)
        external
    {
        callbackCount++;
        lastCallbackChainId = config_.chainId;
        lastRecipient = config_.recipient;
        lastGasLimit = config_.gasLimit;
        lastPayload = config_.payload;
    }
}

contract SentinelReactiveTest is Test {
    address internal constant SYSTEM = 0x8888888888888888888888888888888888888888;
    address internal constant SEPOLIA_PROXY = 0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4;
    uint256 internal constant DECISION_TOPIC0 =
        0x7e17a9c86e011e7e110d42ad938ba16ea8471b61881522d86334e7a47d2c90b6;

    SentinelRegistry internal registry;
    SentinelReactor internal reactor;
    SentinelBreaker internal breaker;
    MockSystem internal mock;
    // Reads the mock's state from SYSTEM's storage: the etched code runs
    // with SYSTEM's storage, so the counters live at SYSTEM, not at mock.
    MockSystem internal system;

    function setUp() public {
        mock = new MockSystem();
        vm.etch(SYSTEM, address(mock).code);
        system = MockSystem(SYSTEM);

        registry = new SentinelRegistry();
        reactor = new SentinelReactor(address(registry));
        breaker = new SentinelBreaker(IPayable(payable(SEPOLIA_PROXY)), address(reactor));
        reactor.setBreaker(address(breaker));
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _logDecision(
        SentinelRegistry.ActionKind kind,
        SentinelRegistry.Verdict verdict,
        SentinelRegistry.ReasonCode reason
    ) internal returns (uint256 id) {
        // wallet == this test contract, so logDecision auth passes
        // (msg.sender == wallet).
        address wallet = address(this);
        address target = address(0xdead);
        id = registry.logDecision(wallet, target, kind, verdict, reason, bytes32(0));
    }

    function _makeLog(uint256 id, uint8 kind, uint8 verdict, uint8 reason)
        internal
        view
        returns (IReactive.LogRecord memory)
    {
        return IReactive.LogRecord({
            chainId: 11155111,
            contractAddress: address(registry),
            topic0: DECISION_TOPIC0,
            topic1: id,
            topic2: uint256(uint160(address(this))),
            topic3: uint256(uint160(address(0xdead))),
            data: abi.encode(kind, verdict, reason, bytes32(0)),
            blockNumber: block.number,
            opCode: 4,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
    }

    /// @notice Simulate the Sepolia callback proxy delivering the reactor's
    ///         last requested callback: it overwrites the first payload
    ///         argument (the address(0) placeholder) with the reactor address
    ///         and calls the breaker as the proxy.
    function _deliverLastCallback() internal {
        bytes memory payload = system.lastPayload();
        assertGt(payload.length, 4, "no callback recorded");
        bytes memory args = new bytes(payload.length - 4);
        for (uint256 i = 0; i < args.length; i++) {
            args[i] = payload[i + 4];
        }
        (address sender, uint8 verdict, uint8 reason, address wallet, address target) =
            abi.decode(args, (address, uint8, uint8, address, address));
        assertEq(sender, address(0), "payload placeholder must be address(0)");
        vm.prank(SEPOLIA_PROXY);
        breaker.recordVerdict(address(reactor), verdict, reason, wallet, target);
    }

    function _react(uint256 id, uint8 kind, uint8 verdict, uint8 reason) internal {
        vm.prank(SYSTEM);
        reactor.react(_makeLog(id, kind, verdict, reason));
    }

    // ------------------------------------------------------------------
    // Subscription
    // ------------------------------------------------------------------

    function testSubscriptionTargetsSepoliaRegistry() public view {
        assertEq(system.subscribeCount(), 1, "exactly one subscription");
        assertEq(system.lastChainId(), 11155111, "origin must be Sepolia");
        assertEq(system.lastContract(), address(registry), "origin must be the registry");
        assertEq(system.lastTopic0(), DECISION_TOPIC0, "must watch DecisionLogged");
    }

    // ------------------------------------------------------------------
    // Threat verdict -> callback -> breaker trips
    // ------------------------------------------------------------------

    function testThreatVerdictTripsBreaker() public {
        uint256 id = _logDecision(
            SentinelRegistry.ActionKind.MINT,
            SentinelRegistry.Verdict.BLOCK,
            SentinelRegistry.ReasonCode.BLOCKLISTED
        );
        _react(id, 0, 1, 10);

        assertEq(system.callbackCount(), 1, "threat must request a callback");
        assertEq(system.lastCallbackChainId(), 11155111, "callback back to Sepolia");
        assertEq(system.lastRecipient(), address(breaker), "callback to the breaker");
        // 700k: recordVerdict costs ~356k on its first call (cold storage)
        // and the Sepolia proxy reserves 200k overhead from the relayer tx
        // (gas limit = this value). 300k starved it on mainnet-testnet and
        // the proxy emitted CallbackFailure (2026-11-16).
        assertEq(system.lastGasLimit(), 700_000, "callback gas limit");

        _deliverLastCallback();

        assertTrue(breaker.halted(), "breaker must trip on a threat verdict");
        assertEq(breaker.haltedReason(), 10, "halted reason must be BLOCKLISTED");
        assertEq(breaker.alertCount(), 1, "one alert recorded");
        (uint8 v, uint8 r, address w, address t,) = breaker.alerts(0);
        assertEq(v, 1, "alert verdict BLOCK");
        assertEq(r, 10, "alert reason BLOCKLISTED");
        assertEq(w, address(this), "alert wallet");
        assertEq(t, address(0xdead), "alert target");
    }

    function testSimulationFailedIsAThreat() public {
        uint256 id = _logDecision(
            SentinelRegistry.ActionKind.CLAIM,
            SentinelRegistry.Verdict.BLOCK,
            SentinelRegistry.ReasonCode.SIMULATION_FAILED
        );
        _react(id, 1, 1, 5);
        _deliverLastCallback();
        assertTrue(breaker.halted(), "SIMULATION_FAILED must trip the breaker");
        assertEq(breaker.haltedReason(), 5);
    }

    function testNotFreeIsAThreat() public {
        uint256 id = _logDecision(
            SentinelRegistry.ActionKind.MINT,
            SentinelRegistry.Verdict.BLOCK,
            SentinelRegistry.ReasonCode.NOT_FREE
        );
        _react(id, 0, 1, 4);
        _deliverLastCallback();
        assertTrue(breaker.halted(), "NOT_FREE must trip the breaker");
        assertEq(breaker.haltedReason(), 4);
    }

    // ------------------------------------------------------------------
    // PASS verdict -> callback, no halt
    // ------------------------------------------------------------------

    function testPassVerdictRecordsReadyNoHalt() public {
        uint256 id = _logDecision(
            SentinelRegistry.ActionKind.MINT,
            SentinelRegistry.Verdict.PASS,
            SentinelRegistry.ReasonCode.NONE
        );
        _react(id, 0, 0, 0);

        assertEq(system.callbackCount(), 1, "PASS must request a ready callback");
        _deliverLastCallback();

        assertFalse(breaker.halted(), "PASS must not trip the breaker");
        assertEq(breaker.haltedReason(), 0);
        assertEq(breaker.alertCount(), 1, "ready alert recorded");
    }

    // ------------------------------------------------------------------
    // Non-threat BLOCK -> no callback at all
    // ------------------------------------------------------------------

    function testNonThreatBlockRequestsNoCallback() public {
        uint256 id = _logDecision(
            SentinelRegistry.ActionKind.MINT,
            SentinelRegistry.Verdict.BLOCK,
            SentinelRegistry.ReasonCode.QUOTA_USED
        );
        _react(id, 0, 1, 3);
        assertEq(system.callbackCount(), 0, "non-threat BLOCK must not request a callback");
        assertEq(breaker.alertCount(), 0, "no alert without a callback");
        assertFalse(breaker.halted());
    }

    // ------------------------------------------------------------------
    // Auth guards
    // ------------------------------------------------------------------

    function testReactRevertsForNonSystem() public {
        IReactive.LogRecord memory log = _makeLog(0, 0, 1, 10);
        vm.prank(address(0x1234));
        vm.expectRevert();
        reactor.react(log);
    }

    function testBreakerRejectsWrongCallbackSender() public {
        vm.prank(SEPOLIA_PROXY);
        vm.expectRevert();
        breaker.recordVerdict(address(0x1234), 1, 10, address(this), address(0xdead));
    }

    function testBreakerRejectsNonProxyCaller() public {
        vm.prank(address(0x1234));
        vm.expectRevert();
        breaker.recordVerdict(address(reactor), 1, 10, address(this), address(0xdead));
    }

    function testSetBreakerOnlyOwner() public {
        vm.prank(address(0x1234));
        vm.expectRevert();
        reactor.setBreaker(address(0x1234));
    }

    // ------------------------------------------------------------------
    // Reset
    // ------------------------------------------------------------------

    function testResetClearsHalt() public {
        uint256 id = _logDecision(
            SentinelRegistry.ActionKind.MINT,
            SentinelRegistry.Verdict.BLOCK,
            SentinelRegistry.ReasonCode.BLOCKLISTED
        );
        _react(id, 0, 1, 10);
        _deliverLastCallback();
        assertTrue(breaker.halted());

        vm.prank(address(0x1234));
        vm.expectRevert();
        breaker.reset();

        breaker.reset();
        assertFalse(breaker.halted(), "reset must clear halted");
        assertEq(breaker.haltedReason(), 0, "reset must clear haltedReason");
        assertEq(breaker.alertCount(), 1, "reset must keep the alert log");
    }
}
