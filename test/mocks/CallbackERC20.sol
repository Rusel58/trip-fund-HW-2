// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TripFund} from "../../src/TripFund.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev Observes fund state during a transfer and tries to reenter the fund.
contract CallbackERC20 is MockERC20 {
    TripFund private _fund;
    address private _contributor;
    bytes private _callData;

    uint256 public observedContribution;
    uint256 public observedTotalRaised;
    bool public observedWithdrawn;
    bool public callbackSucceeded;
    bytes public callbackResult;

    function configureCallback(TripFund fund, address contributor, bytes calldata callData) external {
        _fund = fund;
        _contributor = contributor;
        _callData = callData;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _observeAndReenter();
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _observeAndReenter();
        return super.transferFrom(from, to, amount);
    }

    function _observeAndReenter() private {
        if (address(_fund) == address(0)) return;

        observedContribution = _fund.contributions(_contributor);
        observedTotalRaised = _fund.totalRaised();
        observedWithdrawn = _fund.withdrawn();
        (callbackSucceeded, callbackResult) = address(_fund).call(_callData);
    }
}
