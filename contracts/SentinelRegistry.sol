// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SentinelRegistry
/// @notice On-chain policy + decision logbook for the Sentinel guardian agent.
///
/// Sentinel watches mint / claim opportunities for Binance Agent ID wallets on
/// BNB Chain. Before anything is executed, the agent runs a verification
/// pipeline off-chain (code exists, source-verification signal, free-quota
/// state, zero price, eth_call simulation, wallet preview). This contract is
/// the part that must be public and tamper-evident:
///
///   1. POLICY  — the rails each wallet owner set for their guardian
///                (free-only, per-tx value cap, daily tx cap, pause switch).
///   2. LOGBOOK — an append-only record of every opportunity the agent
///                evaluated: target contract, action kind, verdict
///                (PASS / BLOCK), a machine-readable reason code, and the
///                hash of the transaction that followed (when one did).
///
/// Anyone can audit whether a guardian behaves the way its owner configured:
/// the policy is on-chain, and every decision it ever made is on-chain too.
contract SentinelRegistry {
    // ------------------------------------------------------------------
    // Types
    // ------------------------------------------------------------------

    /// @notice What the agent was asked to do with an opportunity.
    enum ActionKind {
        MINT, // public / free mint
        CLAIM, // airdrop / reward claim
        APPROVE, // token approval (exact-amount only under the rails)
        OTHER
    }

    /// @notice Outcome of the verification pipeline.
    enum Verdict {
        PASS, // every check passed -> eligible for execution
        BLOCK // at least one check failed -> nothing is sent
    }

    /// @notice Machine-readable reason codes. Keep in sync with agent/verify.js.
    enum ReasonCode {
        NONE, // 0 — PASS, no reason needed
        NO_CODE, // 1 — target address holds no bytecode
        UNVERIFIED_SOURCE, // 2 — no verified-source signal for the target
        QUOTA_USED, // 3 — the wallet's free quota for this contract is spent
        NOT_FREE, // 4 — price > 0 while policy is free-only
        SIMULATION_FAILED, // 5 — eth_call simulation reverted
        PREVIEW_MISMATCH, // 6 — wallet preview showed unexpected changes
        OVER_VALUE_CAP, // 7 — value exceeds policy.maxValuePerTx
        DAILY_CAP_REACHED, // 8 — policy.dailyTxCap already used today
        POLICY_PAUSED, // 9 — wallet policy is paused
        BLOCKLISTED // 10 — target is on the owner's blocklist
    }

    /// @notice Per-wallet guardian policy ("Safety Rails", on-chain).
    struct Policy {
        bool exists;
        bool freeOnly; // default rail: only zero-price opportunities
        bool paused; // kill switch: agent must not execute anything
        uint256 maxValuePerTx; // wei; hard cap for a single execution
        uint32 dailyTxCap; // max executed txs per UTC day
    }

    /// @notice One evaluated opportunity. Append-only, never edited.
    struct Decision {
        address wallet; // wallet the opportunity was evaluated for
        address target; // opportunity contract
        ActionKind kind;
        Verdict verdict;
        ReasonCode reason; // NONE when verdict == PASS
        bytes32 txHash; // execution tx hash, or bytes32(0) if none sent
        uint64 timestamp; // block time of the log entry
    }

    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------

    mapping(address => Policy) private _policies;
    mapping(address => bool) public isOperator; // agent addresses allowed to log for any wallet
    mapping(address => mapping(address => bool)) public authorizedLogger; // wallet => logger => ok

    Decision[] public decisions;

    /// @notice Executed-tx counter per wallet per UTC day: wallet => day => count.
    mapping(address => mapping(uint256 => uint32)) public executedOnDay;

    address public owner;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    event PolicyUpdated(
        address indexed wallet, bool freeOnly, bool paused, uint256 maxValuePerTx, uint32 dailyTxCap
    );
    event LoggerAuthorized(address indexed wallet, address indexed logger, bool allowed);
    event OperatorSet(address indexed operator, bool allowed);
    event DecisionLogged(
        uint256 indexed id,
        address indexed wallet,
        address indexed target,
        ActionKind kind,
        Verdict verdict,
        ReasonCode reason,
        bytes32 txHash
    );

    // ------------------------------------------------------------------
    // Admin / policy
    // ------------------------------------------------------------------

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    /// @notice Register or replace the caller's own guardian policy.
    /// @dev A wallet owner always controls their own policy. The agent never
    ///      writes policy — it only reads it and obeys it.
    function setPolicy(bool freeOnly, bool paused, uint256 maxValuePerTx, uint32 dailyTxCap) external {
        _policies[msg.sender] = Policy({
            exists: true,
            freeOnly: freeOnly,
            paused: paused,
            maxValuePerTx: maxValuePerTx,
            dailyTxCap: dailyTxCap
        });
        emit PolicyUpdated(msg.sender, freeOnly, paused, maxValuePerTx, dailyTxCap);
    }

    function getPolicy(address wallet) external view returns (Policy memory) {
        return _policies[wallet];
    }

    /// @notice Authorize an agent address to write log entries for your wallet.
    function setLogger(address logger, bool allowed) external {
        authorizedLogger[msg.sender][logger] = allowed;
        emit LoggerAuthorized(msg.sender, logger, allowed);
    }

    /// @notice Platform-level operators (e.g. the hosted Sentinel runner).
    function setOperator(address operator, bool allowed) external onlyOwner {
        isOperator[operator] = allowed;
        emit OperatorSet(operator, allowed);
    }

    // ------------------------------------------------------------------
    // Logbook
    // ------------------------------------------------------------------

    /// @notice Append one evaluated opportunity to the public logbook.
    /// @dev The logger must be the wallet itself, a logger the wallet
    ///      authorized, or a platform operator. Logging is bookkeeping only:
    ///      it moves no funds and grants no approvals.
    /// @param relatedTx Hash of the execution transaction that followed the
    ///        verdict, or bytes32(0) when nothing was broadcast.
    function logDecision(
        address wallet,
        address target,
        ActionKind kind,
        Verdict verdict,
        ReasonCode reason,
        bytes32 relatedTx
    ) external returns (uint256 id) {
        require(
            msg.sender == wallet || authorizedLogger[wallet][msg.sender] || isOperator[msg.sender],
            "logger not authorized"
        );
        if (verdict == Verdict.PASS) {
            require(reason == ReasonCode.NONE, "PASS requires reason NONE");
        } else {
            require(reason != ReasonCode.NONE, "BLOCK requires a reason");
        }

        id = decisions.length;
        decisions.push(
            Decision({
                wallet: wallet,
                target: target,
                kind: kind,
                verdict: verdict,
                reason: reason,
                txHash: relatedTx,
                timestamp: uint64(block.timestamp)
            })
        );

        // Only executions consume the daily cap. A PASS with a related tx
        // hash is an execution; a BLOCK never is.
        if (relatedTx != bytes32(0)) {
            executedOnDay[wallet][block.timestamp / 1 days] += 1;
        }
        emit DecisionLogged(id, wallet, target, kind, verdict, reason, relatedTx);
    }

    function decisionsCount() external view returns (uint256) {
        return decisions.length;
    }

    function getDecision(uint256 id) external view returns (Decision memory) {
        require(id < decisions.length, "no such decision");
        return decisions[id];
    }

    // ------------------------------------------------------------------
    // Policy evaluation (what the agent checks before it may execute)
    // ------------------------------------------------------------------

    /// @notice Evaluate a proposed execution against a wallet's policy.
    /// @dev Pure policy math — the agent calls this (off-chain, via eth_call)
    ///      as one step of its verification pipeline. Returns the verdict and
    ///      the reason code that would be logged.
    /// @param value Wei that the execution would send.
    /// @param wouldExecute Whether the agent intends to broadcast afterwards.
    function evaluate(address wallet, uint256 value, bool wouldExecute)
        external
        view
        returns (Verdict verdict, ReasonCode reason)
    {
        Policy memory p = _policies[wallet];
        if (!p.exists) {
            // Fail closed: no policy on-chain means the guardian has no rails
            // to work under, so nothing may execute.
            return (Verdict.BLOCK, ReasonCode.POLICY_PAUSED);
        }
        if (p.paused) return (Verdict.BLOCK, ReasonCode.POLICY_PAUSED);
        if (p.freeOnly && value > 0) return (Verdict.BLOCK, ReasonCode.NOT_FREE);
        if (value > p.maxValuePerTx) return (Verdict.BLOCK, ReasonCode.OVER_VALUE_CAP);
        if (wouldExecute && p.dailyTxCap > 0) {
            if (executedOnDay[wallet][block.timestamp / 1 days] >= p.dailyTxCap) {
                return (Verdict.BLOCK, ReasonCode.DAILY_CAP_REACHED);
            }
        }
        return (Verdict.PASS, ReasonCode.NONE);
    }
}
