// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title TripFund
/// @notice Collects one ERC-20 token for a team trip until a fixed deadline.
/// @dev Assumes a token without transfer fees or rebasing. Direct transfers are not contributions.
contract TripFund is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroGoal();
    error InvalidDeadline();
    error ZeroAmount();
    error DeadlineReached();
    error DeadlineNotReached();
    error NotOrganizer();
    error GoalNotReached();
    error GoalReached();
    error AlreadyWithdrawn();
    error NoContribution();

    event Contributed(address indexed contributor, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);

    IERC20 public immutable token;
    address public immutable organizer;
    uint256 public immutable goal;
    uint256 public immutable deadline;

    mapping(address contributor => uint256 amount) public contributions;

    /// @notice Lifetime sum of accepted contributions; payouts never decrease it.
    uint256 public totalRaised;
    bool public withdrawn;

    /// @param token_ ERC-20 used for all contributions and payouts.
    /// @param organizer_ Recipient of a successful fund's single withdrawal.
    /// @param goal_ Target amount in the token's smallest units.
    /// @param deadline_ Exclusive contribution deadline, as a Unix timestamp in seconds.
    constructor(IERC20 token_, address organizer_, uint256 goal_, uint256 deadline_) {
        if (address(token_) == address(0) || organizer_ == address(0)) revert ZeroAddress();
        if (goal_ == 0) revert ZeroGoal();
        if (deadline_ <= block.timestamp) revert InvalidDeadline();

        token = token_;
        organizer = organizer_;
        goal = goal_;
        deadline = deadline_;
    }

    /// @notice Adds to the caller's contribution before the deadline.
    /// @dev The caller must first approve this contract to spend at least amount tokens.
    function contribute(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp >= deadline) revert DeadlineReached();

        contributions[msg.sender] += amount;
        totalRaised += amount;

        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Contributed(msg.sender, amount);
    }

    /// @notice Pays all accounted contributions to the organizer after a successful fund closes.
    function withdraw() external nonReentrant {
        if (msg.sender != organizer) revert NotOrganizer();
        if (block.timestamp < deadline) revert DeadlineNotReached();
        if (totalRaised < goal) revert GoalNotReached();
        if (withdrawn) revert AlreadyWithdrawn();

        withdrawn = true;
        uint256 amount = totalRaised;

        token.safeTransfer(organizer, amount);
        emit Withdrawn(organizer, amount);
    }

    /// @notice Returns the caller's full contribution after an unsuccessful fund closes.
    function refund() external nonReentrant {
        if (block.timestamp < deadline) revert DeadlineNotReached();
        if (totalRaised >= goal) revert GoalReached();

        uint256 amount = contributions[msg.sender];
        if (amount == 0) revert NoContribution();
        contributions[msg.sender] = 0;

        token.safeTransfer(msg.sender, amount);
        emit Refunded(msg.sender, amount);
    }
}
