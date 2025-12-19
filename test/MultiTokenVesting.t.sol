// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MultiTokenVesting.sol"; // Adjust path to your contract
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// 1. Create a Mock Token for testing
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
        // Define users
        owner = address(this); // The test contract is the owner
        beneficiary = address(0x123);
        unauthorizedUser = address(0x999);

        // Deploy contracts
        token = new MockERC20("Test Token", "TST");
        vesting = new MultiTokenVesting();

        // Mint tokens to owner for funding the vesting
        token.mint(owner, AMOUNT * 10);

        // Approve the vesting contract to spend owner's tokens
        token.approve(address(vesting), type(uint256).max);
    }

    /* ========================================================================
                            TEST: CREATION
       ======================================================================== */

    function test_CreateVestingSchedule() public {
        uint256 start = block.timestamp;
        
        // Call the create function
        uint256 index = vesting.createVestingSchedule(
            beneficiary,
            address(token),
            AMOUNT,
            start,
            CLIFF,
            DURATION
        );

        // Check if index returned is correct (should be 0 for first schedule)
        assertEq(index, 0);

        // Check internal state
        assertEq(vesting.getScheduleCountByUser(beneficiary), 1);
        assertEq(vesting.totalLockedPerToken(address(token)), AMOUNT);

        // Check if tokens were actually transferred to the contract
        assertEq(token.balanceOf(address(vesting)), AMOUNT);
    }

    function test_Revert_CreateWithZeroAddress() public {
        vm.expectRevert("Beneficiary cannot be zero address");
        vesting.createVestingSchedule(
            address(0), 
            address(token), 
            AMOUNT, 
            block.timestamp, 
            CLIFF, 
            DURATION
        );
    }

    /* ========================================================================
                            TEST: VESTING LOGIC
       ======================================================================== */

    function test_CalculateReleasableAmount_Linear() public {
        uint256 start = block.timestamp;
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, CLIFF, DURATION);

        // 1. Check immediately (should be 0)
        uint256 releasable = vesting.calculateReleasableAmount(index);
        assertEq(releasable, 0);

        // 2. Warp to 50% of duration
        vm.warp(start + (DURATION / 2));
        releasable = vesting.calculateReleasableAmount(index);
        
        // Should be exactly 50% of AMOUNT
        assertEq(releasable, AMOUNT / 2);

        // 3. Warp to end
        vm.warp(start + DURATION);
        releasable = vesting.calculateReleasableAmount(index);
        assertEq(releasable, AMOUNT);
    }

    function test_CalculateReleasable_WithCliff() public {
        uint256 start = block.timestamp;
        uint256 cliffLength = 200 seconds; // Cliff is 200s
        
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, cliffLength, DURATION);

        // Warp to 100s (Before cliff)
        vm.warp(start + 100 seconds);
        uint256 releasable = vesting.calculateReleasableAmount(index);
        assertEq(releasable, 0, "Should be 0 before cliff");

        // Warp to 201s (Just after cliff)
        // Formula: (1000 * 201) / 1000 = 201 tokens
        vm.warp(start + 201 seconds);
        releasable = vesting.calculateReleasableAmount(index);
        assertGt(releasable, 0, "Should have vested tokens after cliff");
    }

    /* ========================================================================
                            TEST: CLAIMING & STATE
       ======================================================================== */

    function test_Claim_Success() public {
        uint256 start = block.timestamp;
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, CLIFF, DURATION);

        // Warp to 100% finished
        vm.warp(start + DURATION);

        // Switch caller to beneficiary
        vm.startPrank(beneficiary);
        
        vesting.claim(index);

        vm.stopPrank();

        // Checks
        assertEq(token.balanceOf(beneficiary), AMOUNT); // User got tokens
        assertEq(token.balanceOf(address(vesting)), 0); // Contract empty
        
        // Verify the 'claimed' flag is true
        // Note: We need to access the struct. Since it's in an array, we can use the getter we made or access public array.
        // Assuming public array:
        (,,,,, , , , bool claimed) = vesting.vestingSchedules(index);
        assertTrue(claimed, "Claimed flag should be true");
    }

    function test_Claim_Partial_UpdatesState() public {
        uint256 start = block.timestamp;
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, CLIFF, DURATION);

        // Warp to 50%
        vm.warp(start + (DURATION / 2));

        vm.prank(beneficiary);
        vesting.claim(index);

        // Beneficiary should have 50%
        assertEq(token.balanceOf(beneficiary), AMOUNT / 2);
        
        // Contract should have remaining 50%
        assertEq(token.balanceOf(address(vesting)), AMOUNT / 2);

        // Check claimed amount in struct
        (,,,,,uint256 amountClaimed,,,) = vesting.vestingSchedules(index);
        assertEq(amountClaimed, AMOUNT / 2);
    }

    function test_Revert_Claim_Unauthorized() public {
        uint256 start = block.timestamp;
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, CLIFF, DURATION);

        vm.warp(start + DURATION);

        // Try to claim as random user
        vm.prank(unauthorizedUser);
        vm.expectRevert("Only beneficiary can claim");
        vesting.claim(index);
    }

    function test_Revert_Claim_DoubleClaim() public {
        uint256 start = block.timestamp;
        uint256 index = vesting.createVestingSchedule(beneficiary, address(token), AMOUNT, start, CLIFF, DURATION);

        vm.warp(start + DURATION);

        vm.startPrank(beneficiary);
        
        // 1. Claim all
        vesting.claim(index);

        // 2. Try to claim again
        vm.expectRevert("Schedule fully claimed");
        vesting.claim(index);
        
        vm.stopPrank();
    }
}