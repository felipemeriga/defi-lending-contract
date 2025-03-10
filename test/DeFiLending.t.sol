// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/DeFiLending.sol";

// Mock USDC token for testing (6 decimals)
contract MockUSDC is ERC20 {
    constructor() ERC20("MockUSDC", "USDC") {
        // Mint 100,000 USDC to deployer, scaled to 6 decimals.
        _mint(msg.sender, 100_000 * 1e6);
    }
    // Override decimals to 6

    function decimals() public pure override returns (uint8) {
        return 6;
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
    MockUSDC public token;
    ERC1967Proxy public proxy;
    address public user = address(0x123);
    address public user2 = address(0x1234);
    address public user3 = address(0x12345);
    address public user4 = address(0x123456);
    address public provider = address(0x1234567);
    address public admin = address(this);

    function setUp() public {
        token = new MockUSDC();

        // Deploy the first implementation
        DeFiLending implementation = new DeFiLending();

        // Deploy proxy with initialization
        proxy =
            new ERC1967Proxy(address(implementation), abi.encodeWithSignature("initialize(address)", address(token)));

        // Cast proxy address to DeFiLending interface
        lending = DeFiLending(address(proxy));

        // Transfer 1,000 USDC to the user and provider (scaled to 6 decimals).
        token.transfer(user, 5_000 * 1e6);
        token.transfer(user2, 5_000 * 1e6);
        token.transfer(user3, 5_000 * 1e6);
        token.transfer(user4, 5_000 * 1e6);
        token.transfer(provider, 5_000 * 1e6);
    }

    function testDeposit() public {
        vm.startPrank(user);
        // Approve and deposit 100 USDC.
        token.approve(address(lending), 100 * 1e6);
        lending.deposit(100 * 1e6);
        vm.stopPrank();

        assertEq(lending.deposits(user), 100 * 1e6);
        assertEq(token.balanceOf(address(lending)), 100 * 1e6);
    }

    function testBorrowAndRepayWithInterest() public {
        vm.startPrank(user);
        // Approve and deposit 100 USDC.
        token.approve(address(lending), 100 * 1e6);
        lending.deposit(100 * 1e6);

        // User borrows 50 tokens
        lending.borrow(50 * 1e6);
        (uint256 initialDebt,) = lending.borrows(user);
        assertEq(initialDebt, 50 * 1e6);

        uint256 firstDepositShares = lending.depositShares(user);
        console.log(firstDepositShares);

        // Warp time forward by 30 days (30 * 86400 seconds)
        uint256 thirtyDays = 30 * 86400;
        vm.warp(block.timestamp + thirtyDays);

        // Trigger interest accrual by performing a small borrow (e.g. 5 USDC)
        // This call will first accrue interest on the existing debt.
        lending.borrow(5);
        (uint256 newDebt,) = lending.borrows(user);
        // Expect new debt to be higher than just principal + 5 because interest accrued.
        assertGt(newDebt, initialDebt + 5);

        // Now, the user repays the debt
        uint256 repayAmount = newDebt;
        token.approve(address(lending), repayAmount);
        lending.repay(repayAmount);
        (uint256 remainingDebt,) = lending.borrows(user);
        // Remaining debt should be less than the debt before repayment.
        assertLt(remainingDebt, newDebt);
        vm.stopPrank();
    }

    function testBorrowAboveThreshold() public {
        vm.startPrank(user);
        // User deposits 100 USDC tokens as collateral
        token.approve(address(lending), 100 * 1e6);
        lending.deposit(100 * 1e6);

        vm.expectRevert("Insufficient collateral");
        // Expect the test to fail, due to borrowing above liquidation threshold
        lending.borrow(90 * 1e6);
    }

    function testLiquidation() public {
        // User deposits 100 USDC tokens as collateral.
        vm.startPrank(user);
        token.approve(address(lending), 100 * 1e6);
        lending.deposit(100 * 1e6);

        // With a liquidation threshold of 75%, maximum allowed borrow = 75% of collateral = 75e6.
        lending.borrow(75 * 1e6);
        (uint256 initialDebt,) = lending.borrows(user);
        assertEq(initialDebt, 75 * 1e6);
        vm.stopPrank();

        // Warp time forward to let interest accrue significantly (e.g., 180 days).
        uint256 warpTime = 180 * 86400;
        vm.warp(block.timestamp + warpTime);

        // Now, try to trigger interest accrual without increasing debt.
        // Calling borrow(0) will first accrue interest.
        // We expect it to revert if the new debt (with accrued interest) exceeds the allowed threshold.
        vm.startPrank(user);
        vm.expectRevert("Insufficient collateral");
        lending.borrow(0);
        vm.stopPrank();

        // Retrieve the accrued debt.
        // Since the last transaction reverted, because the borrow + interest exceeds the
        // threshold, the current principal will be equal the borrowed amount.
        (uint256 accruedDebt,) = lending.borrows(user);
        uint256 currentInterest = lending.verifyInterest(user);
        console.log("Accrued Debt plus interest:", accruedDebt + currentInterest);
        uint256 limit = (100 * 1e6 * 75) / 100;
        console.log("Collateral-based Limit:", limit);

        // Ensure that the accrued debt now exceeds the maximum allowed (liquidation condition met).
        require(accruedDebt + currentInterest > limit, "Debt has not exceeded liquidation threshold");

        // Liquidation is performed by admin.
        vm.prank(admin);
        lending.liquidate(user);

        // After liquidation, the user's debt should be reset to 0,
        // and collateral (deposits) should be reduced.
        (uint256 finalDebt,) = lending.borrows(user);
        uint256 finalDeposit = lending.deposits(user);
        assertEq(finalDebt, 0);
        assertLt(finalDeposit, 100 * 1e6);
    }

    function testWithdraw() public {
        // User deposits 100 USDC tokens as collateral.
        vm.startPrank(user);
        // Approve transaction for sending 100 USDC tokens to the user wallet
        token.approve(address(lending), 100 * 1e6);
        lending.deposit(100 * 1e6);

        // Borrow bellow the threshold for checking interest over time
        lending.borrow(50 * 1e6);
        (uint256 initialDebt,) = lending.borrows(user);
        assertEq(initialDebt, 50 * 1e6);

        // Advancing 365 days
        uint256 warpTime = 365 * 86400;
        vm.warp(block.timestamp + warpTime);

        // Now, the user repays his debit
        uint256 repayAmount = 50 * 1e6 + lending.verifyInterest(user);
        token.approve(address(lending), repayAmount);

        lending.repay(repayAmount);
        assertGt(lending.depositIndex(), 1e18);
        uint256 currentShares = lending.depositShares(user);
        lending.withdraw(currentShares);

        vm.stopPrank();
    }

    // This function will simulate an user providing liquidity depositing USDC
    // while another one will be borrow some money
    function testIncreasedShareValues() public {
        // User deposits 1000 USDC tokens as collateral.
        vm.startPrank(user);
        // Approve transaction for sending 1000 USDC tokens to the user wallet
        token.approve(address(lending), 1000 * 1e6);
        lending.deposit(1000 * 1e6);
        // Borrow bellow the threshold for checking interest over time
        lending.borrow(500 * 1e6);

        vm.stopPrank();

        // Provider deposits 100 USDC tokens as collateral.
        vm.startPrank(provider);
        // Approve transaction for sending 100 USDC tokens to the user wallet
        token.approve(address(lending), 1000 * 1e6);
        lending.deposit(1000 * 1e6);
        vm.stopPrank();

        // Advancing 365 days
        uint256 warpTime = 365 * 86400;
        vm.warp(block.timestamp + warpTime);

        vm.startPrank(user);
        // User that borrowed, will repay with interest
        uint256 repayAmount = 500 * 1e6 + lending.verifyInterest(user);
        token.approve(address(lending), repayAmount);
        lending.repay(repayAmount);
        vm.stopPrank();

        // The user that provided liquidity will withdraw his shares that raised up their values
        vm.startPrank(provider);
        uint256 currentProviderShares = lending.depositShares(provider);
        lending.withdraw(currentProviderShares);
        uint256 currentBalance = token.balanceOf(provider);
        console.log("Current provider balance: ", currentBalance);
        assertGt(currentBalance, 1000 * 1e6);
        vm.stopPrank();
    }

    function testUpgrade() public {
        // Deploy the new implementation (v2)
        DeFiLendingV2 newImplementation = new DeFiLendingV2();

        // Upgrade the proxy to the new implementation
        vm.prank(admin);
        lending.upgradeToAndCall(address(newImplementation), "");

        // Verify that the upgrade was successful
        assertEq(DeFiLendingV2(address(lending)).version(), "v2");
    }
}
