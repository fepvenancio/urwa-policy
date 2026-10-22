// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IExamplePolicy} from 'interfaces/IExamplePolicy.sol';
import {IExampleToken} from 'interfaces/IExampleToken.sol';

/**
 * @notice Seeds a policy's holder count and installs it in one call, as a governance batch would
 * @dev Needs ownership of the incoming policy and `DEFAULT_ADMIN_ROLE` on the token
 */
contract SeedAndInstall {
  /**
   * @notice Seeds a count fixed when the batch was prepared, then installs: what a static governance batch can do
   * @param _token The token
   * @param _newPolicy The incoming policy
   * @param _count The holder count, read before this call
   */
  function seedAndInstall(
    address _token,
    address _newPolicy,
    uint256 _count
  ) external {
    IExamplePolicy(_newPolicy).seedHolderCount(_count);
    IExampleToken(_token).setPolicy(_newPolicy);
  }

  /**
   * @notice Reads the outgoing policy's count in this call, then seeds and installs: nothing can land in between
   * @param _token The token
   * @param _newPolicy The incoming policy
   * @param _oldPolicy The outgoing policy, which tracks the same count
   */
  function seedFromAndInstall(
    address _token,
    address _newPolicy,
    address _oldPolicy
  ) external {
    IExamplePolicy(_newPolicy).seedHolderCount(IExamplePolicy(_oldPolicy).holderCount());
    IExampleToken(_token).setPolicy(_newPolicy);
  }
}
