// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title SentinelBreaker
/// @notice Callback contract for Sentinel (Reactive Omni Buildathon, Nov 2026).
/// @dev Lives on Ethereum Sepolia. Receives callbacks from SentinelReactor
///      (Lasna) via the Sepolia callback proxy. A threat verdict sets
///      halted=true; the Sentinel agent reads halted() before every execution
///      and refuses to send anything while the breaker is tripped. The owner
///      (throwaway deployer) can reset() after reviewing the alert.
///
///      Auth is two-layer, per the Reactive docs: onlyServiceProvider
///      (msg.sender must be the Sepolia callback proxy) AND
///      onlyCallbackSender (the first payload argument, injected by the proxy
///      with the reactor's address, must equal _CALLBACK_SENDER).
///
///      Written 2026-11-16 for the Reactive Omni Buildathon.
import { AbstractCallback } from "reactive-lib-omni/base/AbstractCallback.sol";
import { IPayable } from "reactive-lib-omni/interfaces/IPayable.sol";

contract SentinelBreaker is AbstractCallback {
    /// @notice One routed verdict, as delivered by the reactor.
    struct Alert {
        uint8 verdict;
        uint8 reason;
        address wallet;
        address target;
        uint64 timestamp;
    }

    /// @notice True while a threat verdict has tripped the breaker.
    bool public halted;
    /// @notice ReasonCode that tripped the breaker (0 when not halted).
    uint8 public haltedReason;
    /// @notice Append-only log of every verdict the reactor routed.
    Alert[] public alerts;
    /// @notice Deployer/owner (throwaway testnet key).
    address public owner;

    event VerdictRecorded(
        address indexed wallet, address indexed target, uint8 verdict, uint8 reason, bool threat
    );
    event Halted(address indexed wallet, address indexed target, uint8 reason);
    event Reset(address indexed by);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(IPayable callbackProxy_, address callbackSender_)
        AbstractCallback(callbackProxy_, callbackSender_)
    {
        owner = msg.sender;
    }

    /// @notice Called by the Sepolia callback proxy on the reactor's behalf.
    /// @param callbackSender_ First payload argument — the proxy injects the
    ///        reactor's address here; must equal _CALLBACK_SENDER.
    function recordVerdict(
        address callbackSender_,
        uint8 verdict_,
        uint8 reason_,
        address wallet_,
        address target_
    ) external onlyServiceProvider onlyCallbackSender(callbackSender_) {
        bool threat = verdict_ == 1 && (reason_ == 4 || reason_ == 5 || reason_ == 10);
        alerts.push(
            Alert({
                verdict: verdict_,
                reason: reason_,
                wallet: wallet_,
                target: target_,
                timestamp: uint64(block.timestamp)
            })
        );
        emit VerdictRecorded(wallet_, target_, verdict_, reason_, threat);
        if (threat) {
            halted = true;
            haltedReason = reason_;
            emit Halted(wallet_, target_, reason_);
        }
    }

    /// @notice Clear the halt after the owner reviews the alert (owner-only).
    function reset() external onlyOwner {
        halted = false;
        haltedReason = 0;
        emit Reset(msg.sender);
    }

    /// @notice Number of verdicts routed so far.
    function alertCount() external view returns (uint256) {
        return alerts.length;
    }
}
