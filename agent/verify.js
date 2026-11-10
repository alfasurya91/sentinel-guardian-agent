#!/usr/bin/env node
/**
 * Sentinel — verification pipeline (dry-run, read-only).
 *
 * For every opportunity in watchlist.json, Sentinel runs the same checks the
 * guardian performs before it may act for a Binance Agent ID wallet:
 *
 *   1. code_exists      target address actually holds bytecode
 *   2. verified_source  Sourcify reports a source match for the target
 *   3. quota            the wallet's free quota / eligibility views pass
 *   4. price            the call's value respects free-only / value caps
 *   5. simulation       eth_call of the exact mint call does not revert
 *   6. policy           mirror of SentinelRegistry.evaluate() on agent/policy.json
 *   7. baw_preview      (execution stage) Binance Agentic Wallet preview —
 *                       only ever reached when 1–6 all PASS, and only with
 *                       SENTINEL_BAW_PREVIEW=1. Preview never broadcasts.
 *
 * Mainnet is READ-ONLY here: this script never signs and never sends.
 * Usage: node agent/verify.js [--save]
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const RPCS = ['https://bsc.drpc.org', 'https://bsc-dataseed1.defibit.io'];
const CHAIN_ID = 56;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------- RPC ----
let rpcIdx = 0;
async function rpc(method, params) {
  let lastErr;
  for (let attempt = 0; attempt < RPCS.length * 2; attempt++) {
    const url = RPCS[(rpcIdx + attempt) % RPCS.length];
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
      });
      const json = await res.json();
      if (json.error) {
        const e = new Error(json.error.message || 'rpc error');
        e.data = json.error.data;
        // Execution reverts (code 3, or error data present) are ANSWERS,
        // not transport failures — never retry them as if they were.
        if (json.error.code === 3 || (typeof json.error.data === 'string' && json.error.data.startsWith('0x'))) {
          e.kind = 'revert';
          throw e;
        }
        e.kind = 'transport'; // rate limits etc: rotate + back off
        throw e;
      }
      rpcIdx = (rpcIdx + attempt) % RPCS.length;
      await sleep(350); // be gentle with public endpoints; no batching
      return json.result;
    } catch (err) {
      if (err.kind === 'revert') throw err;
      lastErr = err;
      await sleep(err.kind === 'transport' ? 2500 : 600);
    }
  }
  lastErr.kind = lastErr.kind || 'transport';
  throw lastErr;
}

// ------------------------------------------------------------ ABI bits ----
function encodeArg(v) {
  if (typeof v === 'string' && v.startsWith('0x') && v.length === 42) {
    return v.slice(2).toLowerCase().padStart(64, '0'); // address
  }
  return BigInt(v).toString(16).padStart(64, '0'); // uint256
}
function encodeCall(selector, args) {
  return selector + args.map(encodeArg).join('');
}
function substitute(v, ctx) {
  if (v === '$WALLET') return ctx.wallet;
  if (v === '$AGENT_ID') return ctx.agentId;
  return v;
}
const KNOWN_ERRORS = {
  // Custom-error selectors observed on real watchlist contracts (verified
  // against the contract with `cast sig` during development).
  '0x589ed34b': 'MintClosed()', // Agent Ape Club
};

function decodeRevert(err) {
  const data = typeof err?.data === 'string' ? err.data : '';
  if (data.startsWith('0x08c379a0')) {
    // Error(string)
    try {
      const len = Number(BigInt('0x' + data.slice(74, 138)));
      const bytes = Buffer.from(data.slice(138, 138 + len * 2), 'hex');
      return `revert: ${bytes.toString('utf8')}`;
    } catch { /* fall through */ }
  }
  const sel = data.slice(0, 10);
  if (KNOWN_ERRORS[sel]) return `reverted with ${KNOWN_ERRORS[sel]} (${sel})`;
  if (err?.message) return err.message;
  return 'reverted (no reason string)';
}

// ------------------------------------------------------------- checks ----
async function checkCodeExists(entry) {
  const code = await rpc('eth_getCode', [entry.contract, 'latest']);
  const bytes = (code.length - 2) / 2;
  return bytes > 0
    ? { name: 'code_exists', status: 'pass', evidence: `${bytes} bytes of bytecode at ${entry.contract}` }
    : { name: 'code_exists', status: 'fail', reason: 'NO_CODE', evidence: 'eth_getCode returned 0x (empty)' };
}

async function checkVerifiedSource(entry) {
  try {
    const res = await fetch(`https://sourcify.dev/server/v2/contract/${CHAIN_ID}/${entry.contract}`);
    if (!res.ok) throw new Error(`sourcify http ${res.status}`);
    const j = await res.json();
    const match = j.match || j.runtimeMatch || null;
    if (match) {
      return {
        name: 'verified_source', status: 'pass',
        evidence: `Sourcify match=${match}, verifiedAt=${j.verifiedAt || 'n/a'}`,
      };
    }
    return { name: 'verified_source', status: 'fail', reason: 'UNVERIFIED_SOURCE', evidence: 'Sourcify reports no match' };
  } catch (e) {
    // Fail closed: an unverifiable source signal is treated as no signal.
    return { name: 'verified_source', status: 'fail', reason: 'UNVERIFIED_SOURCE', evidence: `source lookup failed: ${e.message}` };
  }
}

