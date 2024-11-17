// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {Registry} from "src/L2/Registry.sol";
import {ReverseRegistrar} from "src/L2/ReverseRegistrar.sol";
import "src/util/Constants.sol";

contract DeployReverseRegistrar is Script {
    function run() external {
        // Fetch deployer's private key and address
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Fetch the deployed Registry contract's address
        address registryAddress = vm.envAddress("REGISTRY_ADDR");
        Registry registry = Registry(registryAddress);

        // Deploy the ReverseRegistrar contract
        ReverseRegistrar reverseRegistrar = new ReverseRegistrar(
            registry,
            deployerAddress, // Deployer as owner
            BASE_REVERSE_NODE
        );

        // Set ownership for 'addr.reverse' and its base subnode
        bytes32 reverseLabel = keccak256("reverse");
        bytes32 baseReverseLabel = keccak256("80002105"); // Replace with actual label if necessary
        registry.setSubnodeOwner(0x0, reverseLabel, deployerAddress);
        registry.setSubnodeOwner(REVERSE_NODE, baseReverseLabel, address(reverseRegistrar));

        // Log the deployed ReverseRegistrar address
        console.log(address(reverseRegistrar));

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
