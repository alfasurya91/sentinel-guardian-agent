# Sentinel — sample dry-run report

- Mode: **DRY-RUN (read-only). Nothing was signed or broadcast.**
- Chain: BNB Smart Chain mainnet (chainId 56)
- Wallet: `0x16c3a45B80A27F81e511D04610C7726a0aa2098c`
- Generated: 2026-11-10T05:10:40.063Z
- Policy: freeOnly=true, maxValuePerTx=0 wei, dailyTxCap=5, paused=false

## Agent Ape Club — free mint (LIVE watch)

- Contract: `0x31da612e74db1751f0B474b4607493B4fa4d9bd5`
- Watch status: pending
- **Verdict: BLOCK** (reason: SIMULATION_FAILED)

| Check | Result | Evidence |
|---|---|---|
| code_exists | ✅ pass | 7513 bytes of bytecode at 0x31da612e74db1751f0B474b4607493B4fa4d9bd5 |
| verified_source | ✅ pass | Sourcify match=exact_match, verifiedAt=2026-10-25T12:19:04Z |
| quota | ✅ pass | balanceOf(address) = 0 (fail if > 0) |
| price | ✅ pass | call value 0 wei within policy (freeOnly=true) |
| simulation | ❌ fail | eth_call freeMint(uint256,uint256) reverted with MintClosed() (0x589ed34b) |
| policy | ✅ pass | freeOnly=true, maxValuePerTx=0 wei, daily cap 0/5 used |
| baw_preview | ⏭️ skip | not reached — pipeline already BLOCKED at 'simulation'. In dry-run the wallet preview only runs for fully passing opportunities. |

## Niche Society — free mints #1–2 (historical demo)

- Contract: `0xA522C9257BB00B832f49f550e25e790Ace0Be585`
- Watch status: historical
- **Verdict: BLOCK** (reason: QUOTA_USED)

| Check | Result | Evidence |
|---|---|---|
| code_exists | ✅ pass | 12123 bytes of bytecode at 0xA522C9257BB00B832f49f550e25e790Ace0Be585 |
| verified_source | ✅ pass | Sourcify match=exact_match, verifiedAt=2026-10-29T00:34:53Z |
| quota | ❌ fail | free quota consumed: mintedBy(wallet) vs free allowance of 2 — mintedBy(address) = 2 (fail if >= 2) |
| price | ⏭️ skip | no mint call configured (historical entry) |
| simulation | ⏭️ skip | no mint call configured (historical entry) |
| policy | ✅ pass | freeOnly=true, maxValuePerTx=0 wei, daily cap 0/5 used |
| baw_preview | ⏭️ skip | not reached — pipeline already BLOCKED at 'quota'. In dry-run the wallet preview only runs for fully passing opportunities. |

## Night Shift Agents — first mint free (historical demo)

- Contract: `0x427aed3f7427b48e45f5e648105aa1b77724cf14`
- Watch status: historical
- **Verdict: BLOCK** (reason: QUOTA_USED)

| Check | Result | Evidence |
|---|---|---|
| code_exists | ✅ pass | 16072 bytes of bytecode at 0x427aed3f7427b48e45f5e648105aa1b77724cf14 |
| verified_source | ✅ pass | Sourcify match=exact_match, verifiedAt=2026-10-26T17:23:06Z |
| quota | ❌ fail | wallet already holds this NFT (free first-mint slot spent) — balanceOf(address) = 1 (fail if > 0) |
| price | ⏭️ skip | no mint call configured (historical entry) |
| simulation | ⏭️ skip | no mint call configured (historical entry) |
| policy | ✅ pass | freeOnly=true, maxValuePerTx=0 wei, daily cap 0/5 used |
| baw_preview | ⏭️ skip | not reached — pipeline already BLOCKED at 'quota'. In dry-run the wallet preview only runs for fully passing opportunities. |

_Produced by `node agent/verify.js --save` against live BSC mainnet state. Read-only: no transaction was signed or sent._
