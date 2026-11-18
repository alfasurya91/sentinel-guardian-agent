# Sentinel x Reactive — RUN LOG

## 2026-11-16 ~10:35–11:00 WIB — verification + build (no funds needed)

### Verified (live reads, 2026-11-16)
- Buildathon: Nov 5–Dec 5 2026, $5,500 REACT, DoraHacks, 3 tracks.
  "Reactive Meets AI" ($1,000 1st) requires the AI in the running system.
  Submission: public repo + deployed addresses + tx hashes of the FULL
  origin→callback loop + demo video < 3 min.
  Source: https://blog.reactive.network/reactive-omni-buildathon-thirty-days-to-find-out-what-one-second-buys/
- Lasna live: chain 5318007, RPC https://lasna-rpc.rnk.dev/, explorer
  https://lasna.reactscan.net/, system contract 0x8888...8888 has code.
- Origins/destinations: testnet origins = Base Sepolia 84532, Sepolia
  11155111, Lasna 5318007, Unichain Sepolia 1301. **BSC testnet (97) is
  NOT an origin.** Sepolia callback proxy
  0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4.
- reactive-lib-omni HEAD 3ade0dcf1d27e67e5783ef807e73a1b9e0c0cce8
  (tag v0.1.0), installed via `forge install`.
- DecisionLogged topic0:
  0x7e17a9c86e011e7e110d42ad938ba16ea8471b61881522d86334e7a47d2c90b6
  (keccak256("DecisionLogged(uint256,address,address,uint8,uint8,uint8,bytes32)")).

### Funding — BLOCKER (verified, not assumed)
- lREACT only via the Lasna faucet contracts (1 SepETH → 100 lREACT):
  Sepolia faucet 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434,
  Base Sepolia faucet 0x2afaFD298b23b62760711756088F75B7409f5967.
- pk910 Sepolia PoW faucet: `GET /api/getFaucetConfig` shows
  `captcha.requiredForStart: true` (custom captcha at
  faucets.pk910.de). NOT solvable headlessly; bypassing an anti-bot
  captcha is not attempted. PoW params (for the record): cryptonight,
  difficulty 11, minClaim 0.05 ETH, maxClaim 2.5 ETH.
- ASK FOR THE USER: claim 0.05 Sepolia ETH from the Google Cloud Web3
  faucet (Google sign-in, ~2 min on their phone) and send it to the
  throwaway deployer below. That one pot covers Sepolia deploys +
  breaker funding + the Lasna conversion (0.01–0.02 SepETH → 1–2 lREACT).
- tBNB does NOT help: BSC testnet is not a Lasna origin.

### Throwaway deployer (testnet only)
- Address: 0x0b71114B48693Ca3D40d7e644aDF6eb0676AF690
- Private key: ONLY in `reactive/.env.local` (chmod 600, gitignored).
  Never in any report, log, or chat. Never the user's wallet.
- Balance at generation: 0 SepETH / 0 lREACT (unfunded — see blocker).

### Built (all fresh, Nov 16; Nov 10 registry code untouched)
- `contracts/reactive/SentinelReactor.sol` — subscribes to
  DecisionLogged on the Sepolia registry; routes threat verdicts
  (BLOCK + NOT_FREE/SIMULATION_FAILED/BLOCKLISTED) and PASS verdicts to
  Sepolia callbacks; ignores other BLOCK reasons.
- `contracts/reactive/SentinelBreaker.sol` — Sepolia callback contract;
  recordVerdict() appends alerts, trips halted=true on threats;
  owner-only reset().
- `test/reactive.t.sol` — 11 tests, anvil simulation with a mock system
  contract etched at the real SYSTEM address (0x8888...8888).
- `agent/reactive-guard.js` — agent side: --check / --guard (exit 2 if
  halted) / --log (log a verdict to the Sepolia registry via cast).
  Pre-deploy it fails gracefully: "breaker not deployed yet".
- `script/DeployReactive.s.sol` — two-chain forge script (Sepolia leg:
  registry or breaker; Lasna leg: reactor), driven by env vars.
- `reactive/config.json` — chain ids, proxies, topic0, deployer address;
  registry/reactor/breaker null until deployed.
