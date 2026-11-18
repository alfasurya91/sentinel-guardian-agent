# Reactive Omni Buildathon — DoraHacks submission pack (draft)

> Everything below is a **draft for the project owner (zkera) to submit
> himself** on DoraHacks. The demo video is not recorded yet (needs the
> owner's phone/screen) and the repo is not pushed yet (needs the owner's
> go-ahead). Everything else is live and verified on-chain.

## Submission facts

- **Event:** Reactive Omni Buildathon, Nov 5 – Dec 5 2026
- **Track:** Reactive Meets AI ($1,000 first place)
- **Project:** Sentinel — Guardian Agent for Agent ID Wallets, + the new
  Reactive circuit-breaker integration (built Nov 16, 2026, all fresh code;
  the Nov 10 Sentinel registry enters as a dependency, redeployed on Sepolia)
- **Repo (NOT pushed yet — push before submitting):**
  https://github.com/alfasurya91/sentinel-guardian-agent
- **Demo video:** < 3 min, NOT recorded yet — shot-by-shot script:
  `reactive/VIDEO-SCRIPT.md` (all tx hashes already filled in)
- **DoraHacks page:** https://dorahacks.io/hackathon/reactive-omni-buildathon
  (owner registers + submits himself)

## One-liner

Sentinel's AI guardian logs every mint/claim verdict on-chain; a Reactive
contract watches those verdicts and trips an on-chain circuit-breaker in
~1 second when one is a threat — and the agent refuses to execute while
it is halted.

## Deployed contracts (testnet only)

| Contract | Chain | Address | Sourcify |
|---|---|---|---|
| SentinelRegistry (origin) | Sepolia 11155111 | 0x05B8B63297FfC9f6AB8B64F830bEc39cCC17B198 | exact_match |
| SentinelReactor | Lasna 5318007 | 0xF9dD65a93b286d3F67a1e89720f17861e21247Cf | exact_match |
| SentinelBreaker | Sepolia 11155111 | 0xAb21f451c83B1DfF52B8cA4795c509a7B388061e | exact_match |

Explorer links: Sepolia https://sepolia.etherscan.io/address/<addr> ·
Lasna https://lasna.reactscan.net/address/<addr>

## The full loop, proven live (both demos)

### Demo 1 — PASS (records ready, no halt)
- Origin (Sepolia block 12144914):
  https://sepolia.etherscan.io/tx/0xbb4c52fbf89d174ccd1d57974499a68c2341111de956b453f55c10269b624236
- react() (Lasna block 8461932):
  https://lasna.reactscan.net/tx/0x3d6a2525b26ab8a0e4bbec85abe05c9a9c5cf74d450d4068a4c1e0facc8f5706
- Callback (Sepolia block 12144915, gas limit 700,000, used 405,999):
  https://sepolia.etherscan.io/tx/0xe9ef7c89cedfa24454ee15917969cbe65ba11b0f41f71b439071ffc426183aa3
- Result: breaker alertCount=1, halted=false. Alert 0: PASS / NONE.

### Demo 2 — BLOCK + BLOCKLISTED (breaker trips)
- Origin (Sepolia block 12144918):
  https://sepolia.etherscan.io/tx/0xaf24db4b4d28eb83187149705451f5f5e7b941d3dafea47569c4380f3f1afb5f
- react() (Lasna):
  https://lasna.reactscan.net/tx/0x423bcfa79359d324e065c709535c30031254caaf21e15eb7498d8896d5b211b3
- Callback (Sepolia block 12144919):
  https://sepolia.etherscan.io/tx/0x058dca9d1048e3d5aa243d114e7d42ef8925a0939664029090c3eb416b30e3e5
- Result: breaker alertCount=2, halted=true, haltedReason=10 (BLOCKLISTED).
  Alert 1: BLOCK / BLOCKLISTED. `node agent/reactive-guard.js --guard`
  exits 2: "HALTED: breaker tripped, reason=10, alerts=2 — refusing to
  execute." The breaker is left halted as demo evidence.

## Why it is real (not a bolt-on)

- The reactor is the ONLY path from a threat verdict to an enforced halt.
  Without it, a polling bot notices minutes later or never.
- The AI is in the loop on both ends: it produces the verdicts the reactor
  routes, and it obeys the breaker the reactor trips.
- The build survived a real failure in public: v1's callback died with
  `CallbackFailure` (300k gas limit vs 200k proxy overhead + ~356k
  first-call cost); the fix (700k) and the full root-cause analysis are in
  `reactive/RUNLOG.md` and in the code comments — not hidden.

## What needs pushing (git status, not pushed yet)

Staged: `.gitmodules`, `lib/reactive-lib-omni` (reactive-lib-omni v0.1.0).
Modified: `README.md` (new Reactive section), `SUBMISSION.md` (BNB Hack
pack, untouched by this work), `foundry.toml` (solc 0.8.29 + sepolia/lasna
RPCs).
New: `REACTIVE-PLAN.md`, `agent/reactive-guard.js`,
`contracts/reactive/SentinelReactor.sol`,
`contracts/reactive/SentinelBreaker.sol`, `reactive/` (config.json,
RUNLOG.md, VIDEO-SCRIPT.md, SUBMISSION-PACK.md),
`script/DeployReactive.s.sol`, `test/reactive.t.sol`.
Also untracked from earlier work (not part of this submission unless the
owner wants them): `SPONSORS.md`, `engagement-pack.md`, `deck.pdf`,
`whitepaper.pdf`, `demo-video.mp4`, `.env.development`,
`env-development.txt`, `foundry.lock`.
NOT in git (never push): `reactive/.env.local` (throwaway deployer key,
gitignored, chmod 600).

Suggested commit once the owner says go:
`git add REACTIVE-PLAN.md agent/reactive-guard.js contracts/reactive reactive script/DeployReactive.s.sol test/reactive.t.sol README.md foundry.toml .gitmodules lib/reactive-lib-omni && git commit -m "Reactive Omni: Sentinel circuit-breaker (Sepolia -> Lasna -> Sepolia)" && git push`

## Remaining for the owner

1. Say go for the git push above (or push from his own machine).
2. Record the demo video (< 3 min) following `reactive/VIDEO-SCRIPT.md`.
3. Register + submit on DoraHacks with this pack (repo link, addresses,
   tx hashes, video link).
