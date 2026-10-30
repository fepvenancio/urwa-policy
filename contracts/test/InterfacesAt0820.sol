// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC8473} from 'interfaces/IERC8473.sol';
import {IERC8473Policy, TRANSFER_OK} from 'interfaces/IERC8473Policy.sol';

/// @notice Compiled alone with solc 0.8.20 (hardhat.config.ts) to prove the interfaces' minimum pragma
contract InterfacesAt0820 {
  function ids() external pure returns (bytes4 _token, bytes4 _policy, bytes32 _ok) {
    _token = type(IERC8473).interfaceId;
    _policy = type(IERC8473Policy).interfaceId;
    _ok = TRANSFER_OK;
  }
}
