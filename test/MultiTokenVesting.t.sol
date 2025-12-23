// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MultiTokenVesting.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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

    uint64 public constant START = 1000;
    uint64 public constant DURATION = 1000;
    uint64 public constant CLIFF = 250;
    uint256 public constant AMOUNT = 1000 ether;

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
    event ScheduleRevoked(uint256 indexed scheduleIndex, uint256 amountRevoked, uint256 amountVested);
    event ExcessWithdrawn(address indexed token, uint256 amount);

    function setUp() public {
        owner = address(this);
        beneficiary = makeAddr("beneficiary");
        otherUser = makeAddr("otherUser");

        vesting = new MultiTokenVesting();
        token = new MockERC20();
        token.approve(address(vesting), type(uint256).max);
        vm.warp(START);
    }

    function test_CreateSchedule() public {
        vm.expectEmit(true, true, true, true);
        emit ScheduleCreated(0, beneficiary, address(token), AMOUNT, START, DURATION);

        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START, CLIFF, DURATION);
        assertEq(index, 0);
    }

    function test_Revert_InvalidAddress() public {
        vm.expectRevert(InvalidAddress.selector);
        vesting.createVestingSchedule(address(0), address(token), AMOUNT, START, CLIFF, DURATION);
    }

    function test_Claim_Full() public {
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START, 0, DURATION);
        vm.warp(START + DURATION);

        vm.prank(beneficiary);
        vesting.claim(index);

        (,,, bool claimed,,,,,) = vesting.vestingSchedules(index);
        assertTrue(claimed);
        assertEq(token.balanceOf(beneficiary), AMOUNT);
    }

    function test_Revoke_SplitsFunds() public {
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START, 0, DURATION);
        vm.warp(START + (DURATION / 2)); // 50%
        uint256 initialOwnerBal = token.balanceOf(owner);

        vesting.revoke(index);

        assertEq(token.balanceOf(beneficiary), AMOUNT / 2);
        assertEq(token.balanceOf(owner), initialOwnerBal + (AMOUNT / 2));
    }

    function test_Revert_ClaimRevoked() public {
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START, 0, DURATION);
        vesting.revoke(index);

        vm.prank(beneficiary);

        vm.expectRevert(ScheduleWasRevoked.selector);
        vesting.claim(index);
    }

    function test_Revert_RevokeTwice() public {
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START, 0, DURATION);
        vesting.revoke(index);

        // FIX: Use the new error name here
        vm.expectRevert(ScheduleWasRevoked.selector);
        vesting.revoke(index);
    }

    function test_Revert_RevokeUnauthorized() public {
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START, 0, DURATION);

        vm.prank(otherUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, otherUser));
        vesting.revoke(index);
    }

    function test_Revoke_PartiallyVested() public {
        uint256 index = vesting.createVestingSchedule(
            beneficiary,
            address(token),
            AMOUNT, // 1000 Tokens
            START,
            0, // No cliff for simpler math
            DURATION // 1000 Seconds
        );

        vm.warp(START + (DURATION / 2));

        uint256 initialOwnerBalance = token.balanceOf(owner);
        uint256 initialBeneficiaryBalance = token.balanceOf(beneficiary);

        vesting.revoke(index);

        // Check Balances
        assertEq(
            token.balanceOf(beneficiary),
            initialBeneficiaryBalance + (AMOUNT / 2),
            "Beneficiary should receive exactly 50% of tokens"
        );

        assertEq(
            token.balanceOf(owner), initialOwnerBalance + (AMOUNT / 2), "Owner should receive the unvested 50% refund"
        );

        // Check Schedule State
        (,, bool revoked, bool claimed,,,,, uint256 claimedAmount) = vesting.vestingSchedules(index);

        assertTrue(revoked, "Schedule should be marked as revoked");
        assertFalse(claimed, "Schedule should NOT be marked as claimed (it was revoked)");
        assertEq(claimedAmount, AMOUNT / 2, "Amount claimed in struct should equal vested amount");

        // Check Contract Accounting
        assertEq(vesting.totalLockedPerToken(address(token)), 0, "Total locked should be cleared");
    }

    function test_WithdrawExcess_Success() public {
        vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START, 0, DURATION);

        assertEq(token.balanceOf(address(vesting)), AMOUNT);
        assertEq(vesting.totalLockedPerToken(address(token)), AMOUNT);

        // Accidental transfer of extra tokens to contract
        uint256 excessAmount = 500 ether;
        token.transfer(address(vesting), excessAmount);

        // Contract now holds 1500, but only 1000 are locked
        assertEq(token.balanceOf(address(vesting)), AMOUNT + excessAmount);

        // Withdraw Excess
        uint256 ownerBalanceBefore = token.balanceOf(owner);

        vm.expectEmit(true, false, false, true);
        emit ExcessWithdrawn(address(token), excessAmount);

        vesting.withdrawExcess(address(token));

        // Owner should get exactly the 500 excess back
        assertEq(token.balanceOf(owner), ownerBalanceBefore + excessAmount);

        // Contract should still hold the 1000 locked tokens
        assertEq(token.balanceOf(address(vesting)), AMOUNT);
        assertEq(vesting.totalLockedPerToken(address(token)), AMOUNT);
    }

    function test_Revert_WithdrawExcess_WhenNoneExists() public {
        vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, START, 0, DURATION);

        vm.expectRevert(InsufficientExcessBalance.selector);
        vesting.withdrawExcess(address(token));
    }

    function test_Revert_WithdrawExcess_Unauthorized() public {
        token.transfer(address(vesting), 100 ether);

        vm.prank(otherUser);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, otherUser));
        vesting.withdrawExcess(address(token));
    }
}
