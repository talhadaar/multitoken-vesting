// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract MultiTokenVesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct VestingSchedule {
        // Unique ID for the schedule
        bytes32 scheduleId;
        // Address of the beneficiary
        address beneficiary;
        // Address of the ERC20 token
        address token;
        // Total amount of tokens to be vested
        uint256 totalAmount;
        // Amount of tokens already claimed
        uint256 amountClaimed;
        // Start time of the vesting
        uint256 start;
        // Cliff duration in seconds (time before tokens begin to vest)
        uint256 cliff;
        // Total duration of the vesting in seconds
        uint256 duration;
        // Flag to indicate if all tokens have been claimed
        bool claimed;
    }

    // Array of all vesting schedules
    VestingSchedule[] public vestingSchedules;

    // Mapping from beneficiary to list of their schedule IDs (indices in the main array)
    mapping(address => uint256[]) private userScheduleIndices;

    // Total amount of specific tokens locked in the contract to prevent over-allocation
    mapping(address => uint256) public totalLockedPerToken;

    event ScheduleCreated(
        bytes32 indexed scheduleId,
        address indexed beneficiary,
        address indexed token,
        uint256 amount,
        uint256 start,
        uint256 duration
    );

    event TokensClaimed(
        address indexed beneficiary,
        bytes32 indexed scheduleId,
        uint256 amount
    );

    event ScheduleCompleted(bytes32 indexed scheduleId);

    /**
     * @dev Constructor sets the owner (admin) of the contract.
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Creates a new vesting schedule.
     * @param _beneficiary Address of the user receiving tokens.
     * @param _token Address of the ERC20 token.
     * @param _amount Total tokens to vest.
     * @param _start Unix timestamp for the start of vesting.
     * @param _cliff Duration in seconds before vesting begins.
     * @param _duration Total duration of vesting in seconds.
     */
    function createVestingSchedule(
        address _beneficiary,
        address _token,
        uint256 _amount,
        uint256 _start,
        uint256 _cliff,
        uint256 _duration
    ) external onlyOwner nonReentrant {
        require(_beneficiary != address(0), "Beneficiary cannot be zero address");
        require(_token != address(0), "Token cannot be zero address");
        require(_amount > 0, "Amount must be > 0");
        require(_duration > 0, "Duration must be > 0");
        require(_cliff <= _duration, "Cliff must be <= duration");

        // Transfer tokens from admin to contract
        // NOTE: Admin must approve this contract to spend _amount of _token beforehand
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        bytes32 scheduleId = keccak256(
            abi.encodePacked(_beneficiary, _token, _start, _duration, vestingSchedules.length)
        );

        VestingSchedule memory schedule = VestingSchedule({
            scheduleId: scheduleId,
            beneficiary: _beneficiary,
            token: _token,
            totalAmount: _amount,
            amountClaimed: 0,
            start: _start,
            cliff: _cliff,
            duration: _duration,
            claimed: false
        });

        vestingSchedules.push(schedule);
        userScheduleIndices[_beneficiary].push(vestingSchedules.length - 1);
        totalLockedPerToken[_token] += _amount;

        emit ScheduleCreated(scheduleId, _beneficiary, _token, _amount, _start, _duration);
    }

    /**
     * @dev Calculates the amount of tokens that have vested (unlocked) but not yet claimed.
     * @param _scheduleIndex Index of the schedule in the vestingSchedules array.
     */
    function calculateReleasableAmount(uint256 _scheduleIndex) public view returns (uint256) {
        require(_scheduleIndex < vestingSchedules.length, "Invalid schedule index");
        VestingSchedule storage schedule = vestingSchedules[_scheduleIndex];

        if (schedule.claimed) {
            return 0;
        }

        uint256 currentTime = block.timestamp;

        // If before cliff or start, nothing is vested
        if (currentTime < schedule.start + schedule.cliff) {
            return 0;
        }

        // If vesting period ended, all remaining tokens are releasable
        if (currentTime >= schedule.start + schedule.duration) {
            return schedule.totalAmount - schedule.amountClaimed;
        }

        // Linear Vesting Calculation: (Total * (Now - Start)) / Duration
        uint256 timeFromStart = currentTime - schedule.start;
        uint256 vestedAmount = (schedule.totalAmount * timeFromStart) / schedule.duration;

        return vestedAmount - schedule.amountClaimed;
    }

    /**
     * @dev Allows a user to claim their unlocked tokens for a specific schedule.
     * @param _scheduleIndex Index of the schedule to claim from.
     */
    function claim(uint256 _scheduleIndex) external nonReentrant {
        require(_scheduleIndex < vestingSchedules.length, "Invalid schedule index");
        VestingSchedule storage schedule = vestingSchedules[_scheduleIndex];

        require(msg.sender == schedule.beneficiary, "Only beneficiary can claim");
        require(!schedule.claimed, "Schedule fully claimed");

        uint256 releasable = calculateReleasableAmount(_scheduleIndex);
        require(releasable > 0, "No tokens due for claiming");

        schedule.amountClaimed += releasable;
        totalLockedPerToken[schedule.token] -= releasable;

        // Check if fully claimed
        if (schedule.amountClaimed == schedule.totalAmount) {
            schedule.claimed = true;
            emit ScheduleCompleted(schedule.scheduleId);
        }

        emit TokensClaimed(msg.sender, schedule.scheduleId, releasable);

        // Transfer tokens
        IERC20(schedule.token).safeTransfer(schedule.beneficiary, releasable);
    }

    /**
     * @dev Returns the count of vesting schedules for a specific user.
     */
    function getScheduleCountByUser(address _user) external view returns (uint256) {
        return userScheduleIndices[_user].length;
    }

    /**
     * @dev Returns a vesting schedule by the user's index (not global index).
     * Useful for frontend to iterate over a user's schedules.
     */
    function getScheduleByUserAtIndex(address _user, uint256 _index) external view returns (VestingSchedule memory) {
        require(_index < userScheduleIndices[_user].length, "Index out of bounds");
        uint256 globalIndex = userScheduleIndices[_user][_index];
        return vestingSchedules[globalIndex];
    }
}