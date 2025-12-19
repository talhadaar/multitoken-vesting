// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import "../src/MultiTokenVesting.sol"; // Adjust path to your contract
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// 1. Mock Token
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract MultiTokenVestingTest is Test {
    MultiTokenVesting public vesting;
    MockERC20 public token;

    address public owner;
    address public beneficiary;
    address public unauthorizedUser;

    uint256 public constant AMOUNT = 1000 ether;
    uint64 public constant DURATION = 1000; // uint64 for optimized contract
    uint64 public constant CLIFF = 0;

    function setUp() public {
        owner = address(this);
        beneficiary = address(0x123);
        unauthorizedUser = address(0x999);

        token = new MockERC20("Test Token", "TST");
        vesting = new MultiTokenVesting();

        token.mint(owner, AMOUNT * 100);
        token.approve(address(vesting), type(uint256).max);
    }

    /* ========================================================================
                            TEST: CREATION & ERRORS
       ======================================================================== */

    function test_CreateVestingSchedule() public {
        uint64 start = uint64(block.timestamp);
        
        uint256 index = vesting.createVestingSchedule(
            beneficiary, address(token), AMOUNT, start, CLIFF, DURATION
        );

        assertEq(index, 0); 
        assertEq(vesting.getScheduleCountByUser(beneficiary), 1);
        
        // Verify struct data
        MultiTokenVesting.VestingSchedule memory schedule = vesting.getScheduleByUserAtIndex(beneficiary, 0);
        assertEq(schedule.totalAmount, AMOUNT);
        assertEq(schedule.beneficiary, beneficiary);
    }

    function test_Revert_InvalidAddress() public {
        // We expect the custom error 'InvalidAddress()'
        vm.expectRevert(InvalidAddress.selector);
        
        vesting.createVestingSchedule(
            address(0), // Bad address
            address(token), 
            AMOUNT, 
            uint64(block.timestamp), 
            CLIFF, 
            DURATION
        );
    }

    function test_Revert_InvalidAmount() public {
        vm.expectRevert(InvalidAmount.selector);
        
        vesting.createVestingSchedule(
            beneficiary, 
            address(token), 
            0, // Bad amount
            uint64(block.timestamp), 
            CLIFF, 
            DURATION
        );
    }

    /* ========================================================================
                            TEST: CLAIMING LOGIC
       ======================================================================== */

    function test_Claim_FullAmount() public {
        uint64 start = uint64(block.timestamp);
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, CLIFF, DURATION);

        // Warp to end
        vm.warp(start + DURATION);

        vm.startPrank(beneficiary);
        vesting.claim(index);
        vm.stopPrank();

        // 1. Check Balance
        assertEq(token.balanceOf(beneficiary), AMOUNT);
        
        // 2. Check State (We infer 'claimed' by checking amounts)
        MultiTokenVesting.VestingSchedule memory schedule = vesting.getScheduleByUserAtIndex(beneficiary, 0);
        assertEq(schedule.amountClaimed, AMOUNT);
        assertEq(schedule.amountClaimed, schedule.totalAmount);
    }

    function test_Claim_Partial() public {
        uint64 start = uint64(block.timestamp);
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, CLIFF, DURATION);

        // Warp 50%
        vm.warp(start + (DURATION / 2));

        vm.prank(beneficiary);
        vesting.claim(index);

        assertEq(token.balanceOf(beneficiary), AMOUNT / 2);
    }

    /* ========================================================================
                            TEST: SECURITY REVERTS
       ======================================================================== */

    function test_Revert_UnauthorizedClaim() public {
        uint64 start = uint64(block.timestamp);
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, CLIFF, DURATION);
        
        vm.warp(start + DURATION);

        vm.prank(unauthorizedUser);
        
        // Expect custom error
        vm.expectRevert(Unauthorized.selector);
        vesting.claim(index);
    }

    function test_Revert_DoubleClaim() public {
        uint64 start = uint64(block.timestamp);
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, CLIFF, DURATION);

        vm.warp(start + DURATION);

        vm.startPrank(beneficiary);
        
        // First claim
        vesting.claim(index);
        
        // Second claim (should fail because amountClaimed == totalAmount)
        vm.expectRevert(ScheduleClaimed.selector);
        vesting.claim(index);
        
        vm.stopPrank();
    }

    function test_Revert_NothingToClaim() public {
        uint64 start = uint64(block.timestamp);
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, CLIFF, DURATION);

        // Try to claim immediately (0 unlocked)
        vm.prank(beneficiary);
        
        vm.expectRevert(NothingToClaim.selector);
        vesting.claim(index);
    }
}