async function checkQuota(entry, ctx) {
  if (!entry.quota?.length) return { name: 'quota', status: 'skip', evidence: 'no quota views configured for this entry' };
  const parts = [];
  for (const q of entry.quota) {
    const args = q.args.map((a) => substitute(a, ctx));
    const data = encodeCall(q.selector, args);
    const out = await rpc('eth_call', [{ to: entry.contract, data }, 'latest']);
    const value = BigInt(out);
    const limit = BigInt(q.failIf.value);
    const failed =
      (q.failIf.op === '>' && value > limit) ||
      (q.failIf.op === '>=' && value >= limit) ||
      (q.failIf.op === '==' && value === limit);
    parts.push(`${q.signature} = ${value.toString()} (fail if ${q.failIf.op} ${q.failIf.value})`);
    if (failed) {
      return { name: 'quota', status: 'fail', reason: q.onFailReason, evidence: `${q.label} — ${parts.join('; ')}` };
    }
  }
  return { name: 'quota', status: 'pass', evidence: parts.join('; ') };
}

function checkPrice(entry, policy) {
  if (!entry.mint) return { name: 'price', status: 'skip', evidence: 'no mint call configured (historical entry)' };
  const value = BigInt(entry.mint.valueWei || '0');
  if (policy.freeOnly && value > 0n) {
    return { name: 'price', status: 'fail', reason: 'NOT_FREE', evidence: `call value ${value} wei > 0 under free-only policy` };
  }
  if (value > BigInt(policy.maxValuePerTxWei)) {
    return { name: 'price', status: 'fail', reason: 'OVER_VALUE_CAP', evidence: `call value ${value} wei exceeds maxValuePerTx ${policy.maxValuePerTxWei}` };
  }
  return { name: 'price', status: 'pass', evidence: `call value ${value} wei within policy (freeOnly=${policy.freeOnly})` };
}

async function checkSimulation(entry, ctx) {
  if (!entry.mint) return { name: 'simulation', status: 'skip', evidence: 'no mint call configured (historical entry)' };
  const args = entry.mint.args.map((a) => substitute(a, ctx));
  const data = encodeCall(entry.mint.selector, args);
  const value = '0x' + BigInt(entry.mint.valueWei || '0').toString(16);
  try {
    const out = await rpc('eth_call', [{ from: ctx.wallet, to: entry.contract, data, value }, 'latest']);
    return { name: 'simulation', status: 'pass', evidence: `eth_call ${entry.mint.signature} succeeded (returned ${out.slice(0, 66)}${out.length > 66 ? '…' : ''})` };
  } catch (e) {
    if (e.kind === 'revert') {
      return { name: 'simulation', status: 'fail', reason: 'SIMULATION_FAILED', evidence: `eth_call ${entry.mint.signature} ${decodeRevert(e)}` };
    }
    // Transport failure: the check could not be completed. Sentinel fails
    // closed — an unverifiable opportunity is a blocked opportunity.
    return {
      name: 'simulation', status: 'error', reason: 'SIMULATION_FAILED',
      evidence: `simulation could not be completed (RPC error: ${e.message}) — treated as BLOCK, fail closed`,
    };
  }
}

function checkPolicy(entry, policy, executedToday) {
  // Mirror of SentinelRegistry.evaluate(wallet, value, wouldExecute=true).
  const value = entry.mint ? BigInt(entry.mint.valueWei || '0') : 0n;
  if (policy.paused) return { name: 'policy', status: 'fail', reason: 'POLICY_PAUSED', evidence: 'policy.paused = true (kill switch)' };
  if (policy.freeOnly && value > 0n) return { name: 'policy', status: 'fail', reason: 'NOT_FREE', evidence: 'free-only policy and value > 0' };
  if (value > BigInt(policy.maxValuePerTxWei)) return { name: 'policy', status: 'fail', reason: 'OVER_VALUE_CAP', evidence: 'value exceeds maxValuePerTx' };
  if (policy.dailyTxCap > 0 && executedToday >= policy.dailyTxCap) {
    return { name: 'policy', status: 'fail', reason: 'DAILY_CAP_REACHED', evidence: `${executedToday}/${policy.dailyTxCap} executions already logged today` };
  }
  return {
    name: 'policy', status: 'pass',
    evidence: `freeOnly=${policy.freeOnly}, maxValuePerTx=${policy.maxValuePerTxWei} wei, daily cap ${executedToday}/${policy.dailyTxCap} used`,
  };
}

