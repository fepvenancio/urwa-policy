// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ERC165} from '@openzeppelin/contracts/utils/introspection/ERC165.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

import {IERCXXXXPolicy, TRANSFER_OK} from 'interfaces/IERCXXXXPolicy.sol';

/// @notice Permits everything; the base of the faulty policies below
abstract contract PermissivePolicy is ERC165, IERCXXXXPolicy {
  function afterTransfer(
    TransferContext calldata
  ) external virtual {}

  function checkReceive(
    address,
    address
  ) external view virtual returns (bytes32 _reason) {
    _reason = TRANSFER_OK;
  }

  function checkSend(
    address,
    address
  ) external view virtual returns (bytes32 _reason) {
    _reason = TRANSFER_OK;
  }

  function checkTransfer(
    TransferContext calldata
  ) external view virtual returns (bytes32 _reason) {
    _reason = TRANSFER_OK;
  }

  function wantsAfterTransfer() external view virtual returns (bool _wantsAfter) {
    _wantsAfter = false;
  }

  function supportsInterface(
    bytes4 _interfaceId
  ) public view override(ERC165, IERC165) returns (bool _supported) {
    _supported = _interfaceId == type(IERCXXXXPolicy).interfaceId || super.supportsInterface(_interfaceId);
  }
}

/// @notice Its author handled TRANSFER and forgot every other kind: the unassigned return value is zero
contract ForgetfulPolicy is PermissivePolicy {
  function checkTransfer(
    TransferContext calldata _context
  ) external pure override returns (bytes32 _reason) {
    if (_context.kind == TransferKind.TRANSFER) _reason = TRANSFER_OK;
  }
}

/// @notice Reverts on every movement check
contract RevertingPolicy is PermissivePolicy {
  error RevertingPolicy_Failure();

  function checkTransfer(
    TransferContext calldata
  ) external pure override returns (bytes32) {
    revert RevertingPolicy_Failure();
  }
}

/// @notice Answers the movement check with 31 bytes: too short to decode as a bytes32
contract ShortReturnPolicy is PermissivePolicy {
  function checkTransfer(
    TransferContext calldata
  ) external pure override returns (bytes32) {
    assembly {
      mstore(0x00, 0x2a5b6d0c00000000000000000000000000000000000000000000000000000000)
      return(0x00, 31)
    }
  }
}

/// @notice Answers `wantsAfterTransfer` with the word 2, which is not a valid bool
contract BadBoolPolicy is PermissivePolicy {
  function wantsAfterTransfer() external pure override returns (bool) {
    assembly {
      mstore(0x00, 2)
      return(0x00, 0x20)
    }
  }
}

/// @notice Answers `wantsAfterTransfer` with 31 bytes
contract ShortBoolPolicy is PermissivePolicy {
  function wantsAfterTransfer() external pure override returns (bool) {
    assembly {
      mstore(0x00, 0)
      return(0x00, 31)
    }
  }
}

/// @notice Tries to start a second movement from inside `afterTransfer`
contract ReentrantPolicy is PermissivePolicy {
  function wantsAfterTransfer() external pure override returns (bool _wantsAfter) {
    _wantsAfter = true;
  }

  function afterTransfer(
    TransferContext calldata _context
  ) external override {
    // solhint-disable-next-line custom-errors
    require(IERC20(_context.token).transfer(address(0xBEEF), 1), 'unreachable');
  }
}

/// @notice Answers every call with its own calldata
contract EchoContract {
  fallback() external {
    assembly {
      calldatacopy(0x00, 0x00, calldatasize())
      return(0x00, calldatasize())
    }
  }
}

/// @notice The policy ABI with the kind as a raw uint8, to send a value outside the enumeration
interface IRawPolicy {
  struct RawContext {
    address token;
    address from;
    address to;
    uint256 tokenId;
    uint256 amount;
    address operator;
    uint8 kind;
    bytes data;
  }

  function checkTransfer(
    RawContext calldata _context
  ) external view returns (bytes32 _reason);
}
