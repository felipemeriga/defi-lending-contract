// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {DeFiLending} from "../src/DeFiLending.sol";

contract UpgradeDeFiLending is Script {
    function run() external {
        vm.startBroadcast();

        // Replace with your actual proxy address
        address PROXY_ADDRESS = 0x6b338b0ab70B08ABEf6F4344F8dB3Bd3e42591Cc;

        // Deploy new implementation
        DeFiLending newImplementation = new DeFiLending();
        console.log("New Implementation Address:", address(newImplementation));

        // Upgrade the proxy
        DeFiLending(payable(PROXY_ADDRESS)).upgradeToAndCall(address(newImplementation), "");

        console.log("Upgrade successful!");

        vm.stopBroadcast();
    }
}
