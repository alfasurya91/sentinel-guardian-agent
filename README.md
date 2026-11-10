# Sentinel — the guardian agent for Agent ID wallets

**Verify first. Execute second. Log everything.**

Sentinel is an AI-agent guardian for Binance **Agent ID** wallets on BNB Chain.
It watches mint and claim opportunities, verifies each one on-chain *before*
acting, executes only what passes every check inside the owner's **Safety
Rails**, and writes every decision — pass or block — to a public on-chain
logbook.

Built for the **BNB Hack (AI track)**.

---

## The problem

Agent ID wallets can act on-chain autonomously — and the Agent ID ecosystem
now runs a constant stream of free mints, claims and airdrops. Chasing them by
hand is a full-time job; letting an agent chase them blind is dangerous:

- **FCFS pools vanish in a minute**, so slow manual verification = missed mint.
- **Look-alike contracts are everywhere**: unverified code, paid mints dressed
  up as "free", quotas that are already spent, mints that are not open yet.
- An agent with a wallet and no rails will eventually sign something it
  shouldn't — a paid mint, an unlimited approval, a call that reverts and
  burns gas, or worse.

Humans solved this with discipline: *simulate before broadcast, confirm before
signing, exact approvals only, free means zero*. Sentinel turns that
discipline into code — and proves it followed the rules, on-chain.

## How Sentinel works

```
            ┌──────────────────── WATCH ────────────────────┐
            │  watchlist: mint/claim opportunities (contracts │
            │  + the exact calls + eligibility views)         │
            └──────────────────────┬──────────────────────────┘
                                   ▼
   ┌──────────────────── VERIFY (read-only, per opportunity) ───────────────┐
   │ 1 code_exists      target holds bytecode                               │
   │ 2 verified_source  Sourcify reports a source match                     │
   │ 3 quota            the wallet's free quota is actually unused          │
   │ 4 price            call value respects free-only / value caps          │
   │ 5 simulation       eth_call of the exact mint call does not revert     │
   │ 6 policy           SentinelRegistry.evaluate() — the on-chain rails    │
   │ 7 baw_preview      Binance Agentic Wallet preview (dry-run): the       │
   │                    preview must show no unexpected balance/allowance   │
   │                    changes — only then may anything be signed          │
   └──────────────────────┬──────────────────────────┬─────────────────────┘
                    ALL PASS ▼                ANY FAIL ▼
              execute (under rails)        BLOCK — nothing is sent
                    │                            │
                    └──────────┬─────────────────┘
                               ▼
                 LOG — logDecision() appends the verdict,
                 reason code and execution tx hash to the
                 on-chain logbook (SentinelRegistry)
```

Every check in the pipeline produces **named evidence** (the actual view-call
results, the actual revert reason), so a verdict is never "trust me" — it is
a small audit trail, and the summary of it lives permanently on-chain.

### Live demo — real verdicts, real chain state

`node agent/verify.js --save` runs the pipeline against **live BSC mainnet**
(read-only) for the wallet this product was built around. Latest run
(`demo/sample-report.md`):

