// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeFiLending is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    IERC20 public token;
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public borrows;
    uint256 public totalDeposits;
    uint256 public totalBorrows;
    uint256 public interestRate;
    uint256 public liquidationThreshold;

    event Deposited(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(address indexed user, uint256 amount);

    function initialize(address _token) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        token = IERC20(_token);
        interestRate = 5; // Example: 5% annual interest rate
        liquidationThreshold = 75; // Example: 75% LTV
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Deposit must be greater than zero");
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        deposits[msg.sender] += amount;
        totalDeposits += amount;

        emit Deposited(msg.sender, amount);
    }

    function borrow(uint256 amount) external {
        uint256 maxBorrowable = (deposits[msg.sender] * liquidationThreshold) / 100;
        require(deposits[msg.sender] > 0, "No collateral provided");
        require(maxBorrowable >= borrows[msg.sender] + amount, "Insufficient collateral");

        borrows[msg.sender] += amount;
        totalBorrows += amount;
        require(token.transfer(msg.sender, amount), "Borrow transfer failed");

        emit Borrowed(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        require(amount > 0, "Repayment amount must be greater than zero");
        require(borrows[msg.sender] >= amount, "Exceeds borrowed amount");
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        borrows[msg.sender] -= amount;
        totalBorrows -= amount;

        emit Repaid(msg.sender, amount);
    }

    function liquidate(address user) external onlyOwner {
        require(borrows[user] > 0, "User has no active loans");
        require((deposits[user] * liquidationThreshold) / 100 < borrows[user], "Not eligible for liquidation");

        uint256 liquidationAmount = borrows[user];
        deposits[user] -= liquidationAmount;
        borrows[user] = 0;
        totalDeposits -= liquidationAmount;
        totalBorrows -= liquidationAmount;

        emit Liquidated(user, liquidationAmount);
    }

    // ✅ Correctly override _authorizeUpgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
