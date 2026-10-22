// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from 'forge-std/Test.sol';

/// @notice Shared test helpers
abstract contract Helpers is Test {
  /**
   * @notice A labelled address with code, so calls to it reach `vm.mockCall` and pass code-length checks
   * @param _label The label
   * @return _contract The address
   */
  function _mockContract(
    string memory _label
  ) internal returns (address _contract) {
    _contract = makeAddr(_label);
    vm.etch(_contract, hex'01');
  }
}
