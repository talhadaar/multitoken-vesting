// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Custom Errors (Saves massive bytecode compared to require strings)
error InvalidAddress();
error InvalidAmount();
error InvalidDuration();
error InvalidCliff();
error Unauthorized();
error ScheduleClaimed();
error NothingToClaim();
error InvalidIndex();

contract MultiTokenVesting is Ownable {
    using SafeERC20 for IERC20;

    struct VestingSchedule {
        address beneficiary;
        uint64 start;
        address token;
        uint64 duration;
        uint64 cliff;
        uint256 totalAmount;
        uint256 amountClaimed;
    }

    VestingSchedule[] public vestingSchedules;
    mapping(address => uint256[]) private userScheduleIndices;
    mapping(address => uint256) public totalLockedPerToken;

    event ScheduleCreated(
        bytes32 indexed scheduleId,
        address indexed beneficiary,
        address indexed token,
        uint256 amount,
        uint256 start,
        uint256 duration
    );

    event TokensClaimed(address indexed beneficiary, bytes32 indexed scheduleId, uint256 amount);

    event ScheduleCompleted(bytes32 indexed scheduleId);

    constructor() Ownable(msg.sender) {}

    function createVestingSchedule(
        address _beneficiary,
        address _token,
        uint256 _amount,
        uint64 _start,
        uint64 _cliff,
        uint64 _duration
    ) external onlyOwner returns (uint256) {
        if (_beneficiary == address(0) || _token == address(0)) revert InvalidAddress();
        if (_amount == 0) revert InvalidAmount();
        if (_duration == 0) revert InvalidDuration();
        if (_cliff > _duration) revert InvalidCliff();

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // We push first, then get index. logic matches previous.
        vestingSchedules.push(
            VestingSchedule({
                beneficiary: _beneficiary,
                token: _token,
                start: _start,
                duration: _duration,
                cliff: _cliff,
                totalAmount: _amount,
                amountClaimed: 0
            })
        );

        uint256 index = vestingSchedules.length - 1;
        userScheduleIndices[_beneficiary].push(index);
        totalLockedPerToken[_token] += _amount;

        // Generate ID on the fly for the event, but don't store it
        bytes32 scheduleId = keccak256(abi.encodePacked(_beneficiary, _token, _start, _duration, index));
        emit ScheduleCreated(scheduleId, _beneficiary, _token, _amount, _start, _duration);

        return index;
    }

    function calculateReleasableAmount(uint256 _index) public view returns (uint256) {
        if (_index >= vestingSchedules.length) revert InvalidIndex();
        VestingSchedule storage schedule = vestingSchedules[_index];

        // Infer 'claimed' status
        if (schedule.amountClaimed == schedule.totalAmount) {
            return 0;
        }

        uint256 currentTime = block.timestamp;
        if (currentTime < schedule.start + schedule.cliff) {
            return 0;
        }

        uint256 vestedAmount;
        if (currentTime >= schedule.start + schedule.duration) {
            vestedAmount = schedule.totalAmount;
        } else {
            uint256 timeFromStart = currentTime - schedule.start;
            vestedAmount = (schedule.totalAmount * timeFromStart) / schedule.duration;
        }

        return vestedAmount - schedule.amountClaimed;
    }

    function claim(uint256 _index) external {
        if (_index >= vestingSchedules.length) revert InvalidIndex();
        VestingSchedule storage schedule = vestingSchedules[_index];

        if (msg.sender != schedule.beneficiary) revert Unauthorized();
        if (schedule.amountClaimed == schedule.totalAmount) revert ScheduleClaimed();

        uint256 releasable = calculateReleasableAmount(_index);
        if (releasable == 0) revert NothingToClaim();

        // CHECKS-EFFECTS-INTERACTIONS PATTERN
        // 1. Update State (Effect)
        schedule.amountClaimed += releasable;
        totalLockedPerToken[schedule.token] -= releasable;

        // Generate ID for event
        bytes32 scheduleId = keccak256(
            abi.encodePacked(schedule.beneficiary, schedule.token, schedule.start, schedule.duration, _index)
        );

        if (schedule.amountClaimed == schedule.totalAmount) {
            emit ScheduleCompleted(scheduleId);
        }

        emit TokensClaimed(msg.sender, scheduleId, releasable);

        IERC20(schedule.token).safeTransfer(schedule.beneficiary, releasable);
    }

    function getScheduleCountByUser(address _user) external view returns (uint256) {
        return userScheduleIndices[_user].length;
    }

    function getScheduleByUserAtIndex(address _user, uint256 _index) external view returns (VestingSchedule memory) {
        if (_index >= userScheduleIndices[_user].length) revert InvalidIndex();
        uint256 globalIndex = userScheduleIndices[_user][_index];
        return vestingSchedules[globalIndex];
    }
}
