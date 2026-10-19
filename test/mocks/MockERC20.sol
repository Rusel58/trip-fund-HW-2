// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Local test token with 18 decimals, no transfer fees and no rebasing.
contract MockERC20 is ERC20 {
    constructor() ERC20("Trip Test Token", "TRIP") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
