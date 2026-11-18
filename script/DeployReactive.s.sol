// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title DeployReactive — two-chain deploy for the Sentinel x Reactive build.
/// @notice Run once per chain (a forge script has a single --rpc-url):
///
///   # 1. Sepolia: deploy the origin registry
///   forge script script/DeployReactive.s.sol --rpc-url sepolia --broadcast
///
///   # 2. Lasna: deploy the reactor (needs the registry address)
///   REGISTRY_ADDRESS=0x... forge script script/DeployReactive.s.sol --rpc-url lasna --broadcast
///
///   # 3. Sepolia: deploy the breaker (needs the reactor address)
///   REACTOR_ADDRESS=0x... forge script script/DeployReactive.s.sol --rpc-url sepolia --broadcast
///
///   # 4. Lasna: point the reactor at the breaker (owner-only)
///   cast send <reactor> "setBreaker(address)" <breaker> --rpc-url lasna --private-key $REACTIVE_DEPLOYER_PRIVATE_KEY
///
///   # 5. Fund: reactor with lREACT (Lasna), breaker with SepETH (Sepolia).
///
/// Deployer key: REACTIVE_DEPLOYER_PRIVATE_KEY from reactive/.env.local
/// (fresh throwaway testnet-only keypair — never the user's wallet).
/// The script writes the deployed addresses to reactive/config.json via
/// console output; copy them in by hand (forge scripts cannot write
/// outside broadcast/ by design — the addresses are also in broadcast/).
import { Script, console } from "forge-std/Script.sol";
import { SentinelRegistry } from "../contracts/SentinelRegistry.sol";
import { SentinelReactor } from "../contracts/reactive/SentinelReactor.sol";
import { SentinelBreaker } from "../contracts/reactive/SentinelBreaker.sol";
import { IPayable } from "reactive-lib-omni/interfaces/IPayable.sol";

contract DeployReactive is Script {
    /// @notice Sepolia callback proxy (dev.reactive.network/origins-and-destinations).
    address internal constant SEPOLIA_PROXY = 0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4;

    function run() external {
        uint256 deployerKey = vm.envUint("REACTIVE_DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        console.log("deployer:", deployer);
        console.log("chainId:", block.chainid);

        vm.startBroadcast(deployerKey);

        if (block.chainid == 11155111) {
            // Sepolia leg: registry (step 1) or breaker (step 3).
            address reactor = vm.envOr("REACTOR_ADDRESS", address(0));
            if (reactor == address(0)) {
                SentinelRegistry registry = new SentinelRegistry();
                console.log("registry:", address(registry));
                // Authorize the deployer as operator so the agent can log
                // verdicts with any wallet as the subject.
                registry.setOperator(deployer, true);
                console.log("operator set:", deployer);
            } else {
                SentinelBreaker breaker =
                    new SentinelBreaker(IPayable(payable(SEPOLIA_PROXY)), reactor);
                console.log("breaker:", address(breaker));
                console.log("breaker callback sender (reactor):", reactor);
            }
        } else if (block.chainid == 5318007) {
            // Lasna leg: reactor (step 2).
            address registry = vm.envAddress("REGISTRY_ADDRESS");
            SentinelReactor reactorContract = new SentinelReactor(registry);
            console.log("reactor:", address(reactorContract));
            console.log("reactor origin registry:", registry);
        } else {
            revert("DeployReactive: run on Sepolia (11155111) or Lasna (5318007) only");
        }

        vm.stopBroadcast();
    }
}
