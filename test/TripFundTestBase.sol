// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TripFund} from "../src/TripFund.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

abstract contract TripFundTestBase is Test {
    uint256 internal constant GOAL = 100 ether;
    uint256 internal constant INITIAL_BALANCE = 1_000 ether;

    MockERC20 internal token;
    TripFund internal fund;
    address internal organizer;
    address internal alice;
    address internal bob;
    address internal outsider;
    uint256 internal deadline;

    function setUp() public virtual {
        vm.warp(1_700_000_000);
        organizer = makeAddr("organizer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        outsider = makeAddr("outsider");
        deadline = block.timestamp + 7 days;

        token = _deployToken();
        fund = new TripFund(token, organizer, GOAL, deadline);
        token.mint(alice, INITIAL_BALANCE);
        token.mint(bob, INITIAL_BALANCE);
        token.mint(outsider, INITIAL_BALANCE);
    }

    function _deployToken() internal virtual returns (MockERC20) {
        return new MockERC20();
    }

    function _contribute(address contributor, uint256 amount) internal {
        vm.startPrank(contributor);
        token.approve(address(fund), amount);
        fund.contribute(amount);
        vm.stopPrank();
    }

    function _refund(address contributor) internal {
        vm.prank(contributor);
        fund.refund();
    }

    function _withdraw() internal {
        vm.prank(organizer);
        fund.withdraw();
    }

    function _donate(uint256 amount) internal {
        vm.prank(outsider);
        token.transfer(address(fund), amount);
    }
}
