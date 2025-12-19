// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MultiTokenVesting} from "../src/MultiTokenVesting.sol"; // Adjust path to your contract
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock Token for testing
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
    uint256 public constant DURATION = 1000 seconds;
    uint256 public constant CLIFF = 0;

    function setUp() public {
        owner = address(this);
        beneficiary = address(0x123);
        unauthorizedUser = address(0x999);

        token = new MockERC20("Test Token", "TST");
        vesting = new MultiTokenVesting();

        // Fund the owner and approve vesting contract
        token.mint(owner, AMOUNT * 100);
        token.approve(address(vesting), type(uint256).max);
    }

    // --- TEST CREATION ---

    function test_CreateVestingSchedule() public {
        uint256 start = block.timestamp;
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, CLIFF, DURATION);

        assertEq(index, 0); // First schedule should be index 0
        assertEq(vesting.getScheduleCountByUser(beneficiary), 1);
        assertEq(token.balanceOf(address(vesting)), AMOUNT); // Contract holds tokens
    }

    function test_Revert_CreateWithZeroAddress() public {
        vm.expectRevert("Beneficiary cannot be zero address");
        vesting.createVestingSchedule(address(0), address(token), AMOUNT, block.timestamp, CLIFF, DURATION);
    }

    // --- TEST VESTING MATH ---

    function test_CalculateReleasableAmount_Linear() public {
        uint256 start = block.timestamp;
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, CLIFF, DURATION);

        // 1. Check immediately (0%)
        assertEq(vesting.calculateReleasableAmount(index), 0);

        // 2. Warp to 50%
        vm.warp(start + (DURATION / 2));
        assertEq(vesting.calculateReleasableAmount(index), AMOUNT / 2);

        // 3. Warp to 100%
        vm.warp(start + DURATION);
        assertEq(vesting.calculateReleasableAmount(index), AMOUNT);
    }

    function test_CalculateReleasable_WithCliff() public {
        uint256 start = block.timestamp;
        uint256 cliffLength = 200 seconds;
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, cliffLength, DURATION);

        // Before Cliff
        vm.warp(start + 100 seconds);
        assertEq(vesting.calculateReleasableAmount(index), 0);

        // Just after Cliff (201s / 1000s vested)
        vm.warp(start + 201 seconds);
        uint256 expected = (AMOUNT * 201) / DURATION;
        assertEq(vesting.calculateReleasableAmount(index), expected);
    }

    // --- TEST CLAIMING ---

    function test_Claim_FullAmount() public {
        uint256 start = block.timestamp;
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, CLIFF, DURATION);

        vm.warp(start + DURATION); // Fast forward to end

        vm.startPrank(beneficiary);
        vesting.claim(index);
        vm.stopPrank();

        assertEq(token.balanceOf(beneficiary), AMOUNT);

        // Check claimed flag
        (,,,,,,,, bool claimed) = vesting.vestingSchedules(index);
        assertTrue(claimed);
    }

    function test_Claim_Partial() public {
        uint256 start = block.timestamp;
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, CLIFF, DURATION);

        vm.warp(start + (DURATION / 2)); // Fast forward 50%

        vm.prank(beneficiary);
        vesting.claim(index);

        assertEq(token.balanceOf(beneficiary), AMOUNT / 2);

        // Check claimed flag is FALSE
        (,,,,,,,, bool claimed) = vesting.vestingSchedules(index);
        assertFalse(claimed);
    }

    function test_Revert_Claim_Unauthorized() public {
        uint256 start = block.timestamp;
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, CLIFF, DURATION);

        vm.warp(start + DURATION);

        vm.prank(unauthorizedUser);
        vm.expectRevert("Only beneficiary can claim");
        vesting.claim(index);
    }

    function test_Revert_DoubleClaim() public {
        uint256 start = block.timestamp;
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, CLIFF, DURATION);

        vm.warp(start + DURATION);

        vm.startPrank(beneficiary);
        vesting.claim(index); // First claim succeeds

        vm.expectRevert("Schedule fully claimed");
        vesting.claim(index); // Second claim fails
        vm.stopPrank();
    }
}
