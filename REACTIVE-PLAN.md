# Sentinel × Reactive Omni Buildathon — REACTIVE PLAN

Status: DEPLOYED + both demos proven Mon 2026-11-16 ~11:23 WIB.
Funding landed (0.05 SepETH), v1 failed on callback gas (CallbackFailure,
root-caused: 300k limit vs 200k proxy overhead + ~356k first-call cost),
fixed to 700k, v2 redeployed, PASS + BLOCK loops proven end-to-end
(react() + callback + breaker trip + agent --guard exits 2). Breaker left
HALTED as demo evidence. All three live contracts Sourcify exact_match.
Full record: reactive/RUNLOG.md. Remaining: demo video recording (user's
phone/screen) + DoraHacks submission (user registers/submits) + git push.

## 1. Rules, as verified (2026-11-16)

Sources:
- https://blog.reactive.network/reactive-omni-buildathon-thirty-days-to-find-out-what-one-second-buys/
- https://dev.reactive.network/reactive-contracts
- https://dev.reactive.network/callback-contracts
- https://dev.reactive.network/origins-and-destinations
- https://dev.reactive.network/reactive-mainnet (Lasna params + faucet)
- DoraHacks page: https://dorahacks.io/hackathon/reactive-omni-buildathon
  (crawler returns 405 — the page exists; the USER registers there himself)

- Event: Reactive Omni Buildathon, Nov 5 – Dec 5 2026, $5,500 in REACT.
  Registration + submissions via DoraHacks.
- Tracks: "Every Second Counts" ($2,000 1st / $250 runner-up),
  "Set It and Forget It" ($2,000 / $250), "Reactive Meets AI" ($1,000 1st).
- "Reactive Meets AI" rule: the AI has to be part of the running system, not
  just the tool used to write the code.
- "Everything should be built during the event. Prior work can come in as a
  dependency, but not as the submission itself."
- Submission needs: public repo link, deployed contract addresses, tx hashes
  showing the FULL loop from origin event to callback, demo video < 3 min.
- Judging (1–5 each, equal weight): Execution (reactive txs + callbacks
  on-chain, or not scored further), Integration (real work, not bolt-on),
  Usefulness, Craft.
- "Every Second Counts" runs on Lasna testnet; the other two tracks can use
  Reactive mainnet or Lasna. We use Lasna only (testnet-only by decision).
- Mainnets and testnets must not be mixed: testnet origin → testnet
  destination.

## 2. Eligibility analysis

- Sentinel (built Nov 10, BNB Hack) is PRIOR WORK. It enters this
  buildathon as a DEPENDENCY, not as the submission. The submission is the
  NEW reactive integration + agent loop built Nov 16 – Dec 5, all fresh code.
