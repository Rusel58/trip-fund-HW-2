// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TripFund} from "../src/TripFund.sol";
import {TripFundTestBase} from "./TripFundTestBase.sol";

contract TripFundTest is TripFundTestBase {
    event Contributed(address indexed contributor, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);

    function test_ConstructorStoresParametersAndStartsEmpty() public view {
        assertEq(address(fund.token()), address(token));
        assertEq(fund.organizer(), organizer);
        assertEq(fund.goal(), GOAL);
        assertEq(fund.deadline(), deadline);
        assertEq(fund.totalRaised(), 0);
        assertEq(fund.contributions(alice), 0);
        assertFalse(fund.withdrawn());
    }

    function test_RejectsZeroToken() public {
        vm.expectRevert(TripFund.ZeroAddress.selector);
        new TripFund(IERC20(address(0)), organizer, GOAL, deadline);
    }

    function test_RejectsZeroOrganizer() public {
        vm.expectRevert(TripFund.ZeroAddress.selector);
        new TripFund(token, address(0), GOAL, deadline);
    }

    function test_RejectsZeroGoal() public {
        vm.expectRevert(TripFund.ZeroGoal.selector);
        new TripFund(token, organizer, 0, deadline);
    }

    function test_RejectsDeadlineAtCurrentTimestamp() public {
        vm.expectRevert(TripFund.InvalidDeadline.selector);
        new TripFund(token, organizer, GOAL, block.timestamp);
    }

    function test_RejectsDeadlineInThePast() public {
        vm.expectRevert(TripFund.InvalidDeadline.selector);
        new TripFund(token, organizer, GOAL, block.timestamp - 1);
    }

    function test_TwoParticipantsAndRepeatedContributions() public {
        _contribute(alice, 20 ether);
        _contribute(bob, 30 ether);
        _contribute(alice, 15 ether);

        assertEq(fund.contributions(alice), 35 ether);
        assertEq(fund.contributions(bob), 30 ether);
        assertEq(fund.totalRaised(), 65 ether);
        assertEq(token.balanceOf(address(fund)), 65 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 35 ether);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE - 30 ether);
        assertEq(token.allowance(alice, address(fund)), 0);
        assertEq(token.allowance(bob, address(fund)), 0);
    }

    function test_ContributionEmitsAddressAndAmount() public {
        vm.prank(alice);
        token.approve(address(fund), 10 ether);

        vm.expectEmit(true, false, false, true, address(fund));
        emit Contributed(alice, 10 ether);
        vm.prank(alice);
        fund.contribute(10 ether);
    }

    function test_ZeroContributionRevertsWithoutChangingAccountingOrBalances() public {
        _contribute(alice, 10 ether);

        vm.expectRevert(TripFund.ZeroAmount.selector);
        vm.prank(alice);
        fund.contribute(0);

        assertEq(fund.contributions(alice), 10 ether);
        assertEq(fund.totalRaised(), 10 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 10 ether);
        assertEq(token.balanceOf(address(fund)), 10 ether);
    }

    function test_InsufficientAllowanceRollsBackAccountingAndBalances() public {
        _contribute(alice, 10 ether);
        uint256 amount = 20 ether;
        vm.prank(alice);
        token.approve(address(fund), amount - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(fund), amount - 1, amount
            )
        );
        vm.prank(alice);
        fund.contribute(amount);

        assertEq(fund.contributions(alice), 10 ether);
        assertEq(fund.totalRaised(), 10 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 10 ether);
        assertEq(token.balanceOf(address(fund)), 10 ether);
        assertEq(token.allowance(alice, address(fund)), amount - 1);
    }

    function test_InsufficientBalanceRollsBackAccountingBalancesAndAllowance() public {
        _contribute(alice, 10 ether);
        uint256 balance = token.balanceOf(alice);
        uint256 amount = balance + 1;
        vm.prank(alice);
        token.approve(address(fund), amount);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount)
        );
        vm.prank(alice);
        fund.contribute(amount);

        assertEq(fund.contributions(alice), 10 ether);
        assertEq(fund.totalRaised(), 10 ether);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(address(fund)), 10 ether);
        assertEq(token.allowance(alice, address(fund)), amount);
    }

    function test_ContributionOneSecondBeforeDeadlineSucceeds() public {
        vm.warp(deadline - 1);
        _contribute(alice, 10 ether);

        assertEq(fund.contributions(alice), 10 ether);
        assertEq(token.balanceOf(address(fund)), 10 ether);
    }

    function test_ContributionAtDeadlineRevertsWithoutChanges() public {
        _contribute(alice, 10 ether);
        vm.prank(alice);
        token.approve(address(fund), 20 ether);
        vm.warp(deadline);

        vm.expectRevert(TripFund.DeadlineReached.selector);
        vm.prank(alice);
        fund.contribute(20 ether);

        assertEq(fund.contributions(alice), 10 ether);
        assertEq(fund.totalRaised(), 10 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 10 ether);
        assertEq(token.balanceOf(address(fund)), 10 ether);
        assertEq(token.allowance(alice, address(fund)), 20 ether);
    }

    function test_ContributionAfterDeadlineReverts() public {
        vm.warp(deadline + 1);
        vm.expectRevert(TripFund.DeadlineReached.selector);
        vm.prank(alice);
        fund.contribute(1);
    }

    function test_CanContinueContributingAfterGoalBeforeDeadline() public {
        _contribute(alice, GOAL);
        _contribute(bob, 1 ether);

        assertEq(fund.totalRaised(), GOAL + 1 ether);
        assertEq(fund.contributions(bob), 1 ether);
    }

    function test_WithdrawBeforeDeadlineRevertsEvenWhenGoalReached() public {
        _contribute(alice, GOAL);
        vm.warp(deadline - 1);

        vm.expectRevert(TripFund.DeadlineNotReached.selector);
        vm.prank(organizer);
        fund.withdraw();

        assertFalse(fund.withdrawn());
        assertEq(token.balanceOf(organizer), 0);
        assertEq(token.balanceOf(address(fund)), GOAL);
    }

    function test_RefundBeforeDeadlineRevertsWhenGoalNotReached() public {
        _contribute(alice, 10 ether);
        vm.warp(deadline - 1);

        vm.expectRevert(TripFund.DeadlineNotReached.selector);
        vm.prank(alice);
        fund.refund();

        assertEq(fund.contributions(alice), 10 ether);
        assertEq(token.balanceOf(address(fund)), 10 ether);
    }

    function test_RefundBeforeDeadlineRevertsEvenWhenGoalReached() public {
        _contribute(alice, GOAL);

        vm.expectRevert(TripFund.DeadlineNotReached.selector);
        vm.prank(alice);
        fund.refund();
    }

    function test_ExactlyGoalCanBeWithdrawnAtDeadlineAndEmitsEvent() public {
        _contribute(alice, 40 ether);
        _contribute(bob, 60 ether);
        vm.warp(deadline);

        vm.expectEmit(true, false, false, true, address(fund));
        emit Withdrawn(organizer, GOAL);
        _withdraw();

        assertTrue(fund.withdrawn());
        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 40 ether);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE - 60 ether);
        assertEq(fund.totalRaised(), GOAL);
        assertEq(fund.contributions(alice), 40 ether);
        assertEq(fund.contributions(bob), 60 ether);
    }

    function test_AboveGoalPaysEntireAccountedSum() public {
        _contribute(alice, 80 ether);
        _contribute(bob, 70 ether);
        vm.warp(deadline + 1);
        _withdraw();

        assertEq(token.balanceOf(organizer), 150 ether);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(fund.totalRaised(), 150 ether);
    }

    function test_NonOrganizerCannotWithdraw() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);

        vm.expectRevert(TripFund.NotOrganizer.selector);
        vm.prank(alice);
        fund.withdraw();

        assertFalse(fund.withdrawn());
        assertEq(token.balanceOf(address(fund)), GOAL);
        assertEq(token.balanceOf(organizer), 0);
    }

    function test_SecondWithdrawalReverts() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);
        _withdraw();

        vm.expectRevert(TripFund.AlreadyWithdrawn.selector);
        vm.prank(organizer);
        fund.withdraw();

        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(fund.totalRaised(), GOAL);
    }

    function test_UnsuccessfulFundCannotBeWithdrawn() public {
        _contribute(alice, GOAL - 1);
        vm.warp(deadline);

        vm.expectRevert(TripFund.GoalNotReached.selector);
        vm.prank(organizer);
        fund.withdraw();

        assertFalse(fund.withdrawn());
        assertEq(token.balanceOf(address(fund)), GOAL - 1);
    }

    function test_IndependentRefundsReturnFullRepeatedContributions() public {
        _contribute(alice, 10 ether);
        _contribute(bob, 30 ether);
        _contribute(alice, 15 ether);
        vm.warp(deadline);

        vm.expectEmit(true, false, false, true, address(fund));
        emit Refunded(alice, 25 ether);
        _refund(alice);

        assertEq(fund.contributions(alice), 0);
        assertEq(fund.contributions(bob), 30 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE - 30 ether);
        assertEq(token.balanceOf(address(fund)), 30 ether);
        assertEq(fund.totalRaised(), 55 ether);

        _refund(bob);

        assertEq(fund.contributions(bob), 0);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(token.balanceOf(organizer), 0);
        assertEq(fund.totalRaised(), 55 ether);
        assertFalse(fund.withdrawn());
    }

    function test_RefundWithoutContributionReverts() public {
        _contribute(alice, 10 ether);
        vm.warp(deadline);

        vm.expectRevert(TripFund.NoContribution.selector);
        vm.prank(outsider);
        fund.refund();

        assertEq(token.balanceOf(outsider), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(fund)), 10 ether);
    }

    function test_SecondRefundReverts() public {
        _contribute(alice, 10 ether);
        vm.warp(deadline);
        _refund(alice);

        vm.expectRevert(TripFund.NoContribution.selector);
        vm.prank(alice);
        fund.refund();

        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(fund.totalRaised(), 10 ether);
    }

    function test_SuccessfulFundCannotBeRefundedBeforeWithdrawal() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);

        vm.expectRevert(TripFund.GoalReached.selector);
        vm.prank(alice);
        fund.refund();

        assertEq(fund.contributions(alice), GOAL);
        assertEq(token.balanceOf(address(fund)), GOAL);
    }

    function test_SuccessfulFundCannotBeRefundedAfterWithdrawal() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);
        _withdraw();

        vm.expectRevert(TripFund.GoalReached.selector);
        vm.prank(alice);
        fund.refund();

        assertEq(fund.totalRaised(), GOAL);
        assertEq(token.balanceOf(organizer), GOAL);
    }

    function test_DirectTransfersStayAfterSuccessfulWithdrawal() public {
        _contribute(alice, GOAL);
        _donate(7 ether);

        assertEq(fund.totalRaised(), GOAL);
        assertEq(fund.contributions(outsider), 0);
        assertEq(token.balanceOf(address(fund)), GOAL + 7 ether);

        vm.warp(deadline);
        _withdraw();

        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(token.balanceOf(address(fund)), 7 ether);
        assertEq(token.balanceOf(outsider), INITIAL_BALANCE - 7 ether);
        assertEq(fund.totalRaised(), GOAL);
    }

    function test_DirectTransfersDoNotTurnFailureIntoSuccessAndStayAfterRefunds() public {
        _contribute(alice, 20 ether);
        _contribute(bob, 30 ether);
        _donate(GOAL);

        assertEq(token.balanceOf(address(fund)), 150 ether);
        assertEq(fund.totalRaised(), 50 ether);
        assertEq(fund.contributions(outsider), 0);
        vm.warp(deadline);

        vm.expectRevert(TripFund.GoalNotReached.selector);
        vm.prank(organizer);
        fund.withdraw();

        _refund(bob);
        _refund(alice);

        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(fund)), GOAL);
        assertEq(fund.totalRaised(), 50 ether);

        vm.expectRevert(TripFund.NoContribution.selector);
        vm.prank(outsider);
        fund.refund();
    }

    function test_EmptyFundClosesWithoutPayouts() public {
        vm.warp(deadline);

        vm.expectRevert(TripFund.GoalNotReached.selector);
        vm.prank(organizer);
        fund.withdraw();

        vm.expectRevert(TripFund.NoContribution.selector);
        vm.prank(alice);
        fund.refund();

        assertEq(fund.totalRaised(), 0);
        assertEq(token.balanceOf(address(fund)), 0);
    }

    function testFuzz_RepeatedContributionsAccumulate(uint96 first, uint96 second, uint96 other) public {
        uint256 a = bound(uint256(first), 1, 300 ether);
        uint256 b = bound(uint256(second), 1, 300 ether);
        uint256 c = bound(uint256(other), 1, 300 ether);

        _contribute(alice, a);
        _contribute(bob, c);
        _contribute(alice, b);

        assertEq(fund.contributions(alice), a + b);
        assertEq(fund.contributions(bob), c);
        assertEq(fund.totalRaised(), a + b + c);
        assertEq(token.balanceOf(address(fund)), a + b + c);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - a - b);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE - c);
    }

    function testFuzz_WithdrawalPaysOnlyContributions(uint96 extra, uint96 donation) public {
        uint256 contribution = bound(uint256(extra), GOAL, INITIAL_BALANCE);
        uint256 directTransfer = bound(uint256(donation), 1, INITIAL_BALANCE);

        _contribute(alice, contribution);
        _donate(directTransfer);
        vm.warp(deadline);
        _withdraw();

        assertEq(token.balanceOf(organizer), contribution);
        assertEq(token.balanceOf(address(fund)), directTransfer);
        assertEq(fund.totalRaised(), contribution);
        assertTrue(fund.withdrawn());
    }

    function testFuzz_RefundsLeaveOnlyDirectTransfers(uint96 first, uint96 second, uint96 donation) public {
        uint256 a = bound(uint256(first), 1, GOAL / 2 - 1);
        uint256 b = bound(uint256(second), 1, GOAL / 2 - 1);
        uint256 directTransfer = bound(uint256(donation), 1, INITIAL_BALANCE);

        _contribute(alice, a);
        _contribute(bob, b);
        _donate(directTransfer);
        vm.warp(deadline);
        _refund(bob);
        _refund(alice);

        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(fund)), directTransfer);
        assertEq(fund.contributions(alice), 0);
        assertEq(fund.contributions(bob), 0);
        assertEq(fund.totalRaised(), a + b);
    }
}