- `foundry.toml` — solc 0.8.24 → 0.8.29 (reactive-lib-omni needs
  ^0.8.29; the registry's ^0.8.24 still compiles under it) + sepolia
  and lasna RPC endpoints added. Registry source untouched.

### Test evidence (2026-11-16, forge test)
- Reactive suite: **11/11 PASS** (subscription, 3 threat kinds trip the
  breaker, PASS records ready without halting, non-threat BLOCK requests
  no callback, react() rejects non-SYSTEM, breaker rejects wrong sender
  and non-proxy caller, setBreaker/reset owner-only, reset clears halt).
- Full repo suite: **21/21 PASS** (10 pre-existing registry tests +
  11 new reactive tests). The solc bump broke nothing.

### Deploy commands (run AFTER funding lands)
```sh
cd ~/workspace/hackathon/sentinel
source reactive/.env.local   # REACTIVE_DEPLOYER_PRIVATE_KEY (never echo it)
export PATH="$HOME/.foundry/bin:$PATH"

# 1. Sepolia: origin registry
forge script script/DeployReactive.s.sol --rpc-url sepolia --broadcast
#    -> record registry address into reactive/config.json

# 2. Lasna: reactor (needs registry address)
REGISTRY_ADDRESS=0x... forge script script/DeployReactive.s.sol --rpc-url lasna --broadcast
#    -> record reactor address

# 3. Sepolia: breaker (needs reactor address)
REACTOR_ADDRESS=0x... forge script script/DeployReactive.s.sol --rpc-url sepolia --broadcast
#    -> record breaker address

# 4. Lasna: point reactor at breaker (owner-only)
cast send <reactor> "setBreaker(address)" <breaker> --rpc-url lasna --private-key $REACTIVE_DEPLOYER_PRIVATE_KEY

# 5. Fund: reactor with lREACT, breaker with SepETH
cast send 0x9b9BB25f1A81078C544C829c5EB7822d747Cf434 "request(address)" <deployer> --value 0.02ether --rpc-url sepolia --private-key $REACTIVE_DEPLOYER_PRIVATE_KEY
#    (1 SepETH -> 100 lREACT; 0.02 -> 2 lREACT; max 5 ETH/tx, amounts above 5 ETH are LOST)
cast send <reactor> --value 1ether --rpc-url lasna --private-key $REACTIVE_DEPLOYER_PRIVATE_KEY   # 1 lREACT
cast send <breaker> --value 0.005ether --rpc-url sepolia --private-key $REACTIVE_DEPLOYER_PRIVATE_KEY  # callback fuel

# 6. Demo: log one PASS + one BLOCK/BLOCKLISTED verdict, watch Lasna
#    react() txs + Sepolia callback txs, verify breaker state, run
#    agent/reactive-guard.js --guard (must exit 2 while halted).
```

### Tx hashes
- None yet — nothing deployed (funding blocker). This section fills in
  after step 6, with Lasna (reactscan) + Sepolia (etherscan) links.

### Remaining
1. USER: fund the throwaway deployer with 0.05 Sepolia ETH (Google
   Cloud Web3 faucet on their phone, ~2 min).
2. Deploy in the order above; record every address + tx hash here.
3. Demo the full loop twice (PASS + BLOCK/threat); capture tx hashes.
4. Verify contracts on Sourcify (Lasna 5318007, Sepolia 11155111).
5. Demo video < 3 min + DoraHacks submission (USER registers/submits;
   agent prepares repo link, addresses, tx hashes, video script).
6. Update README with the Reactive track section.

## 2026-11-16 ~11:04–11:23 WIB — funding landed, DEPLOYED + both demos proven

### Funding (verified on-chain)
- User funded the throwaway deployer with 0.05 Sepolia ETH (Google Cloud
  Web3 faucet, on their phone). Balance verified before deploy:
  0.05 SepETH (50000000000000000 wei) at Sepolia block 12144834.
- Total SepETH spent from the 0.05 pot: ~0.0403 (two faucet conversions
  0.02 + 0.01, deploys, breaker funding). Deployer left with ~0.0097
  SepETH + ~1.25 lREACT. No further funding needed.

### V1 deploy (all succeeded — then superseded by the gas-limit fix)
- Registry (Sepolia): 0x05B8B63297FfC9f6AB8B64F830bEc39cCC17B198
  deploy tx 0xe36159903dca9c0033fa479e757282970b81b998255b5b5baa99835a94b1c994
  operator-set tx 0xb3bbb2aeff1c4cdd44bb993abc0a25d096dac09500fe7ea2031fbbda76ef3c47
  (registry is chain-shared: SAME address/contract serves v1 and v2)
- Reactor v1 (Lasna): 0x05B8B63297FfC9f6AB8B64F830bEc39cCC17B198
  deploy tx 0xdd906b5a074aaff83c72037a974c69c5f2651f7a45d500ca080151724f35eb3d
- Breaker v1 (Sepolia): 0xF9dD65a93b286d3F67a1e89720f17861e21247Cf
  deploy tx 0x809f5946d2550afe688f89e39ac4f6309c9b1149740f5ee59ac9554f27137f3a
- setBreaker v1 tx 0xb2702f89bae807e333121e31f077d81fe3541f9b8a818a0aaf4b85c67a35ed1c
- Faucet conversion 1: tx 0xc232eab5c8c49cc66a08763e7256fca663ada027962da90f12a14c69b153a0aa
  (0.02 SepETH -> 2.1 lREACT; deployer Lasna balance 2.1 lREACT)
- Fund reactor v1 (1 lREACT): 0xe269c8b35ac8cb41f00d433d2546881f424e8bc1208e2f10cb5539f5fecb52ef
- Fund breaker v1 (0.005 SepETH): 0x2928f34d6c6498d0b0ece2c483f5dbb80b81b1ea030deb500127ee1106f3e4dd

### V1 demo — PASS loop reached react() but the callback FAILED (root-caused)
- Origin (decision 0, PASS): 0x00bb967fcb973e7e0926cf8528b6ec294381c79415bbce69f260feb2e51192cb
  (Sepolia block 12144857)
- react() v1: 0x59d57a31febbc5db53fd2d2e83e81448c41ad96c7cfeda97eeb75035964f79a2
  (Lasna block 8461287, ~1 min after origin — the reactive leg works)
- Callback v1: 0xa00d48f5534eddf66892039586ee3bdbe5ee06598fb765edbadb5f054081b644
  (Sepolia block 12144858, relayer tx, gas limit 300,000, status 1)
  BUT the proxy emitted CallbackFailure (topic 0xc8313f69...) and the
  breaker state never changed (alertCount stayed 0). The breaker was still
  charged 3,825,474 wei for the attempt.
- ROOT CAUSE (proven, not guessed): the relayer sets the deliverCallback
  tx gas limit = the callback gasLimit from the reactor config (300,000).
  The Sepolia callback proxy reserves overhead _extraGas 150,000 +
  _maxChargeGas 50,000 = 200,000 gas before calling the breaker, so the
  breaker call got only ~55,000 gas (charge math + tx gas limit confirm).
  recordVerdict costs 356,291 gas on its first call (cast estimate;
  cold storage: alerts array first push) -> OUT OF GAS -> CallbackFailure.
  Debts all 0, breaker funded, auth correct — gas was the ONLY blocker.
  (Also note: the first Lasna deploy attempt failed on insufficient funds
  BEFORE the faucet conversion — the Lasna deploy needs lREACT up front,
  so conversion must precede it. Reordered accordingly.)

### Fix — CALLBACK_GAS_LIMIT 300,000 -> 700,000 (reactor only)
- contracts/reactive/SentinelReactor.sol: CALLBACK_GAS_LIMIT = 700_000
  (covers first-call ~356k + 200k proxy overhead + relayer/tx margin).
  test/reactive.t.sol assertion updated to 700_000 with the reason.
- Faucet conversion 2: tx 0x0291b49584c9a461ab97a73b56878441840cdd51829e957f73f2e20fd92de14d
  (0.01 SepETH -> ~1.05 lREACT, insurance for the redeploy)
- forge test after fix: 21/21 PASS (10 registry + 11 reactive).
- V1 contracts SUPERSEDED. V1 reactor holds ~0.987 lREACT stranded
  (no withdraw in AbstractReactive — testnet faucet funds, accepted loss).
  V1 breaker holds ~0.005 SepETH minus the 3,825,474 wei failed-callback
  charge. Neither is referenced by config.json anymore.

### V2 deploy (current, live)
- Reactor v2 (Lasna): 0xF9dD65a93b286d3F67a1e89720f17861e21247Cf
  deploy tx 0x631d893849ae76b265b995411531c5edff2e663a14d06d856186a066ccc64029
- Breaker v2 (Sepolia): 0xAb21f451c83B1DfF52B8cA4795c509a7B388061e
  deploy tx 0x87a11d41920e243374c2a2753ca3e1536d30ae3975c593d24938b1c6f8518ddd
- setBreaker v2 tx 0x92dee0e2a315dd94d6f8d67b3ca7ac25e4d9415403e5db93b1f1c330a4fbbde4
  (verified: reactor.breaker() = breaker v2; breaker._CALLBACK_SENDER = reactor v2)
- Fund reactor v2 (0.7 lREACT): 0xfba3c5496163bf19057703e3caa56bbd0d409d41d96a4fe9c807ff260c8ba92f
- Fund breaker v2 (0.005 SepETH): 0x8ebb80241ed14e16f8fafdde31274e627eadcbcf7182c972a12c27f0326100f8

### V2 demo 1 — PASS loop: FULLY PROVEN
- Origin (decision 1, PASS): 0xbb4c52fbf89d174ccd1d57974499a68c2341111de956b453f55c10269b624236
  (Sepolia block 12144914)
- react() v2: 0x3d6a2525b26ab8a0e4bbec85abe05c9a9c5cf74d450d4068a4c1e0facc8f5706
  (Lasna block 8461932)
- Callback v2: 0xe9ef7c89cedfa24454ee15917969cbe65ba11b0f41f71b439071ffc426183aa3
  (Sepolia block 12144915, relayer tx gas limit 700,000, gas used 405,999,
  status 1, NO CallbackFailure — VerdictRecorded emitted)
- Breaker v2 after: alertCount=1, halted=false. Alert 0 = verdict 0 (PASS),
  reason 0 (NONE), wallet 0x0b71...AF690, target 0x1111...1111.

### V2 demo 2 — BLOCK/threat loop: FULLY PROVEN, breaker tripped
- Origin (decision 2, BLOCK + BLOCKLISTED): 0xaf24db4b4d28eb83187149705451f5f5e7b941d3dafea47569c4380f3f1afb5f
  (Sepolia block 12144918)
- react() v2: 0x423bcfa79359d324e065c709535c30031254caaf21e15eb7498d8896d5b211b3
- Callback v2: 0x058dca9d1048e3d5aa243d114e7d42ef8925a0939664029090c3eb416b30e3e5
  (Sepolia block 12144919, status 1, VerdictRecorded emitted)
- Breaker v2 after: alertCount=2, halted=true, haltedReason=10 (BLOCKLISTED).
  Alert 1 = verdict 1 (BLOCK), reason 10, wallet 0x0b71...AF690,
  target 0x2222...2222.
- Agent guard: `node agent/reactive-guard.js --guard` prints
  "HALTED: breaker tripped, reason=10, alerts=2 — refusing to execute."
  and exits 2. (A real agent-side bug was caught + fixed during this demo:
  the script called `halted()` without a return-type annotation, so `cast`
  returned raw hex 0x...0001, never the string 'true', and the guard
  silently reported CLEAR while halted. Fixed by annotating
  halted()(bool) / haltedReason()(uint8) / alertCount()(uint256).
  --check now reports {halted: true, haltedReason: 10, alertCount: 2}.)
- Breaker LEFT HALTED as demo evidence. Owner (throwaway deployer) can
  reset() it if a fresh demo is needed.

### Sourcify verification (exact_match, all three live contracts)
- Registry (Sepolia 0x05B8...B198): exact_match, verified 2026-11-16T04:11:27Z
- Reactor v2 (Lasna 0xF9dD...47Cf): exact_match, verified 2026-11-16T04:22:27Z
- Breaker v2 (Sepolia 0xAb21...061e): exact_match, verified 2026-11-16T04:19:34Z
- (V1 reactor/breaker were also verified exact_match before being superseded.)

### Remaining
1. Demo video < 3 min — script ready at reactive/VIDEO-SCRIPT.md with real
   tx hashes filled in; RECORDING needs the user's phone/screen (no
   headless recording path on this VM).
2. DoraHacks submission — USER registers + submits; package below is ready.
3. Push to GitHub (repo alfasurya91/sentinel-guardian-agent) — NOT pushed
   yet; needs the user's go-ahead (see git status below).
4. README Reactive section — draft written (see README.md).
