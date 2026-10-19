// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MockERC20} from "./MockERC20.sol";

/// @dev Exercises both ERC-20 failure conventions: false return values and reverts.
contract FailingERC20 is MockERC20 {
    enum FailureMode {
        None,
        ReturnFalse,
        Revert
    }

    error TransferRejected();

    FailureMode public failureMode;

    function setFailureMode(FailureMode mode) external {
        failureMode = mode;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (failureMode == FailureMode.Revert) revert TransferRejected();
        if (failureMode == FailureMode.ReturnFalse) return false;
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (failureMode == FailureMode.Revert) revert TransferRejected();
        if (failureMode == FailureMode.ReturnFalse) return false;
        return super.transferFrom(from, to, amount);
    }
}
