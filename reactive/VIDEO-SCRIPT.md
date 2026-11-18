# Demo video script — Sentinel × Reactive circuit-breaker (< 3 min)

Target: < 180 s total. Screen-record the terminal + explorer pages; voiceover
in English. Fill the [TX] placeholders with the real hashes from RUNLOG.md
before recording.

## 0:00–0:15 — Hook
"Sentinel is an AI guardian agent for Agent ID wallets. A threat verdict
used to sit in a log until a polling bot noticed it minutes later. Now a
Reactive contract trips an on-chain circuit-breaker in about one second —
and the agent refuses to execute while it is halted."

## 0:15–0:45 — Architecture (show the three contracts)
- SentinelRegistry on Ethereum Sepolia — the origin. The agent logs every
  verdict here (DecisionLogged).
- SentinelReactor on Reactive Lasna — subscribes to DecisionLogged, routes
  each verdict: PASS → record-ready callback; BLOCK + threat reason
  (NOT_FREE / SIMULATION_FAILED / BLOCKLISTED) → trip callback.
- SentinelBreaker on Sepolia — receives the callback, appends the alert,
  sets halted=true on a threat. The agent reads halted() before every
  execution.
Show the three addresses + explorer links on screen.

## 0:45–1:30 — Demo 1: PASS loop (show each tx live)
1. Terminal: log a PASS verdict to the Sepolia registry.
   Tx: 0xbb4c52fbf89d174ccd1d57974499a68c2341111de956b453f55c10269b624236 — https://sepolia.etherscan.io/tx/0xbb4c52fbf89d174ccd1d57974499a68c2341111de956b453f55c10269b624236
2. Lasna explorer: the system contract calls react() on the reactor.
   Tx: 0x3d6a2525b26ab8a0e4bbec85abe05c9a9c5cf74d450d4068a4c1e0facc8f5706 — https://lasna.reactscan.net/tx/0x3d6a2525b26ab8a0e4bbec85abe05c9a9c5cf74d450d4068a4c1e0facc8f5706
3. Sepolia explorer: callback calls recordVerdict on the breaker.
   Tx: 0xe9ef7c89cedfa24454ee15917969cbe65ba11b0f41f71b439071ffc426183aa3 — https://sepolia.etherscan.io/tx/0xe9ef7c89cedfa24454ee15917969cbe65ba11b0f41f71b439071ffc426183aa3
4. Terminal: breaker alertCount = 1, halted = false. Agent guard passes.

## 1:30–2:30 — Demo 2: BLOCK / threat loop
1. Terminal: log a BLOCK + BLOCKLISTED verdict (target on the blocklist).
   Tx: 0xaf24db4b4d28eb83187149705451f5f5e7b941d3dafea47569c4380f3f1afb5f
2. Lasna explorer: react() routes the threat.
   Tx: 0x423bcfa79359d324e065c709535c30031254caaf21e15eb7498d8896d5b211b3
3. Sepolia explorer: callback trips the breaker.
   Tx: 0x058dca9d1048e3d5aa243d114e7d42ef8925a0939664029090c3eb416b30e3e5
4. Terminal: breaker halted = true, haltedReason = 10 (BLOCKLISTED),
   alertCount = 2. Run agent/reactive-guard.js --guard → exits 2,
   "HALTED — refusing to execute".

## 2:30–2:55 — Why it matters + links
"The reactive contract is the ONLY path from a threat verdict to an enforced
halt — no polling, no delay, no second chance for the bad mint. Track:
Reactive Meets AI. Repo, addresses and all tx hashes in the description."

## Shot list (record in this order)
1. Terminal: cast call breaker halted/alertCount (pre-demo state).
2. Terminal: PASS logDecision tx + Sepolia Etherscan page.
3. Lasna Reactscan: reactor page → react() tx.
4. Sepolia Etherscan: callback tx → breaker VerdictRecorded event.
5. Terminal: BLOCK logDecision tx + same chain of explorer pages.
6. Terminal: agent/reactive-guard.js --guard (exit 2) + reset() by owner.
7. End card: repo URL + three contract addresses.
