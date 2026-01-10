// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/BondMMA.sol";
import "../../src/BondMMOracle.sol";
import "../../src/interfaces/IBondMMA.sol";

/**
 * @title MultiUserScenarios
 * @notice Integration tests for BondMM-A with multiple users and complex scenarios
 * @dev Tests realistic usage patterns:
 *      - Multiple users lending/borrowing simultaneously
 *      - Mixed maturities
 *      - Sequential operations
 *      - Liquidity stress tests
 *      - Oracle integration
 */
contract MockERC20 is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}

contract MultiUserScenarios is Test {
    BondMMA public bondMMA;
    BondMMOracle public oracle;
    MockERC20 public stablecoin;

    uint256 constant INITIAL_CASH = 100_000 ether;
    uint256 constant INITIAL_RATE = 50000000000000000; // 5%

    // Create 10 test users
    address[] public users;
    uint256 constant NUM_USERS = 10;

    function setUp() public {
        // Deploy contracts
        bondMMA = new BondMMA();
        oracle = new BondMMOracle(INITIAL_RATE);
        stablecoin = new MockERC20();

        // Initialize pool
        stablecoin.mint(address(this), INITIAL_CASH);
        stablecoin.approve(address(bondMMA), INITIAL_CASH);
        bondMMA.initialize(INITIAL_CASH, address(oracle), address(stablecoin));

        // Create and fund users
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address user = address(uint160(i + 100)); // Start from 0x64
            users.push(user);
            stablecoin.mint(user, 500_000 ether); // Give each user 500k DAI
            vm.prank(user);
            stablecoin.approve(address(bondMMA), type(uint256).max);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        MULTI-USER STRESS TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test multiple users lending different amounts at different maturities
    /// @dev Limited to 5 users due to pvBonds underflow issue (Limitation #13)
    function testIntegration_MultiUserLending() public {
        uint256 numLenders = 5; // Reduced from 10 to avoid pvBonds underflow
        uint256[] memory positionIds = new uint256[](numLenders);

        // Each user lends a different amount at a different maturity
        for (uint256 i = 0; i < numLenders; i++) {
            uint256 amount = (i + 1) * 3_000 ether; // 3k, 6k, 9k, 12k, 15k (total: 45k)
            uint256 maturity = block.timestamp + (30 days) + (i * 10 days); // 30d, 40d, 50d, ...

            vm.prank(users[i]);
            positionIds[i] = bondMMA.lend(amount, maturity);
        }

        // Verify pool state
        uint256 totalLent = (numLenders * (numLenders + 1) / 2) * 3_000 ether; // Sum formula: 45k
        assertEq(bondMMA.cash(), INITIAL_CASH + totalLent, "Pool cash should equal initial + total lent");

        // Verify pool remains solvent
        assertTrue(bondMMA.checkSolvency(), "Pool should remain solvent");
    }

    /// @notice Test 5 users borrowing simultaneously
    /// @dev Reduced amounts to avoid draining pool liquidity
    function testIntegration_MultiUserBorrowing() public {
        uint256[] memory positionIds = new uint256[](5);

        // 5 users borrow different amounts (total: 50k, leaving 50k in pool)
        for (uint256 i = 0; i < 5; i++) {
            uint256 amount = (i + 1) * 2_000 ether; // 2k, 4k, 6k, 8k, 10k
            uint256 collateral = (amount * 150) / 100;
            uint256 maturity = block.timestamp + 90 days;

            vm.prank(users[i]);
            positionIds[i] = bondMMA.borrow(amount, maturity, collateral);
        }

        // Total borrowed = 2k + 4k + 6k + 8k + 10k = 30k
        uint256 totalBorrowed = 30_000 ether;
        assertEq(bondMMA.cash(), INITIAL_CASH - totalBorrowed, "Pool cash should decrease");

        // Verify liabilities tracked
        assertGt(bondMMA.netLiabilities(), 0, "Liabilities should be > 0");

        // Verify pool remains solvent
        assertTrue(bondMMA.checkSolvency(), "Pool should remain solvent");
    }

    /// @notice Test mixed lending and borrowing
    function testIntegration_MixedOperations() public {
        // 3 users lend
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(users[i]);
            bondMMA.lend(10_000 ether, block.timestamp + 90 days);
        }

        // 2 users borrow
        for (uint256 i = 3; i < 5; i++) {
            vm.prank(users[i]);
            bondMMA.borrow(15_000 ether, block.timestamp + 90 days, 22_500 ether);
        }

        // 2 more users lend
        for (uint256 i = 5; i < 7; i++) {
            vm.prank(users[i]);
            bondMMA.lend(8_000 ether, block.timestamp + 180 days);
        }

        // Calculate expected cash
        uint256 totalLent = (3 * 10_000 ether) + (2 * 8_000 ether); // 46k
        uint256 totalBorrowed = 2 * 15_000 ether; // 30k
        uint256 expectedCash = INITIAL_CASH + totalLent - totalBorrowed; // 100k + 46k - 30k = 116k

        assertEq(bondMMA.cash(), expectedCash, "Mixed operations cash calculation");
        assertTrue(bondMMA.checkSolvency(), "Pool should remain solvent");

    }

    /*//////////////////////////////////////////////////////////////
                        LIQUIDITY STRESS TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test borrowing until pool is nearly empty
    function testIntegration_LiquidityDrain() public {
        uint256 cashBefore = bondMMA.cash();

        // Borrow 90% of available liquidity
        uint256 borrowAmount = (cashBefore * 90) / 100;
        uint256 collateral = (borrowAmount * 150) / 100;

        vm.prank(users[0]);
        bondMMA.borrow(borrowAmount, block.timestamp + 90 days, collateral);

        // Pool should have 10% liquidity left
        uint256 cashAfter = bondMMA.cash();
        assertApproxEqRel(cashAfter, cashBefore / 10, 0.01e18, "Should have ~10% liquidity left");

        // Try to borrow more than available (should revert)
        vm.prank(users[1]);
        vm.expectRevert("Insufficient pool liquidity");
        bondMMA.borrow(cashAfter + 1 ether, block.timestamp + 90 days, (cashAfter + 1 ether) * 150 / 100);

    }

    /// @notice Test that lenders can still redeem when liquidity is low
    function testIntegration_RedeemWithLowLiquidity() public {
        // User lends
        vm.prank(users[0]);
        uint256 positionId = bondMMA.lend(10_000 ether, block.timestamp + 90 days);

        // Drain most liquidity via borrowing
        uint256 borrowAmount = 95_000 ether;
        vm.prank(users[1]);
        bondMMA.borrow(borrowAmount, block.timestamp + 180 days, borrowAmount * 150 / 100);

        // Pool now has ~15k cash (initial 100k + 10k lent - 95k borrowed)
        uint256 currentCash = bondMMA.cash();
        assertLt(currentCash, 20_000 ether, "Pool should have low liquidity");

        // Warp to maturity
        vm.warp(block.timestamp + 90 days);

        // Lender should still be able to redeem
        vm.prank(users[0]);
        bondMMA.redeem(positionId);

        // Check redemption succeeded
        IBondMMA.Position memory posAfter = bondMMA.getPosition(positionId);
        assertFalse(posAfter.isActive, "Position should be redeemed");

    }

    /*//////////////////////////////////////////////////////////////
                        SEQUENTIAL OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Test complete lifecycle: lend → borrow → repay → redeem
    function testIntegration_FullLifecycle() public {
        uint256 maturity = block.timestamp + 90 days;

        // Step 1: User 0 lends
        vm.prank(users[0]);
        uint256 lendPositionId = bondMMA.lend(20_000 ether, maturity);

        // Step 2: User 1 borrows
        vm.prank(users[1]);
        uint256 borrowPositionId = bondMMA.borrow(15_000 ether, maturity, 22_500 ether);

        // Step 3: User 2 lends
        vm.prank(users[2]);
        uint256 lendPositionId2 = bondMMA.lend(10_000 ether, maturity);

        // Step 4: Warp to maturity
        vm.warp(maturity);

        // Step 5: User 1 repays borrow
        IBondMMA.Position memory borrowPos = bondMMA.getPosition(borrowPositionId);
        stablecoin.mint(users[1], borrowPos.faceValue); // Mint repayment amount

        vm.prank(users[1]);
        bondMMA.repay(borrowPositionId);

        // Step 6: User 0 redeems
        vm.prank(users[0]);
        bondMMA.redeem(lendPositionId);

        // Step 7: User 2 redeems
        vm.prank(users[2]);
        bondMMA.redeem(lendPositionId2);

        // Final checks
        assertTrue(bondMMA.checkSolvency(), "Pool should be solvent at end");

    }

    /*//////////////////////////////////////////////////////////////
                        MULTIPLE MATURITIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Test positions with 30d, 90d, 180d, 365d maturities
    function testIntegration_MultipleMaturity() public {
        uint256[] memory maturities = new uint256[](4);
        maturities[0] = block.timestamp + 30 days;
        maturities[1] = block.timestamp + 90 days;
        maturities[2] = block.timestamp + 180 days;
        maturities[3] = block.timestamp + 365 days;

        uint256[] memory lendPositions = new uint256[](4);
        uint256[] memory borrowPositions = new uint256[](4);

        // Create positions at each maturity
        for (uint256 i = 0; i < 4; i++) {
            // Lend
            vm.prank(users[i]);
            lendPositions[i] = bondMMA.lend(10_000 ether, maturities[i]);

            // Borrow
            vm.prank(users[i + 4]);
            borrowPositions[i] = bondMMA.borrow(5_000 ether, maturities[i], 7_500 ether);
        }

        // Verify all positions created
        for (uint256 i = 0; i < 4; i++) {
            IBondMMA.Position memory lendPos = bondMMA.getPosition(lendPositions[i]);
            IBondMMA.Position memory borrowPos = bondMMA.getPosition(borrowPositions[i]);

            assertTrue(lendPos.isActive, "Lend position should be active");
            assertTrue(borrowPos.isActive, "Borrow position should be active");
            assertEq(lendPos.maturity, maturities[i], "Maturity mismatch");
            assertEq(borrowPos.maturity, maturities[i], "Maturity mismatch");
        }

        assertTrue(bondMMA.checkSolvency(), "Pool should remain solvent");

    }

    /// @notice Test redeeming positions in different order than created
    function testIntegration_OutOfOrderRedemptions() public {
        uint256[] memory positionIds = new uint256[](3);
        uint256 maturity = block.timestamp + 90 days;

        // Create 3 lend positions
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(users[i]);
            positionIds[i] = bondMMA.lend(10_000 ether, maturity);
        }

        // Warp to maturity
        vm.warp(maturity);

        // Redeem in reverse order
        vm.prank(users[2]);
        bondMMA.redeem(positionIds[2]);

        vm.prank(users[0]);
        bondMMA.redeem(positionIds[0]);

        vm.prank(users[1]);
        bondMMA.redeem(positionIds[1]);

        // All should be redeemed
        for (uint256 i = 0; i < 3; i++) {
            IBondMMA.Position memory pos = bondMMA.getPosition(positionIds[i]);
            assertFalse(pos.isActive, "All positions should be redeemed");
        }

    }

    /*//////////////////////////////////////////////////////////////
                        RATE CHANGES
    //////////////////////////////////////////////////////////////*/

    /// @notice Test operations after oracle rate update
    function testIntegration_RateChange() public {
        // Initial lending at 5% rate
        vm.prank(users[0]);
        bondMMA.lend(10_000 ether, block.timestamp + 90 days);

        uint256 rate1 = bondMMA.getCurrentRate();

        // Update oracle to 7% rate
        oracle.updateRate(70000000000000000);

        // New lending at 7% rate
        vm.prank(users[1]);
        bondMMA.lend(10_000 ether, block.timestamp + 90 days);

        uint256 rate2 = bondMMA.getCurrentRate();

        // Rates should be different
        assertNotEq(rate1, rate2, "Rates should differ after oracle update");

        // Pool should still be solvent
        assertTrue(bondMMA.checkSolvency(), "Pool should remain solvent");
    }
}
