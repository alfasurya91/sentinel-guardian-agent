# Sentinel — deployment record

## BSC testnet (chainId 97) — ⏳ PENDING FAUCET

- Disposable deployer (testnet-only, generated for this project):
  `0x9858d01522CdfFADC6022fc20cDf68988e339a3D`
  (private key lives only in `.env.local`, chmod 600, gitignored)
- Balance at last check (2026-11-10): **0 tBNB**
- Faucets attempted from this environment:
  - BNB Chain official testnet faucet — web UI, captcha-gated
  - QuickNode BSC testnet faucet — returns the web UI (captcha-gated), no API drip
  - Chainstack faucet API — empty response, no drip
- **To finish the testnet deploy** (1 minute, needs a human at a faucet):
  1. Fund `0x9858d01522CdfFADC6022fc20cDf68988e339a3D` with ~0.05 tBNB from
     https://testnet.bnbchain.org/faucet-smart
  2. Then run:
     ```bash
     source .env.local
     forge create contracts/SentinelRegistry.sol:SentinelRegistry \
       --rpc-url https://bsc-testnet-rpc.publicnode.com \
       --private-key "$SENTINEL_TESTNET_PRIVATE_KEY"
     ```

## Local anvil run (chainId 97) — ✅ DONE 2026-11-10

Same three transactions the testnet deploy will perform, executed against a
local anvil instance (chain-id 97, anvil's unlocked dev account; the instance
was discarded after the run — hashes below are the run's receipts):

| Step | Tx hash |
|---|---|
| Deploy SentinelRegistry → `0x5FbDB2315678afecb367f032d93F642f64180aa3` | (create, see run log) |
| `setPolicy(freeOnly=true, paused=false, maxValuePerTx=0, dailyTxCap=5)` | `0xe312f2f627ea90c3bd1e318c5d657b3854aedab92ef79ffbceecb2b8d6076c93` |
| `logDecision(Agent Ape Club, MINT, BLOCK, SIMULATION_FAILED, 0x0)` | `0xac05dca13186861c9a149b1e8ea9068ad37ac6331ccbb4c0be9347a72a6ebbc6` |

Read-back after the run: `decisionsCount = 1`, decision #0 =
(wallet, 0x31da612e…d9bd5, MINT, BLOCK, SIMULATION_FAILED, 0x0) — the exact
verdict `agent/verify.js` produced against live BSC mainnet state
(the Agent Ape Club free mint still reverts `MintClosed()`).

Reproduce locally any time: `bash script/deploy-local.sh`