function bawStatus() {
  return new Promise((resolve) => {
    execFile('baw', ['wallet', 'status', '--json'], { timeout: 10000 }, (err, stdout) => {
      if (err && err.code === 'ENOENT') return resolve({ found: false });
      if (err) return resolve({ found: true, status: `unavailable (${err.message.split('\n')[0]})` });
      try {
        const j = JSON.parse(stdout);
        resolve({ found: true, status: j.status || j.state || 'responded' });
      } catch {
        resolve({ found: true, status: 'responded (unparsed)' });
      }
    });
  });
}

async function checkBawPreview(priorChecks) {
  const blocked = priorChecks.find((c) => c.status === 'fail' || c.status === 'error');
  const baw = await bawStatus();
  if (blocked) {
    return {
      name: 'baw_preview', status: 'skip',
      evidence: `not reached — pipeline already BLOCKED at '${blocked.name}'. In dry-run the wallet preview only runs for fully passing opportunities.`,
    };
  }
  if (!baw.found) {
    return { name: 'baw_preview', status: 'skip', evidence: 'baw CLI not installed in this environment; preview step not executed (dry-run)' };
  }
  if (process.env.SENTINEL_BAW_PREVIEW !== '1') {
    return {
      name: 'baw_preview', status: 'skip',
      evidence: `baw present (wallet status: ${baw.status}); preview is opt-in via SENTINEL_BAW_PREVIEW=1 and was not invoked in this dry-run`,
    };
  }
  return {
    name: 'baw_preview', status: 'skip',
    evidence: 'SENTINEL_BAW_PREVIEW=1 set, but preview execution is not wired into the MVP demo path — see README roadmap',
  };
}

// --------------------------------------------------------------- main ----
const watchlist = JSON.parse(readFileSync(join(HERE, 'watchlist.json'), 'utf8'));
const policy = JSON.parse(readFileSync(join(HERE, 'policy.json'), 'utf8'));
const ctx = { wallet: watchlist.wallet, agentId: watchlist.agentId };

const statePath = join(ROOT, 'demo', 'state.json');
let executedToday = 0;
if (existsSync(statePath)) {
  try {
    const s = JSON.parse(readFileSync(statePath, 'utf8'));
    if (s.day === new Date().toISOString().slice(0, 10)) executedToday = s.executedToday || 0;
  } catch { /* ignore */ }
}

const results = [];
for (const entry of watchlist.entries) {
  const checks = [];
  checks.push(await checkCodeExists(entry));
  checks.push(await checkVerifiedSource(entry));
  checks.push(await checkQuota(entry, ctx));
  checks.push(checkPrice(entry, policy));
  checks.push(await checkSimulation(entry, ctx));
  checks.push(checkPolicy(entry, policy, executedToday));
  checks.push(await checkBawPreview(checks));

  const firstFail = checks.find((c) => c.status === 'fail' || c.status === 'error');
  results.push({
    id: entry.id,
    name: entry.name,
    contract: entry.contract,
    kind: entry.kind,
    watchStatus: entry.status,
    checks,
    verdict: firstFail ? 'BLOCK' : 'PASS',
    reason: firstFail ? firstFail.reason : 'NONE',
  });
}

const report = {
  product: 'Sentinel — Agent ID wallet guardian',
  mode: 'DRY-RUN (read-only). Nothing was signed or broadcast.',
  chain: 'BNB Smart Chain mainnet (chainId 56)',
  generatedAt: new Date().toISOString(),
  wallet: ctx.wallet,
  policy,
  results,
};

const json = JSON.stringify(report, null, 2);
console.log(json);

if (process.argv.includes('--save')) {
  writeFileSync(join(ROOT, 'demo', 'sample-report.json'), json + '\n');
  const icon = { pass: '✅', fail: '❌', skip: '⏭️', error: '⚠️' };
  let md = `# Sentinel — sample dry-run report\n\n`;
  md += `- Mode: **${report.mode}**\n- Chain: ${report.chain}\n- Wallet: \`${report.wallet}\`\n- Generated: ${report.generatedAt}\n`;
  md += `- Policy: freeOnly=${policy.freeOnly}, maxValuePerTx=${policy.maxValuePerTxWei} wei, dailyTxCap=${policy.dailyTxCap}, paused=${policy.paused}\n\n`;
  for (const r of results) {
    md += `## ${r.name}\n\n- Contract: \`${r.contract}\`\n- Watch status: ${r.watchStatus}\n- **Verdict: ${r.verdict}** (reason: ${r.reason})\n\n`;
    md += `| Check | Result | Evidence |\n|---|---|---|\n`;
    for (const c of r.checks) md += `| ${c.name} | ${icon[c.status] || c.status} ${c.status} | ${String(c.evidence).replace(/\|/g, '/')} |\n`;
    md += `\n`;
  }
  md += `_Produced by \`node agent/verify.js --save\` against live BSC mainnet state. Read-only: no transaction was signed or sent._\n`;
  writeFileSync(join(ROOT, 'demo', 'sample-report.md'), md);
  console.error('saved demo/sample-report.json and demo/sample-report.md');
}
