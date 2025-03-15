// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;

// audit not used imports ?
// bad practise for using IThunderLoan import from this IFlashLoanReceiver interface for testing/mocks
import { IThunderLoan } from "./IThunderLoan.sol";

/**
 * @dev Inspired by Aave:
 * https://github.com/aave/aave-v3-core/blob/master/contracts/flashloan/interfaces/IFlashLoanReceiver.sol
 */
// q is the token need to be borrowed
// q ??? parameters
// @audit no natspecs

interface IFlashLoanReceiver {
    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    )
        external
        returns (bool);
}
