// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title SentinelReactor
/// @notice Reactive contract for Sentinel (Reactive Omni Buildathon, Nov 2026).
/// @dev Subscribes to SentinelRegistry.DecisionLogged on Ethereum Sepolia
///      (chain 11155111) and routes each verdict to a callback on the
///      SentinelBreaker (also Sepolia). The reactor is the ONLY path by which
///      a threat verdict becomes an enforced halt: a polling bot would notice
///      minutes later (or never); this fires in ~1 second.
///
///      Threat verdicts (BLOCK + NOT_FREE / SIMULATION_FAILED / BLOCKLISTED)
///      request a callback that trips the breaker. PASS verdicts request a
///      callback that records readiness. Other BLOCK reasons (e.g. QUOTA_USED)
///      are not threats and request no callback (no wasted callback gas).
///
///      Written 2026-11-16 for the Reactive Omni Buildathon. SentinelRegistry
///      itself is unchanged Nov 10 code, redeployed fresh on Sepolia as the
///      origin (a dependency redeploy, not a rewrite).
import { AbstractReactive } from "reactive-lib-omni/base/AbstractReactive.sol";
import { IReactive } from "reactive-lib-omni/interfaces/IReactive.sol";
import { ISystemContract } from "reactive-lib-omni/interfaces/ISystemContract.sol";

contract SentinelReactor is AbstractReactive {
    /// @notice Origin chain: Ethereum Sepolia.
    uint256 internal constant ORIGIN_CHAIN_ID = 11155111;
    /// @notice keccak256("DecisionLogged(uint256,address,address,uint8,uint8,uint8,bytes32)").
    uint256 internal constant DECISION_TOPIC0 =
        0x7e17a9c86e011e7e110d42ad938ba16ea8471b61881522d86334e7a47d2c90b6;
    /// @notice Gas limit for the Sepolia callback (recordVerdict + storage).
    /// @dev MUST cover the callback's real cost plus the Sepolia proxy's
    ///      overhead (_extraGas 150k + _maxChargeGas 50k = 200k, reserved
    ///      from the relayer tx whose gas limit equals this value).
    ///      recordVerdict costs ~356k on its first call (cold storage:
    ///      alerts array first push), so 300k starved it and the proxy
    ///      emitted CallbackFailure (2026-11-16). 700k covers the first
    ///      call (~356k) + 200k proxy overhead + relayer/tx margin.
    uint64 internal constant CALLBACK_GAS_LIMIT = 700_000;

    /// @notice Verdict enum values (SentinelRegistry.Verdict).
    uint8 internal constant VERDICT_PASS = 0;
    uint8 internal constant VERDICT_BLOCK = 1;
    /// @notice Threat ReasonCode values (SentinelRegistry.ReasonCode).
    uint8 internal constant REASON_NOT_FREE = 4;
    uint8 internal constant REASON_SIMULATION_FAILED = 5;
    uint8 internal constant REASON_BLOCKLISTED = 10;

    /// @notice Sepolia SentinelRegistry this reactor watches.
    address public immutable originRegistry;
    /// @notice Sepolia SentinelBreaker receiving callbacks (set after deploy).
    address public breaker;
    /// @notice Deployer/owner (throwaway testnet key).
    address public owner;

    event BreakerSet(address indexed breaker);
    event VerdictRouted(
        uint256 indexed decisionId,
        address indexed wallet,
        address indexed target,
        uint8 verdict,
        uint8 reason,
        bool threat
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address originRegistry_) {
        owner = msg.sender;
        originRegistry = originRegistry_;
        SYSTEM.subscribe(
            ORIGIN_CHAIN_ID,
            originRegistry_,
            DECISION_TOPIC0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @notice Point the reactor at the deployed breaker (owner-only).
    /// @dev Deploy order forces this: reactor first, breaker second
    ///      (the breaker needs the reactor address as its callback sender).
    function setBreaker(address breaker_) external onlyOwner {
        breaker = breaker_;
        emit BreakerSet(breaker_);
    }

    /// @notice Called by the Reactive system contract for every matching log.
    /// @dev Decodes DecisionLogged: topic1 = id, topic2 = wallet,
    ///      topic3 = target; data = (kind, verdict, reason, txHash).
    function react(IReactive.LogRecord calldata log_) external override onlySystem {
        (uint8 kind_, uint8 verdict_, uint8 reason_, bytes32 txHash_) =
            abi.decode(log_.data, (uint8, uint8, uint8, bytes32));
        // Silence unused-variable warnings while keeping the full decode
        // shape explicit (kind/txHash are informational, not routing inputs).
        kind_;
        txHash_;

        bool threat = verdict_ == VERDICT_BLOCK
            && (
                reason_ == REASON_NOT_FREE || reason_ == REASON_SIMULATION_FAILED
                    || reason_ == REASON_BLOCKLISTED
            );
        bool route = threat || verdict_ == VERDICT_PASS;

        emit VerdictRouted(
            log_.topic1, address(uint160(log_.topic2)), address(uint160(log_.topic3)), verdict_, reason_, threat
        );

        if (!route || breaker == address(0)) {
            return;
        }

        // First payload argument is the address(0) placeholder the Sepolia
        // callback proxy overwrites with this reactor's address.
        bytes memory payload = abi.encodeWithSignature(
            "recordVerdict(address,uint8,uint8,address,address)",
            address(0),
            verdict_,
            reason_,
            address(uint160(log_.topic2)),
            address(uint160(log_.topic3))
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: ORIGIN_CHAIN_ID,
                recipient: breaker,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
    }
}
