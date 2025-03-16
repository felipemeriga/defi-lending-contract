// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {DeFiLending} from "../src/DeFiLending.sol";

contract UpgradeDeFiLending is Script {
    function run() external {
        vm.startBroadcast();

        // Replace with your actual proxy address
        address PROXY_ADDRESS = 0x6b338b0ab70B08ABEf6F4344F8dB3Bd3e42591Cc;
        uint NEW_LIQUIDATION_THRESHOLD = 75; // replace with your intended value
        uint NEW_DEPOSIT_INDEX = 1e18; // replace with your intended value

        // Deploy new implementation
        DeFiLending newImplementation = new DeFiLending();
        console.log("New Implementation Address:", address(newImplementation));

        // Upgrade the proxy
        DeFiLending(payable(PROXY_ADDRESS)).upgradeToAndCall(address(newImplementation), "");

        // Now, call the new function setLiquidationThresholdPublic
        // to set the new liquidation threshold
        bytes4 selector = DeFiLending.setLiquidationThresholdPublic.selector;
        bytes memory data = abi.encodeWithSelector(selector, NEW_LIQUIDATION_THRESHOLD);

        (bool success, ) = PROXY_ADDRESS.call(data);
        require(success, "Setting liquidationThreshold failed");

        // Now, call the new function setDepositIndex
        // to set the new deposit index
        bytes4 depositSelector = DeFiLending.setDepositIndex.selector;
        bytes memory depositData = abi.encodeWithSelector(depositSelector, NEW_DEPOSIT_INDEX);

        (bool depositSuccess, ) = PROXY_ADDRESS.call(depositData);
        require(depositSuccess, "Setting depositIndex failed");

        console.log("Upgrade successful!");

        vm.stopBroadcast();
    }
}