| Opportunity | Verdict | Why |
|---|---|---|
| Agent Ape Club free mint (still pending) | ⛔ BLOCK / `SIMULATION_FAILED` | Contract verified, quota free — but the mint call reverts `MintClosed()`. The mint simply isn't open yet; Sentinel keeps watching instead of burning gas. |
| Niche Society (free mints #1–2) | ⛔ BLOCK / `QUOTA_USED` | `mintedBy(wallet) = 2` — the free quota was already claimed (tokenIds 1441/1442). The next mint is paid, and paid is out of policy. |
| Night Shift Agents (first mint free) | ⛔ BLOCK / `QUOTA_USED` | Wallet already holds the NFT (tokenId 893); the free slot is spent. |

Three blocks might look like "nothing happened" — that *is* the product.
A naive agent would have sent three transactions: one revert, two paid mints
the owner never approved. Sentinel sent zero.

## The Safety Rails

Sentinel's policy is not a settings file you have to trust — the canonical
copy lives in `SentinelRegistry` on-chain, set by the wallet owner:

- **Simulate before broadcast** — a reverting call is never sent.
- **Confirm before signing** — execution goes through the wallet's own
  preview; unexpected balance/allowance changes in the preview = BLOCK
  (`PREVIEW_MISMATCH`).
- **Free-only by default** — `freeOnly` + `maxValuePerTx` cap every call;
  any paid opportunity is blocked unless the owner deliberately raises the cap.
- **Exact-amount approvals only** — no unlimited allowances, ever.
- **Daily tx cap** — the guardian can only execute N transactions per day.
- **Pause switch** — one flag stops everything.
- **Fail closed** — no policy on-chain, an RPC failure mid-check, or an
  unverifiable source all mean BLOCK, not "proceed and hope".

## Architecture

| Piece | What it does |
|---|---|
| `contracts/SentinelRegistry.sol` | Per-wallet policy + append-only decision logbook + `evaluate()` policy view. The public, auditable record. |
| `agent/verify.js` | The verification pipeline (Node, zero dependencies — raw JSON-RPC + the `baw` CLI). Produces a structured verdict JSON + markdown report. |
| `agent/watchlist.json` | Opportunities under watch: target contract, the exact mint call, and the eligibility/quota views to check. |
| `agent/policy.json` | Local mirror of the on-chain policy used by the off-chain pipeline in dry-run mode. |
| `demo/sample-report.{json,md}` | A real dry-run report against BSC mainnet (regenerate any time). |
| `script/deploy-local.sh` | One-command local deployment + first logbook entry (anvil, chain-id 97). |

Deployment status (testnet): see `DEPLOYMENT.md`.

## Quickstart

```bash
# contracts
forge install   # pulls forge-std
forge build
forge test      # 10 tests: policy, logging, cap enforcement

# agent dry-run (read-only, BSC mainnet)
node agent/verify.js           # print the verdict report
node agent/verify.js --save    # also write demo/sample-report.{json,md}

# local deployment demo
bash script/deploy-local.sh
```

**Safety note:** in this MVP the agent is *read-only on mainnet by design*.
It never signs and never sends a mainnet transaction; the execution stage is
represented by the Binance Agentic Wallet **preview** step in dry-run mode.
The only keys in the repo's orbit are a disposable testnet deployer
(`.env.local`, gitignored) and anvil's built-in dev accounts.

## Roadmap

- **Auto-execution under standing authorization** — when an owner pre-approves
  a narrow scope (this contract class, zero value, this daily cap), Sentinel
  executes passing opportunities instantly — built for FCFS pools that close
  in a minute — and still logs every decision.
- **Opportunity discovery** — scan new contract deployments + ecosystem feeds
  to propose watchlist entries automatically (owner approves additions).
- **Contract reputation scoring** — combine source verification, deployer
  history, holder distribution and past Sentinel verdicts into a risk score
  per mint contract.
- **Multi-wallet fleets** — one guardian watching many Agent ID wallets, each
  with its own on-chain policy.
- **x402-paid verified-opportunity feed** — other agents pay per call for
  Sentinel's verified, simulation-tested opportunity stream: security as a
  service, agent-to-agent.

## Business model sketch

- **Guardian subscription** for Agent ID power users and agent operators:
  monitoring + verification + logbook, priced per wallet per month.
- **Verified-opportunity API (x402)** — per-call micropayments from other
  agents that want Sentinel-grade verification before they act.
- **Project-side "Sentinel-verified" listing** — mint/claim projects pay for
  a verification review so guarded wallets auto-trust their launch.

## Why this is real

Sentinel productizes a workflow that already runs every day: an Agent ID
wallet (`zkera.ai`) whose free mints are hunted under exactly these rails —
verify on-chain, simulate, preview, confirm, execute, log. The watchlist in
this repo contains that wallet's actual history: mints it completed, the
quota it spent, and the free mint it is still waiting for. The guardian's
first job is the one it already does — it just does it in public now.
