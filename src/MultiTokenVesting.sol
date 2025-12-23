// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Custom Errors
error InvalidAddress();
error InvalidAmount();
error InvalidDuration();
error InvalidCliff();
error Unauthorized();
error ScheduleClaimed();
error NothingToClaim();
error InvalidIndex();
error ScheduleWasRevoked();
error InsufficientExcessBalance();

contract MultiTokenVesting is Ownable {
    using SafeERC20 for IERC20;

    struct VestingSchedule {
        address beneficiary;
        uint64 start;
        bool revoked;
        bool claimed;
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

        vestingSchedules.push(
            VestingSchedule({
                beneficiary: _beneficiary,
                start: _start,
                revoked: false,
                claimed: false,
                token: _token,
                duration: _duration,
                cliff: _cliff,
                totalAmount: _amount,
                amountClaimed: 0
            })
        );

        uint256 index = vestingSchedules.length - 1;
        userScheduleIndices[_beneficiary].push(index);
        totalLockedPerToken[_token] += _amount;

        emit ScheduleCreated(index, _beneficiary, _token, _amount, _start, _duration);

        return index;
    }

    function calculateReleasableAmount(uint256 _index) public view returns (uint256) {
        if (_index >= vestingSchedules.length) revert InvalidIndex();
        VestingSchedule storage schedule = vestingSchedules[_index];

        if (schedule.revoked || schedule.claimed) {
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
        if (schedule.revoked) revert ScheduleWasRevoked();
        if (schedule.claimed) revert ScheduleClaimed();

        uint256 releasable = calculateReleasableAmount(_index);
        if (releasable == 0) revert NothingToClaim();

        schedule.amountClaimed += releasable;
        totalLockedPerToken[schedule.token] -= releasable;

        if (schedule.amountClaimed == schedule.totalAmount) {
            schedule.claimed = true;
            emit ScheduleCompleted(_index);
        }

        emit TokensClaimed(msg.sender, _index, releasable);

        IERC20(schedule.token).safeTransfer(schedule.beneficiary, releasable);
    }

    function revoke(uint256 _index) external onlyOwner {
        if (_index >= vestingSchedules.length) revert InvalidIndex();
        VestingSchedule storage schedule = vestingSchedules[_index];

        if (schedule.revoked) revert ScheduleWasRevoked();
        if (schedule.claimed) revert ScheduleClaimed();

        uint256 releasable = calculateReleasableAmount(_index);
        uint256 refundAmount = schedule.totalAmount - (schedule.amountClaimed + releasable);

        schedule.revoked = true;
        totalLockedPerToken[schedule.token] -= (releasable + refundAmount);

        if (releasable > 0) {
            schedule.amountClaimed += releasable;
            emit TokensClaimed(schedule.beneficiary, _index, releasable);
            IERC20(schedule.token).safeTransfer(schedule.beneficiary, releasable);
        }

        if (refundAmount > 0) {
            IERC20(schedule.token).safeTransfer(msg.sender, refundAmount);
        }

        emit ScheduleRevoked(_index, refundAmount, releasable);
    }

    /**
     * @notice Withdraws any tokens that are NOT locked in vesting schedules.
     * Useful if tokens are accidentally sent to the contract address.
     */
    function withdrawExcess(address _token) external onlyOwner {
        uint256 contractBalance = IERC20(_token).balanceOf(address(this));
        uint256 lockedAmount = totalLockedPerToken[_token];

        if (contractBalance <= lockedAmount) revert InsufficientExcessBalance();

        uint256 excess = contractBalance - lockedAmount;

        emit ExcessWithdrawn(_token, excess);
        IERC20(_token).safeTransfer(msg.sender, excess);
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
