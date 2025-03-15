// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// @audit interface should be implemented
interface IThunderLoan {
    // audit-function parameters ????f
    function repay(address token, uint256 amount) external;
}
