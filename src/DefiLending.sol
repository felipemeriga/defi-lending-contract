// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

// Struct for tracking borrow information (assumes amounts are in USDC's smallest unit, 6 decimals)
struct BorrowInfo {
    uint256 principal;
    uint256 lastAccrued; // timestamp of last interest accrual
}

contract DeFiLending is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // The USDC token contract (assumed to have 6 decimals)
    IERC20 public token;

    // Collateral deposits (in USDC, 6 decimals)
    mapping(address => uint256) public deposits;
    uint256 public totalDeposits;

    // Deposit shares and a global deposit index (for yield accrual).
    // Users receive shares proportional to their deposit at the time of deposit.
    mapping(address => uint256) public depositShares;
    uint256 public totalDepositShares;
    uint256 public depositIndex; // starts at 1e18 for high precision

    // Borrowing info: tracks the borrower's debt and when interest was last accrued.
    mapping(address => BorrowInfo) public borrows;
    uint256 public totalBorrows;

    // Interest rate: expressed as an annual percentage (e.g., 5 means 5% per year).
    uint256 public interestRate;
    // Liquidation threshold as a percentage (e.g., 75 means borrow up to 75% of collateral)
    uint256 public liquidationThreshold;

    event Deposited(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);
    event Borrowed(address indexed user, uint256 amount, uint256 newPrincipal);
    event Repaid(address indexed user, uint256 amount, uint256 remainingPrincipal);
    event Liquidated(address indexed user, uint256 collateralSeized);

    // Initialize with the USDC token address.
    function initialize(address _token) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        token = IERC20(_token); // USDC token should have 6 decimals.
        interestRate = 5; // 5% annual interest
        liquidationThreshold = 75; // 75% LTV
        depositIndex = 1e18; // High precision starting index
    }

    // This function is mostly called by owner during contract upgrade, since we don't have
    // how to initialize again the implementation contract
    function setLiquidationThresholdPublic(uint _liquidationThreshold) public onlyOwner {
        setLiquidationThreshold(_liquidationThreshold);
    }

    function setLiquidationThreshold(uint _liquidationThreshold) internal {
        liquidationThreshold = _liquidationThreshold;
    }

    function setDepositIndex(uint _depositIndex) public onlyOwner {
        if(depositIndex == 0) {
            depositIndex = _depositIndex;
        }
    }

    // ---------- Deposits & Withdrawals ----------

    // When a user deposits USDC, they receive deposit shares.
    function deposit(uint256 amount) external {
        require(amount > 0, "Deposit must be > 0");
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        // Record raw deposits.
        deposits[msg.sender] += amount;
        totalDeposits += amount;

        // Calculate deposit shares. (For USDC, amount is in 6 decimals.)
        uint256 shares = (amount * 1e18) / depositIndex;
        depositShares[msg.sender] += shares;
        totalDepositShares += shares;

        emit Deposited(msg.sender, amount, shares);
    }

    function sharesCurrentValue() external view returns (uint256 shareValues) {
        uint256 amount = (depositShares[msg.sender] * depositIndex) / 1e18;
        return amount;
    }

    // Withdraw function redeems deposit shares for USDC based on the current deposit index.
    function withdraw(uint256 shares) external {
        require(shares > 0, "Shares must be > 0");
        require(depositShares[msg.sender] >= shares, "Not enough shares");

        // Determine current value of shares.
        uint256 amount = (shares * depositIndex) / 1e18;

        depositShares[msg.sender] -= shares;
        totalDepositShares -= shares;

        // Update global deposits to reflect withdrawal.
        totalDeposits -= amount;

        // Transfer USDC back to the user.
        require(token.transfer(msg.sender, amount), "Withdrawal failed");

        emit Withdrawn(msg.sender, amount, shares);
    }

    // ---------- Borrowing & Interest Accrual ----------

    // Internal function to accrue interest for a borrower.
    // Using simple interest: interest = principal * rate * timeElapsed / (100 * 365 days)
    function _accrueInterest(address borrower) internal returns (uint256 interestAccrued) {
        BorrowInfo storage info = borrows[borrower];
        if (info.principal > 0) {
            uint256 timeElapsed = block.timestamp - info.lastAccrued;
            interestAccrued = (info.principal * interestRate * timeElapsed) / (100 * 365 days);

            // Update the borrower's debt and global debt totals.
            info.principal += interestAccrued;
            totalBorrows += interestAccrued;
            info.lastAccrued = block.timestamp;

            // Increase depositIndex so depositors benefit from accrued interest.
            // This assumes totalDeposits > 0.
            if (totalDeposits > 0) {
                uint256 indexIncrement = (interestAccrued * depositIndex) / totalDeposits;
                depositIndex += indexIncrement;
                // Optionally, update totalDeposits to reflect increased pool value.
                totalDeposits += interestAccrued;
            }
        } else {
            borrows[borrower].lastAccrued = block.timestamp;
        }
        return interestAccrued;
    }

    // Helper view function to verify interest without state change.
    function verifyInterest(address borrower) external view returns (uint256) {
        BorrowInfo storage info = borrows[borrower];
        if (info.principal > 0) {
            uint256 timeElapsed = block.timestamp - info.lastAccrued;
            uint256 interest = (info.principal * interestRate * timeElapsed) / (100 * 365 days);
            return interest;
        }
        return 0;
    }

    function toString(uint256 value) internal pure returns(string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // Borrow function: user borrows USDC up to a threshold based on their collateral.
    function borrow(uint256 amount) external {
        require(deposits[msg.sender] > 0, "No collateral provided");

        _accrueInterest(msg.sender);
        BorrowInfo storage info = borrows[msg.sender];
        uint256 maxBorrowable = (deposits[msg.sender] * liquidationThreshold) / 100;
        require(info.principal + amount <= maxBorrowable,
            string(abi.encodePacked(
                "Insufficient collateral. Your collateral: ", toString(deposits[msg.sender]),
                ". Liquidation threshold: ", toString(liquidationThreshold),
                ". The amount you asked to borrow was: ", toString(amount),
                ". The maximum amount you can borrow is: ", toString(maxBorrowable)
            ))
        );

        info.principal += amount;
        totalBorrows += amount;
        require(token.transfer(msg.sender, amount), "Borrow transfer failed");

        emit Borrowed(msg.sender, amount, info.principal);
    }

    // Repay function: the borrower repays their debt.
    // If the borrower repays more than the outstanding debt, the extra is distributed to depositors.
    function repay(uint256 amount) external {
        require(amount > 0, "Repayment must be > 0");

        // Accrue interest first; this updates both the borrower's debt and the depositIndex.
        _accrueInterest(msg.sender);
        BorrowInfo storage info = borrows[msg.sender];
        require(info.principal > 0, "No outstanding loan");
        require(amount == info.principal, "Repayment must equal outstanding debt");

        // Transfer the exact repayment amount from the borrower.
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        // Adjust the global totalBorrows.
        totalBorrows -= info.principal;
        // Clear the borrower's debt.
        info.principal = 0;
        info.lastAccrued = block.timestamp;

        emit Repaid(msg.sender, amount, info.principal);
    }

    // Liquidation: if a borrower's debt exceeds their allowed threshold, seize collateral.
    function liquidate(address user) external onlyOwner {
        BorrowInfo storage info = borrows[user];
        require(info.principal > 0, "No active loan");

        _accrueInterest(user);
        uint256 maxBorrowable = (deposits[user] * liquidationThreshold) / 100;
        require(info.principal > maxBorrowable, "User not eligible for liquidation");

        uint256 debt = info.principal;
        deposits[user] -= debt;
        totalDeposits -= debt;
        totalBorrows -= debt;

        info.principal = 0;
        info.lastAccrued = block.timestamp;

        emit Liquidated(user, debt);
    }

    // Required for UUPS upgradeability.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