- Track: "Reactive Meets AI". The AI (Sentinel's verification pipeline) is
  part of the running system: it produces the verdicts the reactive contract
  reacts to, and it obeys the breaker the reactive contract trips. Without
  the agent there is no event stream and no execution.
- DECISIVE chain fact (Origins & Destinations page): Lasna testnet origins
  are ONLY Base Sepolia (84532), Ethereum Sepolia (11155111), Reactive
  Lasna (5318007), Unichain Sepolia (1301). **BSC testnet (97) is NOT a
  monitored origin.** BSC mainnet (56) is, but mainnet/testnet must not mix,
  and mainnet is out of scope. So the origin CANNOT be BSC testnet.

## 3. Design — "Sentinel circuit-breaker" (Sepolia → Lasna → Sepolia)

The smallest integration that is genuinely reactive, not a bolt-on: a
cross-chain safety breaker for an autonomous guardian. A polling bot would
notice a threat verdict minutes later (or never); the reactive contract
trips the breaker in ~1 second, and the agent refuses to execute while it
is halted. The reactive contract does real work: it is the ONLY path by
which a threat verdict becomes an enforced halt.

Flow (every leg is a real on-chain tx):

```
Sentinel agent (Node.js, AI verification pipeline)
  │  logs a verdict to SentinelRegistry on Sepolia
  ▼
DecisionLogged(id, wallet, target, kind, verdict, reason, txHash)
  │  (Sepolia, chain 11155111 — origin)
  ▼
SentinelReactor (reactive contract, Lasna, chain 5318007)
  │  react() classifies the verdict:
  │    BLOCK + threat reason (NOT_FREE=4, SIMULATION_FAILED=5,
  │    BLOCKLISTED=10)  → request callback trip
  │    PASS (all checks green) → request callback record-ready
  │    other BLOCK reasons (e.g. QUOTA_USED) → no callback (not a threat)
  ▼  SYSTEM.requestCallbackV_1_0 → Sepolia
SentinelBreaker.recordVerdict(reactor, verdict, reason, wallet, target)
  │  (Sepolia, chain 11155111 — destination; auth: onlyServiceProvider
  │   [Sepolia callback proxy 0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4]
  │   + onlyCallbackSender [reactor address])
  │  appends the alert; on a threat verdict sets halted=true
  ▼
Sentinel agent reads breaker.halted() BEFORE every execution:
  halted → verdict forced BLOCK / HALTED, nothing is sent.
  Owner (throwaway deployer) can reset() the breaker.
```

Components (all new files, written Nov 16+, zero changes to Nov 10 code):
- `contracts/SentinelRegistry.sol` — UNCHANGED Nov 10 code, redeployed fresh
  on Sepolia as the origin (a dependency redeploy, not a rewrite).
- `contracts/reactive/SentinelReactor.sol` — NEW. Inherits AbstractReactive
  (Reactive-Network/reactive-lib-omni). Subscribes to DecisionLogged on the
  Sepolia registry; react() classifies + requests callbacks. Owner-only
  setBreaker() (deploy order needs it: reactor first, breaker second).
- `contracts/reactive/SentinelBreaker.sol` — NEW. Inherits AbstractCallback
  (proxy = Sepolia callback proxy, sender = reactor). recordVerdict(),
  halted flag + alert log, owner-only reset().
- `agent/reactive-guard.js` — NEW. Agent side: logs verdicts to the Sepolia
  registry (throwaway operator key), checks breaker.halted() before
  executing, refuses while halted. Wires the AI into the loop.

Funding (per contract, from the docs):
- Reactor (Lasna): pays reactive txs in lREACT — must be funded.
- Breaker (Sepolia): pays callback execution in SepETH — must be funded.
- Deploys on Sepolia cost SepETH; deploys on Lasna cost lREACT.

Deployment order: (1) registry on Sepolia → (2) reactor on Lasna (registry
address + DecisionLogged topic0 as constructor args) → (3) breaker on
Sepolia (proxy + reactor address) → (4) setBreaker on reactor (owner-only)
→ (5) fund reactor (lREACT) + breaker (SepETH) → (6) demo: log one PASS
verdict + one BLOCK/threat verdict on Sepolia → collect Lasna react() txs
+ Sepolia callback txs → verify breaker state → agent halts.

## 4. What is built so far (no funds needed)

- reactive-lib-omni installed (forge) as a dependency (tag v0.1.0,
  3ade0dcf).
- SentinelReactor + SentinelBreaker written; **forge tests 11/11 PASS**
  (test/reactive.t.sol — anvil simulation with a mock system contract
  etched at the real SYSTEM address; proves subscription, threat
  classification, callback payload, breaker auth + halt/reset). Full
  repo suite 21/21 PASS (solc bumped 0.8.24 → 0.8.29 in foundry.toml;
  registry source untouched).
- agent/reactive-guard.js written (breaker gate + verdict logging via
  cast; fails gracefully pre-deploy). script/DeployReactive.s.sol
  written (two-chain forge script). reactive/config.json + RUNLOG.md
  in place. Throwaway deployer 0x0b71114B48693Ca3D40d7e644aDF6eb0676AF690
  generated (key only in reactive/.env.local, 600, gitignored).
- Local anvil simulation of the full loop (registry → reactor → breaker)
  with pranked system/proxy — proves the logic; the REAL reactive delivery
  (system contract calling react()) can only be proven on Lasna after
  funding.

## 5. Funding — THE blocker (verified, not assumed)

- lREACT comes ONLY from the Lasna faucet contracts, which take Sepolia
  ETH (1 SepETH → 100 lREACT): Sepolia faucet 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434,
  Base Sepolia faucet 0x2afaFD298b23b62760711756088F75B7409f5967.
- The only headless Sepolia source, the pk910 PoW faucet, requires a
  custom captcha to START a session (`requiredForStart: true`,
  https://sepolia-faucet.pk910.de/api/getFaucetConfig) — not solvable from
  a headless VM, and bypassing an anti-bot captcha is not attempted.
- All other Sepolia faucets (Alchemy, QuickNode, Infura, Chainlink) need
  accounts; the Google Cloud Web3 faucet needs only a Google sign-in and
  gives 0.05 SepETH/day — doable by the USER on their phone in ~2 minutes.
- Nov 10 precedent: the user funded the BSC-testnet deployer (0.03 tBNB)
  from the official faucet on their phone in ~1 minute. Same class of ask.
- ASK (for the user, via the parent agent): claim 0.05 Sepolia ETH from
  the Google Cloud Web3 faucet (Google sign-in) and send it to the fresh
  throwaway deployer address recorded in §6. That one pot covers:
  Sepolia deploys + breaker funding + the Lasna faucet conversion
  (0.01–0.02 SepETH → 1–2 lREACT for reactor funding + Lasna deploys).
- tBNB does NOT help here: BSC testnet is not a Lasna origin, and lREACT
  cannot be bought with tBNB.

## 6. Throwaway deployer (testnet only)

- Fresh keypair generated Nov 16 for THIS build only. Address recorded
  here; the private key lives ONLY in `reactive/.env.local` (chmod 600,
  gitignored, never in any report, log, or chat). Never the user's wallet.
- Address: 0x0b71114B48693Ca3D40d7e644aDF6eb0676AF690

## 7. Remaining after funding

1. Deploy in §3 order; record every address + tx hash in
   `reactive/RUNLOG.md` with explorer links (Lasna:
   https://lasna.reactscan.net; Sepolia: https://sepolia.etherscan.io).
2. Demo the full loop twice (PASS + BLOCK/threat); capture tx hashes for
   origin event → react() → callback → breaker state.
3. Verify contracts on Sourcify (Lasna chain 5318007, Sepolia 11155111).
4. Demo video < 3 min + DoraHacks submission (USER registers + submits;
   agent prepares repo link, addresses, tx hashes, video script).
5. Update README with the Reactive track section + submission links.
