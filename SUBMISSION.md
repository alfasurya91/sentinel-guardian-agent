# BNB Hack — submission pack (drafts)

> Everything below is a **draft for the project owner (zkera) to submit
> himself**. Placeholders in [brackets] get filled once the GitHub repo is
> pushed and the demo video is recorded.

## Form answers

**Project name:** Sentinel — Guardian Agent for Agent ID Wallets

**Track:** AI

**Challenge:** BNB Hack — AI Track (autonomous agents on BNB Chain)

**One-liner:**
Sentinel is an AI guardian that verifies every mint/claim opportunity
on-chain before an Agent ID wallet acts — and proves it, with a public
on-chain logbook of every decision.

**Description (long):**
Agent ID wallets can transact autonomously, and the Agent ID ecosystem runs a
constant stream of free mints and claims. Chasing them manually is slow
(FCFS pools close in about a minute); letting an agent chase them blind is
dangerous (unverified look-alike contracts, "free" mints that are actually
paid, already-spent quotas, mints that aren't open yet).

Sentinel productizes the discipline a careful human operator uses:
1) WATCH a list of opportunities (contract + exact call + eligibility views).
2) VERIFY each one read-only: bytecode exists, source is verified (Sourcify),
the wallet's free quota is unused, the price is truly zero, an eth_call
simulation of the exact mint call passes, and the opportunity fits the
wallet's on-chain policy in SentinelRegistry (free-only, per-tx value cap,
daily tx cap, pause switch). Execution additionally requires the Binance
Agentic Wallet preview to show no unexpected balance/allowance changes.
3) EXECUTE only on a full PASS, strictly inside those rails — and
4) LOG every verdict (PASS/BLOCK + machine-readable reason + execution tx
hash) to the SentinelRegistry logbook, so the guardian's track record is
publicly auditable by anyone.

The demo runs against live BSC mainnet state for a real Agent ID wallet:
Sentinel correctly BLOCKS the still-closed Agent Ape Club free mint
(simulation reverts MintClosed), and BLOCKS Niche Society and Night Shift
Agents whose free quotas that wallet already used — three transactions a
naive agent would have wasted or misspent, reduced to zero.

**Repo:** https://github.com/alfasurya91/sentinel-guardian-agent
**Demo video:** [link — to be recorded, script below]
**Contract (BSC testnet):** [address — deploy pending faucet funding of the
disposable deployer 0x9858d01522CdfFADC6022fc20cDf68988e339a3D; local anvil
deployment on chain-id 97 is complete, see DEPLOYMENT.md]
**Contact / X:** @pralintang

## Tweet draft (submission requirement: tag @BNBChain, #BNBHack)

> Meet Sentinel 🛡️ — an AI guardian for Agent ID wallets on @BNBChain.
>
> It verifies every mint/claim on-chain BEFORE acting (verified source ✓,
> free quota ✓, simulation ✓, on-chain policy ✓), executes only inside
> user-set Safety Rails, and logs every decision on-chain.
>
> Verify first. Execute second. Log everything. #BNBHack
>
> https://github.com/alfasurya91/sentinel-guardian-agent [demo link]

## Demo video script (90 seconds, owner records)

**0:00–0:15 — The problem (screen: a busy free-mint feed / FCFS timer)**
"Free mints for Agent ID wallets drop constantly — and the good ones are
gone in a minute. Check them all by hand and you're too slow. Let an agent
run blind and it will mint the wrong contract, pay for a 'free' mint, or
burn gas on a mint that isn't even open."

**0:15–0:35 — The guardian (screen: README pipeline diagram → SentinelRegistry on screen)**
"Sentinel is a guardian agent. Before it acts, it verifies every
opportunity on-chain: real bytecode, verified source, your free quota
actually unused, price truly zero, and a full simulation of the exact mint
call. Your rules — free-only, value caps, a daily limit, a pause switch —
live in an on-chain policy contract, not in a config file you have to trust."

**0:35–1:05 — Live run (terminal: `node agent/verify.js`)**
"Watch it run against live BSC mainnet, for a real Agent ID wallet.
Agent Ape Club: quota free, contract verified — but the simulation reverts:
MintClosed. BLOCKED, and it keeps watching without wasting gas.
Niche Society: mintedBy equals two — the free quota is already spent.
BLOCKED. Night Shift: same story. Three bad transactions a naive agent
would have sent — Sentinel sent zero."

**1:05–1:25 — The logbook (screen: SentinelRegistry decisions / DEPLOYMENT.md)**
"And every decision is written to an on-chain logbook — target, verdict,
reason, transaction hash. Anyone can audit whether the guardian followed
its owner's rules. That's the point: an agent you don't have to trust,
because you can check."

**1:25–1:30 — Close**
"Sentinel. Verify first. Execute second. Log everything. Built on BNB Chain."
