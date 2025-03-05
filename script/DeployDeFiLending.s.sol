// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {DeFiLending} from "../src/DeFiLending.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployDeFiLending is Script {
    function run() external {
        vm.startBroadcast();

        // Replace with the token you want to use (e.g., USDC address)
        // This is my custom USDC address for SEPOLIA
        address USDC_ADDRESS = 0xae624D2005c193aA546e29Ecc3346307A3dDfdD2;

        // Deploy the implementation contract
        DeFiLending lendingImpl = new DeFiLending();
        console.log("DeFiLending Implementation Address:", address(lendingImpl));

        // Deploy the proxy with encoded initializer call
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(lendingImpl),
            abi.encodeWithSignature("initialize(address)", USDC_ADDRESS)
        );
        console.log("DeFiLending Proxy Address:", address(proxy));

        vm.stopBroadcast();
    }
}
