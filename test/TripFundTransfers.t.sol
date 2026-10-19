// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TripFund} from "../src/TripFund.sol";
import {TripFundTestBase} from "./TripFundTestBase.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {FailingERC20} from "./mocks/FailingERC20.sol";
import {CallbackERC20} from "./mocks/CallbackERC20.sol";

contract TripFundTransferFailureTest is TripFundTestBase {
    function _deployToken() internal override returns (MockERC20) {
        return new FailingERC20();
    }

    function test_ContributionReturningFalseRollsBack() public {
        _checkFailedContribution(FailingERC20.FailureMode.ReturnFalse);
    }

    function test_ContributionRevertingRollsBack() public {
        _checkFailedContribution(FailingERC20.FailureMode.Revert);
    }

    function test_RefundReturningFalseRestoresContributionAndCanBeRetried() public {
        _checkFailedRefund(FailingERC20.FailureMode.ReturnFalse);
    }

    function test_RefundRevertingRestoresContributionAndCanBeRetried() public {
        _checkFailedRefund(FailingERC20.FailureMode.Revert);
    }

    function test_WithdrawalReturningFalseRestoresFlagAndCanBeRetried() public {
        _checkFailedWithdrawal(FailingERC20.FailureMode.ReturnFalse);
    }

    function test_WithdrawalRevertingRestoresFlagAndCanBeRetried() public {
        _checkFailedWithdrawal(FailingERC20.FailureMode.Revert);
    }

    function _checkFailedContribution(FailingERC20.FailureMode mode) internal {
        _contribute(alice, 10 ether);
        vm.prank(alice);
        token.approve(address(fund), 20 ether);
        FailingERC20(address(token)).setFailureMode(mode);

        _expectFailure(mode);
        vm.prank(alice);
        fund.contribute(20 ether);

        assertEq(fund.contributions(alice), 10 ether);
        assertEq(fund.totalRaised(), 10 ether);
        assertEq(token.balanceOf(address(fund)), 10 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 10 ether);
        assertEq(token.allowance(alice, address(fund)), 20 ether);

        FailingERC20(address(token)).setFailureMode(FailingERC20.FailureMode.None);
        vm.prank(alice);
        fund.contribute(20 ether);
        assertEq(fund.totalRaised(), 30 ether);
        assertEq(fund.contributions(alice), 30 ether);
    }

    function _checkFailedRefund(FailingERC20.FailureMode mode) internal {
        _contribute(alice, 10 ether);
        vm.warp(deadline);
        FailingERC20(address(token)).setFailureMode(mode);

        _expectFailure(mode);
        vm.prank(alice);
        fund.refund();

        assertEq(fund.contributions(alice), 10 ether);
        assertEq(fund.totalRaised(), 10 ether);
        assertEq(token.balanceOf(address(fund)), 10 ether);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 10 ether);
        assertFalse(fund.withdrawn());

        FailingERC20(address(token)).setFailureMode(FailingERC20.FailureMode.None);
        _refund(alice);
        assertEq(fund.contributions(alice), 0);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(fund.totalRaised(), 10 ether);
    }

    function _checkFailedWithdrawal(FailingERC20.FailureMode mode) internal {
        _contribute(alice, GOAL);
        vm.warp(deadline);
        FailingERC20(address(token)).setFailureMode(mode);

        _expectFailure(mode);
        vm.prank(organizer);
        fund.withdraw();

        assertFalse(fund.withdrawn());
        assertEq(fund.totalRaised(), GOAL);
        assertEq(fund.contributions(alice), GOAL);
        assertEq(token.balanceOf(address(fund)), GOAL);
        assertEq(token.balanceOf(organizer), 0);

        FailingERC20(address(token)).setFailureMode(FailingERC20.FailureMode.None);
        _withdraw();
        assertTrue(fund.withdrawn());
        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(fund.totalRaised(), GOAL);
    }

    function _expectFailure(FailingERC20.FailureMode mode) internal {
        if (mode == FailingERC20.FailureMode.ReturnFalse) {
            vm.expectRevert(
                abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token))
            );
        } else {
            vm.expectRevert(FailingERC20.TransferRejected.selector);
        }
    }
}

contract TripFundInteractionTest is TripFundTestBase {
    function _deployToken() internal override returns (MockERC20) {
        return new CallbackERC20();
    }

    function test_ContributionUpdatesAccountingBeforeTransferAndBlocksReentry() public {
        CallbackERC20 observer = CallbackERC20(address(token));
        observer.configureCallback(fund, alice, abi.encodeCall(TripFund.contribute, (1)));

        _contribute(alice, 10 ether);

        assertEq(observer.observedContribution(), 10 ether);
        assertEq(observer.observedTotalRaised(), 10 ether);
        _assertReentryBlocked(observer);
        assertEq(fund.contributions(alice), 10 ether);
        assertEq(token.balanceOf(address(fund)), 10 ether);
    }

    function test_RefundClearsContributionBeforeTransferAndBlocksReentry() public {
        _contribute(alice, 10 ether);
        CallbackERC20 observer = CallbackERC20(address(token));
        observer.configureCallback(fund, alice, abi.encodeCall(TripFund.refund, ()));
        vm.warp(deadline);

        _refund(alice);

        assertEq(observer.observedContribution(), 0);
        assertEq(observer.observedTotalRaised(), 10 ether);
        _assertReentryBlocked(observer);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(fund)), 0);
    }

    function test_WithdrawalSetsFlagBeforeTransferAndBlocksReentry() public {
        _contribute(alice, GOAL);
        CallbackERC20 observer = CallbackERC20(address(token));
        observer.configureCallback(fund, alice, abi.encodeCall(TripFund.withdraw, ()));
        vm.warp(deadline);

        _withdraw();

        assertTrue(observer.observedWithdrawn());
        assertEq(observer.observedTotalRaised(), GOAL);
        _assertReentryBlocked(observer);
        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(token.balanceOf(address(fund)), 0);
    }

    function _assertReentryBlocked(CallbackERC20 observer) internal view {
        assertFalse(observer.callbackSucceeded());
        assertEq(
            observer.callbackResult(),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)
        );
    }
}
