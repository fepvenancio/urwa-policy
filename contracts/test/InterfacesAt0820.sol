// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERCXXXX} from 'interfaces/IERCXXXX.sol';
import {IERCXXXXPolicy, TRANSFER_OK} from 'interfaces/IERCXXXXPolicy.sol';

/// @notice Compiled alone with solc 0.8.20 (hardhat.config.ts) to prove the interfaces' minimum pragma
contract InterfacesAt0820 {
  function ids() external pure returns (bytes4 _token, bytes4 _policy, bytes32 _ok) {
    _token = type(IERCXXXX).interfaceId;
    _policy = type(IERCXXXXPolicy).interfaceId;
    _ok = TRANSFER_OK;
  }
}
