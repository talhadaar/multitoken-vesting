// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MultiTokenVesting.sol"; // Adjust path based on your folder structure
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Simple Mock Token for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MCK") {
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }
}

contract MultiTokenVestingTest is Test {
    MultiTokenVesting public vesting;
    MockERC20 public token;

    address public owner;
    address public beneficiary;
    address public otherUser;

    uint64 public constant START_TIME = 1000; // Arbitrary start time
    uint64 public constant DURATION = 1000; // 1000 seconds duration
    uint64 public constant CLIFF = 250; // 250 seconds cliff (25%)
    uint256 public constant AMOUNT = 1000 ether;

    // Events to verify (Must match contract definition exactly)
    event ScheduleCreated(
        uint256 indexed scheduleIndex,
        address indexed beneficiary,
        address indexed token,
        uint256 amount,
        uint256 start,
        uint256 duration
    );

    event TokensClaimed(address indexed beneficiary, uint256 indexed scheduleIndex, uint256 amount);
    event ScheduleCompleted(uint256 indexed scheduleIndex);

    function setUp() public {
        owner = address(this);
        beneficiary = makeAddr("beneficiary");
        otherUser = makeAddr("otherUser");

        // Deploy contracts
        vesting = new MultiTokenVesting();
        token = new MockERC20();

        // Approve vesting contract to spend owner's tokens
        token.approve(address(vesting), type(uint256).max);

        // Set block timestamp to a known starting point
        vm.warp(START_TIME);
    }

    /* -------------------------------------------------------------------------- */
    /* CREATION TESTS                                */
    /* -------------------------------------------------------------------------- */

    function test_CreateVestingSchedule() public {
        // Expect the event with index 0
        vm.expectEmit(true, true, true, true);
        emit ScheduleCreated(0, beneficiary, address(token), AMOUNT, START_TIME, DURATION);

        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START_TIME, CLIFF, DURATION);

        assertEq(index, 0);

        // Check contract token balance
        assertEq(token.balanceOf(address(vesting)), AMOUNT);
        assertEq(vesting.totalLockedPerToken(address(token)), AMOUNT);

        // Verify stored struct data
        (
            address _beneficiary,
            uint64 _start,
            address _token,
            uint64 _duration,
            uint64 _cliff,
            uint256 _totalAmount,
            uint256 _amountClaimed
        ) = vesting.vestingSchedules(0);

        assertEq(_beneficiary, beneficiary);
        assertEq(_start, START_TIME);
        assertEq(_token, address(token));
        assertEq(_duration, DURATION);
        assertEq(_cliff, CLIFF);
        assertEq(_totalAmount, AMOUNT);
        assertEq(_amountClaimed, 0);
    }

    function test_Revert_CreateInvalidInputs() public {
        // 0 Amount
        vm.expectRevert(InvalidAmount.selector);
        vesting.createVestingSchedule(beneficiary, address(token), 0, START_TIME, 0, DURATION);

        // Cliff > Duration
        vm.expectRevert(InvalidCliff.selector);
        vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START_TIME, DURATION + 1, DURATION);

        // 0 Duration
        vm.expectRevert(InvalidDuration.selector);
        vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START_TIME, 0, 0);

        // Zero Address
        vm.expectRevert(InvalidAddress.selector);
        vesting.createVestingSchedule(address(0), address(token), AMOUNT, START_TIME, 0, DURATION);
    }

    function test_Revert_OnlyOwnerCreate() public {
        vm.prank(otherUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, otherUser));
        vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START_TIME, 0, DURATION);
    }

    /* -------------------------------------------------------------------------- */
    /* CALCULATION LOGIC                                */
    /* -------------------------------------------------------------------------- */

    function test_CalculateReleasableAmount_Cliff() public {
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START_TIME, CLIFF, DURATION);

        // Case 1: Before Cliff
        vm.warp(START_TIME + CLIFF - 1);
        uint256 releasable = vesting.calculateReleasableAmount(index);
        assertEq(releasable, 0, "Should be 0 before cliff");

        // Case 2: At Cliff
        vm.warp(START_TIME + CLIFF);
        releasable = vesting.calculateReleasableAmount(index);
        // Linear vesting: (Amount * timePassed) / duration
        // (1000 * 250) / 1000 = 250
        assertEq(releasable, AMOUNT * CLIFF / DURATION, "Should be 25% at cliff");
    }

    function test_CalculateReleasableAmount_Linear() public {
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START_TIME, 0, DURATION);

        // 50% through duration
        vm.warp(START_TIME + (DURATION / 2));
        uint256 releasable = vesting.calculateReleasableAmount(index);

        assertEq(releasable, AMOUNT / 2, "Should be 50% vested");
    }

    function test_CalculateReleasableAmount_PostDuration() public {
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START_TIME, 0, DURATION);

        // Way past duration
        vm.warp(START_TIME + DURATION + 5000);
        uint256 releasable = vesting.calculateReleasableAmount(index);

        assertEq(releasable, AMOUNT, "Should be 100% vested after duration");
    }

    /* -------------------------------------------------------------------------- */
    /* CLAIM TESTS                                  */
    /* -------------------------------------------------------------------------- */

    function test_Claim_Success() public {
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START_TIME, 0, DURATION);

        // Fast forward to end
        vm.warp(START_TIME + DURATION);

        vm.prank(beneficiary);

        vm.expectEmit(true, true, true, true);
        emit TokensClaimed(beneficiary, index, AMOUNT);

        vesting.claim(index);

        assertEq(token.balanceOf(beneficiary), AMOUNT);
        assertEq(vesting.totalLockedPerToken(address(token)), 0);

        // Verify schedule state updated
        (,,,,,, uint256 claimed) = vesting.vestingSchedules(index);
        assertEq(claimed, AMOUNT);
    }

    function test_Claim_Partial() public {
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START_TIME, 0, DURATION);

        // 50% time passed
        vm.warp(START_TIME + (DURATION / 2));

        vm.prank(beneficiary);
        vesting.claim(index);

        assertEq(token.balanceOf(beneficiary), AMOUNT / 2);

        // Move to end and claim remaining
        vm.warp(START_TIME + DURATION);

        vm.prank(beneficiary);
        vesting.claim(index);

        assertEq(token.balanceOf(beneficiary), AMOUNT);
    }

    function test_Revert_ClaimUnauthorized() public {
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START_TIME, 0, DURATION);

        vm.warp(START_TIME + DURATION);

        vm.prank(otherUser);
        vm.expectRevert(Unauthorized.selector);
        vesting.claim(index);
    }

    function test_Revert_ClaimNothing() public {
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START_TIME, CLIFF, DURATION);

        // Before cliff
        vm.warp(START_TIME + CLIFF - 10);

        vm.prank(beneficiary);
        vm.expectRevert(NothingToClaim.selector);
        vesting.claim(index);
    }

    function test_Revert_AlreadyClaimed() public {
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START_TIME, 0, DURATION);

        vm.warp(START_TIME + DURATION);

        vm.prank(beneficiary);
        vesting.claim(index); // Claim 100%

        vm.prank(beneficiary);
        vm.expectRevert(ScheduleClaimed.selector);
        vesting.claim(index); // Try again
    }

    /* -------------------------------------------------------------------------- */
    /* VIEW FUNCTIONS                                 */
    /* -------------------------------------------------------------------------- */

    function test_UserScheduleIndices() public {
        vesting.createVestingSchedule(beneficiary, address(token), 100, START_TIME, 0, DURATION);
        vesting.createVestingSchedule(beneficiary, address(token), 200, START_TIME, 0, DURATION);

        assertEq(vesting.getScheduleCountByUser(beneficiary), 2);

        // Check contents
        MultiTokenVesting.VestingSchedule memory s1 = vesting.getScheduleByUserAtIndex(beneficiary, 0);
        assertEq(s1.totalAmount, 100);

        MultiTokenVesting.VestingSchedule memory s2 = vesting.getScheduleByUserAtIndex(beneficiary, 1);
        assertEq(s2.totalAmount, 200);
    }
}
