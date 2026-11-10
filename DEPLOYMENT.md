# Sentinel — deployment record

## BSC testnet (chainId 97) — ✅ DEPLOYED 2026-11-10

- Disposable deployer (testnet-only, generated for this project):
  `0x9858d01522CdfFADC6022fc20cDf68988e339a3D`
  (private key lives only in `.env.local`, chmod 600, gitignored)
- Funded by the user via the official faucet 2026-11-10: **0.03 tBNB**
- **SentinelRegistry: `0x641E21b0A53872f6D11534783cdA825C001bCa4a`**
  Explorer: https://testnet.bscscan.com/address/0x641E21b0A53872f6D11534783cdA825C001bCa4a

| Step | Tx hash |
|---|---|
| Deploy SentinelRegistry | `0xcd1046316d13941b1c249ac49a1f9b735f4afa71b49a2db3319c7152472090eb` |
| `setOperator(deployer, true)` | `0xb24b51c033d2033dd9e57f1dcec1c65afd8c43e96ced93f9d5334ea4e33915bb` |
| `setPolicy(freeOnly=true, paused=false, maxValuePerTx=0, dailyTxCap=5)` | `0x43f35a175707e5c7d09c72d2443b83c8fc76ba6919ab5ed06054977a500f0c0c` |
| `logDecision(user wallet, Agent Ape Club, MINT, BLOCK, SIMULATION_FAILED)` | `0xd215bb2957fbdbbb86a0c38cbde6841d707953e43af83064078ecc999b2b9091` |

Read-back verified on-chain: decisionsCount = 1; getPolicy(deployer) = (exists, freeOnly=true, paused=false, 0, 5).
Tooling note: BSC testnet enforces a minimum priority fee (0.1 gwei tip) that cast 1.9.0's default EIP-1559 estimation violates (tip cap 1 wei) — sends must use `--legacy --gas-price 1000000000`.
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
