// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/DeFiLending.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1e24); // 1 million tokens
    }
}

// New version of DeFiLending for upgrade testing
contract DeFiLendingV2 is DeFiLending {
    function version() external pure returns (string memory) {
        return "v2";
    }
}

contract DeFiLendingTest is Test {
    DeFiLending public lending;
    MockERC20 public token;
    ERC1967Proxy public proxy;
    address public user = address(0x123);
    address public admin = address(this);

    function setUp() public {
        token = new MockERC20();

        // Deploy the first implementation
        DeFiLending implementation = new DeFiLending();

        // Deploy proxy with initialization
        proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSignature("initialize(address)", address(token))
        );

        // Cast proxy address to DeFiLending interface
        lending = DeFiLending(address(proxy));

        // Give test user some tokens
        token.transfer(user, 1e22); // 10,000 tokens
    }

    function testDeposit() public {
        vm.startPrank(user);
        token.approve(address(lending), 1e21);
        lending.deposit(1e21);
        vm.stopPrank();

        assertEq(lending.deposits(user), 1e21);
        assertEq(token.balanceOf(address(lending)), 1e21);
    }

    function testBorrowAndRepay() public {
        vm.startPrank(user);
        token.approve(address(lending), 1e21);
        lending.deposit(1e21);
        lending.borrow(5e20);
        assertEq(lending.borrows(user), 5e20);

        token.approve(address(lending), 5e20);
        lending.repay(5e20);
        assertEq(lending.borrows(user), 0);
        vm.stopPrank();
    }

    function testUpgrade() public {
        // Deploy the new implementation (v2)
        DeFiLendingV2 newImplementation = new DeFiLendingV2();

        // Upgrade the proxy to the new implementation
        vm.prank(admin);
        lending.upgradeToAndCall(address(newImplementation), "");

        // Verify that the upgrade was successful
        assertEq(
            DeFiLendingV2(address(lending)).version(),
            "v2"
        );
    }
}
