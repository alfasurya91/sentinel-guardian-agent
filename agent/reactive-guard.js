#!/usr/bin/env node
/**
 * Sentinel x Reactive — agent-side guard (Reactive Omni Buildathon, Nov 2026).
 *
 * This is the AI side of the reactive loop. The Sentinel verification
 * pipeline produces verdicts; this script (a) logs them to the Sepolia
 * SentinelRegistry (the origin event the Lasna reactor watches), and
 * (b) reads the Sepolia SentinelBreaker BEFORE any execution and refuses
 * to act while the breaker is tripped.
 *
 *   node agent/reactive-guard.js --check
 *       Print breaker state (halted / reason / alert count).
 *   node agent/reactive-guard.js --guard
 *       Exit 0 if clear, exit 2 if halted (the gate the agent calls
 *       before executing anything). Prints the reason either way.
 *   node agent/reactive-guard.js --log <kind> <verdict> <reason> <wallet> <target>
 *       Log one verdict to the Sepolia registry (signed with the throwaway
 *       testnet deployer key from reactive/.env.local — never the user's
 *       wallet, never a mainnet key).
 *       kind: MINT=0 CLAIM=1 APPROVE=2 OTHER=3
 *       verdict: PASS=0 BLOCK=1
 *       reason: NONE=0 NO_CODE=1 UNVERIFIED_SOURCE=2 QUOTA_USED=3
 *               NOT_FREE=4 SIMULATION_FAILED=5 PREVIEW_MISMATCH=6
 *               OVER_VALUE_CAP=7 DAILY_CAP_REACHED=8 POLICY_PAUSED=9
 *               BLOCKLISTED=10
 *
 * Reads/writes go through `cast` (foundry), the same tooling the Nov 10
 * deployment used. The private key is read from reactive/.env.local into
 * the child process env only — it is never printed, never logged.
 *
 * Addresses come from reactive/config.json (filled by the deploy script).
 * Until the contracts are deployed, --check/--guard report NOT_DEPLOYED
 * and --log refuses.
 */
import { readFileSync, existsSync } from 'node:fs';
import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const CONFIG = JSON.parse(readFileSync(join(ROOT, 'reactive', 'config.json'), 'utf8'));

const SEPOLIA_RPC = process.env.SEPOLIA_RPC || CONFIG.sepoliaRpc;
const ZERO32 = '0x' + '00'.repeat(32);

function run(cmd, args, envExtra = {}) {
  return new Promise((resolve, reject) => {
    execFile(cmd, args, { env: { ...process.env, ...envExtra } }, (err, stdout, stderr) => {
      if (err) {
        const e = new Error((stderr || stdout || err.message).trim().split('\n').pop());
        e.stdout = stdout;
        reject(e);
      } else {
        resolve(stdout.trim());
      }
    });
  });
}

function loadDeployerKey() {
  const envPath = join(ROOT, 'reactive', '.env.local');
  if (!existsSync(envPath)) throw new Error('reactive/.env.local missing — deployer key not generated');
  const line = readFileSync(envPath, 'utf8')
    .split('\n')
    .find((l) => l.startsWith('REACTIVE_DEPLOYER_PRIVATE_KEY='));
  if (!line) throw new Error('REACTIVE_DEPLOYER_PRIVATE_KEY not found in reactive/.env.local');
  return line.split('=')[1].trim();
}

function requireDeployed(name) {
  const addr = CONFIG[name];
  if (!addr) throw new Error(`${name} not deployed yet — see reactive/config.json (run the deploy first)`);
  return addr;
}

async function breakerHalted() {
  const breaker = requireDeployed('breaker');
  const out = await run('cast', ['call', breaker, 'halted()(bool)', '--rpc-url', SEPOLIA_RPC]);
  return out === 'true';
}

async function breakerState() {
  const breaker = requireDeployed('breaker');
  const [halted, reason, count] = await Promise.all([
    // NOTE: the return-type annotation is REQUIRED — without it `cast call`
    // returns raw hex (0x...0001), never the string 'true', so a bare
    // 'halted()' comparison silently reports CLEAR even while tripped
    // (caught live 2026-11-16: guard said CLEAR with halted=true on-chain).
    run('cast', ['call', breaker, 'halted()(bool)', '--rpc-url', SEPOLIA_RPC]),
    run('cast', ['call', breaker, 'haltedReason()(uint8)', '--rpc-url', SEPOLIA_RPC]),
    run('cast', ['call', breaker, 'alertCount()(uint256)', '--rpc-url', SEPOLIA_RPC]),
  ]);
  return { halted: halted === 'true', haltedReason: Number(reason), alertCount: Number(count) };
}

async function logVerdict(kind, verdict, reason, wallet, target) {
  const registry = requireDeployed('registry');
  const key = loadDeployerKey();
  // The deployer is the registry owner; logDecision auth passes via
  // isOperator only if set — the deploy script authorizes the deployer as
  // operator, and wallet == deployer also passes. We log with the deployer
  // as both wallet and sender.
  const txHash = await run(
    'cast',
    [
      'send', registry,
      'logDecision(address,address,uint8,uint8,uint8,bytes32)',
      wallet, target, String(kind), String(verdict), String(reason), ZERO32,
      '--rpc-url', SEPOLIA_RPC,
      '--private-key', key,
    ],
    {}
  );
  // cast send prints the tx hash on stdout; the key never appears in output.
  return txHash;
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  try {
    if (cmd === '--check') {
      const s = await breakerState();
      console.log(JSON.stringify({ breaker: CONFIG.breaker, ...s }, null, 2));
    } else if (cmd === '--guard') {
      const s = await breakerState();
      if (s.halted) {
        console.log(`HALTED: breaker tripped, reason=${s.haltedReason}, alerts=${s.alertCount} — refusing to execute.`);
        process.exit(2);
      }
      console.log(`CLEAR: breaker not halted, alerts=${s.alertCount} — execution allowed.`);
    } else if (cmd === '--log') {
      const [kind, verdict, reason, wallet, target] = rest;
      if ([kind, verdict, reason, wallet, target].some((x) => x === undefined)) {
        throw new Error('usage: --log <kind> <verdict> <reason> <wallet> <target>');
      }
      const out = await logVerdict(Number(kind), Number(verdict), Number(reason), wallet, target);
      console.log(out);
    } else {
      console.log('usage: node agent/reactive-guard.js (--check | --guard | --log <kind> <verdict> <reason> <wallet> <target>)');
      process.exit(1);
    }
  } catch (e) {
    console.error('reactive-guard: ' + e.message);
    process.exit(1);
  }
}

main();
