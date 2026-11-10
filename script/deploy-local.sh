#!/usr/bin/env bash
# Local stand-in deployment for SentinelRegistry.
#
# Why local? The BSC testnet faucets (BNB Chain / QuickNode / Chainstack)
# are captcha- or UI-gated and cannot fund the disposable deployer from a
# headless VM. This script deploys to a local anvil instance running with
# chain-id 97 (BSC testnet's id) using anvil's built-in unlocked dev
# account, and performs the same three transactions the testnet deploy
# will perform once the deployer is funded:
#   1. deploy SentinelRegistry
#   2. setPolicy(freeOnly=true, paused=false, maxValuePerTx=0, dailyTxCap=5)
#   3. logDecision(Agent Ape Club, MINT, BLOCK, SIMULATION_FAILED, 0x0)
#      — the real verdict produced by agent/verify.js against BSC mainnet.
#
# Testnet path (once funded): source .env.local, then
#   forge create contracts/SentinelRegistry.sol:SentinelRegistry \
#     --rpc-url https://bsc-testnet-rpc.publicnode.com \
#     --private-key "$SENTINEL_TESTNET_PRIVATE_KEY"
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
cd "$(dirname "$0")/.."

PORT=8546
RPC="http://127.0.0.1:$PORT"
APE=0x31da612e74db1751f0B474b4607493B4fa4d9bd5

anvil --chain-id 97 --port $PORT --silent &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null || true' EXIT
sleep 2

ACCT=$(cast wallet address --unlocked 2>/dev/null || true)
# anvil account #0 (well-known dev account, unlocked by the node itself)
FROM=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

echo "== deploy =="
OUT=$(forge create contracts/SentinelRegistry.sol:SentinelRegistry --rpc-url $RPC --unlocked --from $FROM --broadcast 2>&1)
echo "$OUT" | grep -E 'Deployer|Deployed to|Transaction Hash' || true
REGISTRY=$(echo "$OUT" | sed -n 's/.*Deployed to: //p')
DEPLOY_TX=$(echo "$OUT" | sed -n 's/.*Transaction Hash: //p')
echo "REGISTRY=$REGISTRY"

echo "== setPolicy =="
cast send $REGISTRY 'setPolicy(bool,bool,uint256,uint32)' true false 0 5 --rpc-url $RPC --unlocked --from $FROM | grep -E '^(transactionHash|status)' || true

echo "== logDecision: Agent Ape Club BLOCK / SIMULATION_FAILED =="
# enums: ActionKind MINT=0 · Verdict BLOCK=1 · ReasonCode SIMULATION_FAILED=5
cast send $REGISTRY 'logDecision(address,address,uint8,uint8,uint8,bytes32)' \
  $FROM $APE 0 1 5 0x0000000000000000000000000000000000000000000000000000000000000000 \
  --rpc-url $RPC --unlocked --from $FROM | grep -E '^(transactionHash|status)' || true

echo "== read back =="
echo "decisionsCount: $(cast call $REGISTRY 'decisionsCount()(uint256)' --rpc-url $RPC)"
cast call $REGISTRY 'getDecision(uint256)((address,address,uint8,uint8,uint8,bytes32,uint64))' 0 --rpc-url $RPC
echo "DEPLOY_TX=$DEPLOY_TX"
