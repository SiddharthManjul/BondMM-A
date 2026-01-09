// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {BondMMOracle} from "../../src/BondMMOracle.sol";

/**
 * @title BondMMOracleTest
 * @notice Comprehensive tests for BondMMOracle
 */
contract BondMMOracleTest is Test {
    BondMMOracle public oracle;

    address public owner;
    address public updater;
    address public user;

    uint256 constant INITIAL_RATE = 0.05 ether; // 5%
    uint256 constant PRECISION = 1e18;

    function setUp() public {
        owner = address(this);
        updater = address(0x1);
        user = address(0x2);

        // Deploy oracle
        oracle = new BondMMOracle(INITIAL_RATE);
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testConstructor() public view {
        assertEq(oracle.rateHistory(0), INITIAL_RATE, "Initial rate should be set");
        assertEq(oracle.timestamps(0), block.timestamp, "Initial timestamp should be set");
        assertEq(oracle.updater(), owner, "Owner should be initial updater");
        assertEq(oracle.owner(), owner, "Owner should be set");
        assertEq(oracle.getHistoryLength(), 1, "History length should be 1");

        console2.log("Initial rate:", oracle.rateHistory(0));
        console2.log("Initial timestamp:", oracle.timestamps(0));
    }

    function testConstructor_RevertsIfRateTooLow() public {
        vm.expectRevert(bytes("Rate out of bounds"));
        new BondMMOracle(0.005 ether); // 0.5% < MIN_RATE
    }

    function testConstructor_RevertsIfRateTooHigh() public {
        vm.expectRevert(bytes("Rate out of bounds"));
        new BondMMOracle(0.60 ether); // 60% > MAX_RATE
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function testSetUpdater() public {
        oracle.setUpdater(updater);
        assertEq(oracle.updater(), updater, "Updater should be changed");

        console2.log("New updater:", oracle.updater());
    }

    function testSetUpdater_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        oracle.setUpdater(updater);
    }

    function testSetUpdater_RevertsIfZeroAddress() public {
        vm.expectRevert(bytes("Invalid updater address"));
        oracle.setUpdater(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        RATE UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdateRate() public {
        uint256 newRate = 0.06 ether; // 6%

        oracle.updateRate(newRate);

        assertEq(oracle.getHistoryLength(), 2, "History length should increase");
        assertEq(oracle.rateHistory(1), newRate, "New rate should be stored");
        assertEq(oracle.timestamps(1), block.timestamp, "New timestamp should be stored");

        console2.log("Updated rate:", oracle.rateHistory(1));
    }

    function testUpdateRate_ByAuthorizedUpdater() public {
        oracle.setUpdater(updater);

        vm.prank(updater);
        oracle.updateRate(0.06 ether);

        assertEq(oracle.getHistoryLength(), 2, "History should be updated");
    }

    function testUpdateRate_ByOwner() public {
        oracle.setUpdater(updater);

        // Owner can still update even after setting different updater
        oracle.updateRate(0.06 ether);

        assertEq(oracle.getHistoryLength(), 2, "Owner should be able to update");
    }

    function testUpdateRate_RevertsIfUnauthorized() public {
        vm.prank(user);
        vm.expectRevert(bytes("Not authorized"));
        oracle.updateRate(0.06 ether);
    }

    function testUpdateRate_RevertsIfRateTooLow() public {
        vm.expectRevert(bytes("Rate out of bounds"));
        oracle.updateRate(0.005 ether);
    }

    function testUpdateRate_RevertsIfRateTooHigh() public {
        vm.expectRevert(bytes("Rate out of bounds"));
        oracle.updateRate(0.60 ether);
    }

    function testUpdateRate_RemovesOldestWhenAtCapacity() public {
        // Add 23 different rates to reach capacity (24 total)
        // Use different rates so we can verify oldest is removed
        for (uint256 i = 1; i <= 23; i++) {
            oracle.updateRate(0.05 ether + (i * 0.001 ether));
        }

        assertEq(oracle.getHistoryLength(), 24, "Should be at max capacity");

        // Store the current first rate (should be INITIAL_RATE = 0.05)
        uint256 firstRate = oracle.rateHistory(0);
        assertEq(firstRate, INITIAL_RATE, "First rate should be initial rate");

        // Store the second rate (should be 0.051)
        uint256 secondRate = oracle.rateHistory(1);

        uint256 newRate = 0.10 ether;

        // Add one more - should remove oldest and shift left
        oracle.updateRate(newRate);

        assertEq(oracle.getHistoryLength(), 24, "Should stay at max capacity");
        // After shift, first rate should now be what was previously second
        assertEq(oracle.rateHistory(0), secondRate, "First position should now have old second rate");
        assertEq(oracle.rateHistory(23), newRate, "Newest rate should be at end");

        console2.log("History maintained at:", oracle.getHistoryLength());
    }

    /*//////////////////////////////////////////////////////////////
                        TWAP CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetRate_SingleObservation() public view {
        uint256 rate = oracle.getRate();
        assertEq(rate, INITIAL_RATE, "Rate should equal initial rate");

        console2.log("TWAP with 1 observation:", rate);
    }

    function testGetRate_MultipleObservations() public {
        // Add rates: 5%, 6%, 7%
        oracle.updateRate(0.06 ether);
        oracle.updateRate(0.07 ether);

        // TWAP = (0.05 + 0.06 + 0.07) / 3 = 0.06
        uint256 rate = oracle.getRate();
        uint256 expectedRate = (0.05 ether + 0.06 ether + 0.07 ether) / 3;

        assertEq(rate, expectedRate, "TWAP should be average of all rates");

        console2.log("TWAP with 3 observations:", rate);
        console2.log("Expected:", expectedRate);
    }

    function testGetRate_WithVariance() public {
        // Add varied rates
        oracle.updateRate(0.03 ether); // 3%
        oracle.updateRate(0.08 ether); // 8%
        oracle.updateRate(0.05 ether); // 5%
        oracle.updateRate(0.06 ether); // 6%

        // TWAP = (0.05 + 0.03 + 0.08 + 0.05 + 0.06) / 5 = 0.054
        uint256 rate = oracle.getRate();
        uint256 sum = 0.05 ether + 0.03 ether + 0.08 ether + 0.05 ether + 0.06 ether;
        uint256 expectedRate = sum / 5;

        assertEq(rate, expectedRate, "TWAP should handle variance");

        console2.log("TWAP with variance:", rate);
        console2.log("Expected:", expectedRate);
    }

    /*//////////////////////////////////////////////////////////////
                        STALENESS TESTS
    //////////////////////////////////////////////////////////////*/

    function testIsStale_InitiallyFresh() public view {
        assertFalse(oracle.isStale(), "Should not be stale initially");
    }

    function testIsStale_AfterOneHour() public {
        // Fast forward 1 hour + 1 second
        vm.warp(block.timestamp + 1 hours + 1);

        assertTrue(oracle.isStale(), "Should be stale after 1 hour");

        console2.log("Stale after:", 1 hours + 1, "seconds");
    }

    function testIsStale_ExactlyOneHour() public {
        // Fast forward exactly 1 hour
        vm.warp(block.timestamp + 1 hours);

        assertFalse(oracle.isStale(), "Should not be stale at exactly 1 hour");
    }

    function testGetRate_RevertsIfStale() public {
        // Fast forward to make data stale
        vm.warp(block.timestamp + 1 hours + 1);

        vm.expectRevert(bytes("Oracle data is stale"));
        oracle.getRate();
    }

    function testGetRate_FreshAfterUpdate() public {
        // Make stale
        vm.warp(block.timestamp + 1 hours + 1);
        assertTrue(oracle.isStale(), "Should be stale");

        // Update rate
        oracle.updateRate(INITIAL_RATE);

        // Should be fresh now
        assertFalse(oracle.isStale(), "Should be fresh after update");
        uint256 rate = oracle.getRate();
        assertGt(rate, 0, "Should be able to get rate");

        console2.log("Fresh after update");
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetLatestRate() public {
        oracle.updateRate(0.06 ether);
        oracle.updateRate(0.07 ether);

        uint256 latest = oracle.getLatestRate();
        assertEq(latest, 0.07 ether, "Should return latest rate");

        console2.log("Latest rate:", latest);
    }

    function testGetLastUpdateTime() public {
        uint256 initialTime = oracle.getLastUpdateTime();
        assertEq(initialTime, block.timestamp, "Should return current timestamp");

        vm.warp(block.timestamp + 100);
        oracle.updateRate(0.06 ether);

        uint256 newTime = oracle.getLastUpdateTime();
        assertEq(newTime, block.timestamp, "Should return new timestamp");

        console2.log("Last update time:", newTime);
    }

    function testGetHistoryLength() public {
        assertEq(oracle.getHistoryLength(), 1, "Initial length should be 1");

        oracle.updateRate(0.06 ether);
        assertEq(oracle.getHistoryLength(), 2, "Length should increase");

        oracle.updateRate(0.07 ether);
        assertEq(oracle.getHistoryLength(), 3, "Length should increase again");

        console2.log("History length:", oracle.getHistoryLength());
    }

    function testGetTimeUntilStale() public {
        uint256 timeUntilStale = oracle.getTimeUntilStale();
        assertEq(timeUntilStale, 1 hours, "Should be 1 hour initially");

        // Fast forward 30 minutes
        vm.warp(block.timestamp + 30 minutes);
        timeUntilStale = oracle.getTimeUntilStale();
        assertEq(timeUntilStale, 30 minutes, "Should be 30 minutes remaining");

        // Fast forward past threshold
        vm.warp(block.timestamp + 31 minutes);
        timeUntilStale = oracle.getTimeUntilStale();
        assertEq(timeUntilStale, 0, "Should be 0 when stale");

        console2.log("Time until stale works correctly");
    }

    function testGetHistory() public {
        oracle.updateRate(0.06 ether);
        oracle.updateRate(0.07 ether);

        (uint256[] memory rates, uint256[] memory times) = oracle.getHistory();

        assertEq(rates.length, 3, "Rates array should have 3 elements");
        assertEq(times.length, 3, "Times array should have 3 elements");
        assertEq(rates[0], 0.05 ether, "First rate should be initial");
        assertEq(rates[1], 0.06 ether, "Second rate should be 6%");
        assertEq(rates[2], 0.07 ether, "Third rate should be 7%");

        console2.log("History retrieved correctly");
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS TESTS
    //////////////////////////////////////////////////////////////*/

    function testConstants() public view {
        assertEq(oracle.MAX_HISTORY(), 24, "MAX_HISTORY should be 24");
        assertEq(oracle.STALE_THRESHOLD(), 1 hours, "STALE_THRESHOLD should be 1 hour");
        assertEq(oracle.MIN_RATE(), 0.01 ether, "MIN_RATE should be 1%");
        assertEq(oracle.MAX_RATE(), 0.50 ether, "MAX_RATE should be 50%");

        console2.log("All constants verified");
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function testMultipleUpdatesInSameBlock() public {
        oracle.updateRate(0.06 ether);
        oracle.updateRate(0.07 ether);
        oracle.updateRate(0.08 ether);

        assertEq(oracle.getHistoryLength(), 4, "Should handle multiple updates");

        uint256 rate = oracle.getRate();
        uint256 expected = (0.05 ether + 0.06 ether + 0.07 ether + 0.08 ether) / 4;
        assertEq(rate, expected, "TWAP should be correct");

        console2.log("Multiple updates in same block handled");
    }

    function testRateAtBoundaries() public {
        // Test minimum rate
        oracle.updateRate(0.01 ether);
        assertEq(oracle.getLatestRate(), 0.01 ether, "Min rate should work");

        // Test maximum rate
        oracle.updateRate(0.50 ether);
        assertEq(oracle.getLatestRate(), 0.50 ether, "Max rate should work");

        console2.log("Boundary rates work correctly");
    }
}
