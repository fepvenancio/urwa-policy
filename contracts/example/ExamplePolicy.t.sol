// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

import {IERCXXXX} from 'interfaces/IERCXXXX.sol';
import {IERCXXXXPolicy, TRANSFER_OK} from 'interfaces/IERCXXXXPolicy.sol';
import {IExamplePolicy} from 'interfaces/IExamplePolicy.sol';

import {ExamplePolicy} from 'contracts/example/ExamplePolicy.sol';
import {IRawPolicy} from 'contracts/test/FaultyPolicies.sol';
import {Helpers} from 'contracts/test/Helpers.sol';

/// @notice ExamplePolicy in isolation: the token is a mocked address whose balances each test sets
contract ExamplePolicyUnitTest is Helpers {
  ExamplePolicy internal _policy;
  address internal _token;
  address internal _owner = makeAddr('owner');
  address internal _alice = makeAddr('alice');
  address internal _bob = makeAddr('bob');
  address internal _carol = makeAddr('carol');
  address internal _stranger = makeAddr('stranger');

  function setUp() public {
    _token = _mockContract('token');
    _policy = new ExamplePolicy(_token, _owner, 10);
    vm.startPrank(_owner);
    _policy.setAllowlisted(_alice, true);
    _policy.setAllowlisted(_bob, true);
    _policy.setAllowlisted(_carol, true);
    vm.stopPrank();
    _balance(_alice, 0);
    _balance(_bob, 0);
    _balance(_carol, 0);
    _balance(_stranger, 0);
  }

  function _balance(
    address _account,
    uint256 _amount
  ) internal {
    vm.mockCall(_token, abi.encodeCall(IERC20.balanceOf, (_account)), abi.encode(_amount));
  }

  function _ctx(
    address _from,
    address _to,
    uint256 _amount,
    IERCXXXXPolicy.TransferKind _kind
  ) internal view returns (IERCXXXXPolicy.TransferContext memory _context) {
    _context = IERCXXXXPolicy.TransferContext({
      token: _token,
      from: _from,
      to: _to,
      tokenId: 0,
      amount: _amount,
      operator: _from == address(0) ? _owner : _from,
      kind: _kind,
      data: ''
    });
  }

  /// @notice Counts `_to` as a holder the way the token would: balance set after the movement, then `afterTransfer`
  function _countNewHolder(
    address _to,
    uint256 _amount
  ) internal {
    _balance(_to, _amount);
    vm.prank(_token);
    _policy.afterTransfer(_ctx(address(0), _to, _amount, IERCXXXXPolicy.TransferKind.MINT));
  }

  /// @dev Maps a fuzzed seed onto a kind other than FORCED
  function _nonForcedKind(
    uint8 _seed
  ) internal pure returns (IERCXXXXPolicy.TransferKind _kind) {
    IERCXXXXPolicy.TransferKind[4] memory _kinds = [
      IERCXXXXPolicy.TransferKind.TRANSFER,
      IERCXXXXPolicy.TransferKind.EXECUTED,
      IERCXXXXPolicy.TransferKind.MINT,
      IERCXXXXPolicy.TransferKind.BURN
    ];
    _kind = _kinds[_seed % 4];
  }

  /*///////////////////////////////////////////////////////////////
                            CONSTRUCTION AND ADMIN
  //////////////////////////////////////////////////////////////*/

  function test_WhenConstructed_ItStoresTheTokenAndTheCapAndEmits() public {
    vm.expectEmit();
    emit IExamplePolicy.CapSet(3);
    ExamplePolicy _fresh = new ExamplePolicy(_token, _owner, 3);
    assertEq(_fresh.TOKEN(), _token);
    assertEq(_fresh.cap(), 3);
    assertEq(_fresh.owner(), _owner);
  }

  function test_WhenTheTokenIsZero_ItReverts() public {
    vm.expectRevert(IExamplePolicy.ExamplePolicy_ZeroAddress.selector);
    new ExamplePolicy(address(0), _owner, 1);
  }

  function test_WhenTheOwnerSetsTheAllowlistAndTheCap_ItStoresAndEmits() public {
    vm.expectEmit(address(_policy));
    emit IExamplePolicy.AllowlistSet(_stranger, true);
    vm.prank(_owner);
    _policy.setAllowlisted(_stranger, true);
    assertTrue(_policy.allowlisted(_stranger));

    vm.expectEmit(address(_policy));
    emit IExamplePolicy.CapSet(7);
    vm.prank(_owner);
    _policy.setCap(7);
    assertEq(_policy.cap(), 7);
  }

  function test_WhenANonOwnerAdministers_ItReverts() public {
    vm.startPrank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _stranger));
    _policy.setAllowlisted(_stranger, true);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _stranger));
    _policy.setCap(1);
    vm.stopPrank();
  }

  /*///////////////////////////////////////////////////////////////
                            SEEDING THE HOLDER COUNT
  //////////////////////////////////////////////////////////////*/

  function _installed(
    bool _isInstalled
  ) internal {
    address _current = _isInstalled ? address(_policy) : _stranger;
    vm.mockCall(_token, abi.encodeCall(IERCXXXX.policy, ()), abi.encode(_current));
  }

  function test_WhenTheOwnerSeedsBeforeInstallation_ItSetsTheCountAndEmits() public {
    _installed(false);
    vm.expectEmit(address(_policy));
    emit IExamplePolicy.HolderCountSeeded(0, 5);
    vm.prank(_owner);
    _policy.seedHolderCount(5);
    assertEq(_policy.holderCount(), 5);
  }

  function test_WhenTheTokenDoesNotExistYet_SeedingIsAllowed() public {
    ExamplePolicy _early = new ExamplePolicy(makeAddr('future token'), _owner, 10);
    vm.prank(_owner);
    _early.seedHolderCount(3);
    assertEq(_early.holderCount(), 3);
  }

  function test_WhenTheTokenHasInstalledThePolicy_SeedingReverts() public {
    _installed(true);
    vm.prank(_owner);
    vm.expectRevert(IExamplePolicy.ExamplePolicy_AlreadyInstalled.selector);
    _policy.seedHolderCount(5);
  }

  function test_WhenANonOwnerSeeds_ItReverts() public {
    _installed(false);
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _stranger));
    _policy.seedHolderCount(5);
  }

  /*///////////////////////////////////////////////////////////////
                            ACCOUNT CHECKS
  //////////////////////////////////////////////////////////////*/

  function test_AccountChecks_FollowTheAllowlist() public view {
    assertEq(_policy.checkSend(_token, _alice), TRANSFER_OK);
    assertEq(_policy.checkReceive(_token, _alice), TRANSFER_OK);
    assertEq(_policy.checkSend(_token, _stranger), _policy.SENDER_NOT_ELIGIBLE());
    assertEq(_policy.checkReceive(_token, _stranger), _policy.RECEIVER_NOT_ELIGIBLE());
  }

  function test_AccountChecks_WhenTheTokenIsUnknown_ItReturnsUnknownToken() public view {
    assertEq(_policy.checkSend(_stranger, _alice), _policy.UNKNOWN_TOKEN());
    assertEq(_policy.checkReceive(_stranger, _alice), _policy.UNKNOWN_TOKEN());
  }

  /*///////////////////////////////////////////////////////////////
                            TRANSFER CHECK
  //////////////////////////////////////////////////////////////*/

  function test_CheckTransfer_WhenTheTokenIsUnknown_ItReturnsUnknownToken() public view {
    IERCXXXXPolicy.TransferContext memory _context = _ctx(_alice, _bob, 1, IERCXXXXPolicy.TransferKind.TRANSFER);
    _context.token = _stranger;
    assertEq(_policy.checkTransfer(_context), _policy.UNKNOWN_TOKEN());
  }

  /// @notice Requirement 4: for every kind except FORCED, a failed account check rejects the movement
  function testFuzz_CheckTransfer_WhenAnAccountCheckFails_ItRejects(
    uint8 _seed,
    bool _fromAllowed,
    bool _toAllowed
  ) public {
    IERCXXXXPolicy.TransferKind _kind = _nonForcedKind(_seed);
    address _from = _kind == IERCXXXXPolicy.TransferKind.MINT ? address(0) : _alice;
    address _to = _kind == IERCXXXXPolicy.TransferKind.BURN ? address(0) : _bob;
    vm.startPrank(_owner);
    _policy.setAllowlisted(_alice, _fromAllowed);
    _policy.setAllowlisted(_bob, _toAllowed);
    vm.stopPrank();
    _balance(_alice, 10);

    bytes32 _reason = _policy.checkTransfer(_ctx(_from, _to, 1, _kind));
    bool _accountsPass = (_from == address(0) || _fromAllowed) && (_to == address(0) || _toAllowed);
    assertEq(_reason == TRANSFER_OK, _accountsPass);
  }

  function test_CheckTransfer_WhenForced_ItChecksOnlyTheReceiverAndIgnoresTheCap() public {
    vm.prank(_owner);
    _policy.setCap(0);
    _balance(_stranger, 10);
    assertEq(_policy.checkTransfer(_ctx(_stranger, _bob, 10, IERCXXXXPolicy.TransferKind.FORCED)), TRANSFER_OK);
    assertEq(
      _policy.checkTransfer(_ctx(_alice, _stranger, 10, IERCXXXXPolicy.TransferKind.FORCED)),
      _policy.RECEIVER_NOT_ELIGIBLE()
    );
    assertEq(_policy.checkTransfer(_ctx(_stranger, address(0), 10, IERCXXXXPolicy.TransferKind.FORCED)), TRANSFER_OK);
  }

  /// @notice TRANSFER, MINT and BURN decisions cannot depend on `operator`
  function testFuzz_CheckTransfer_NeverReadsTheOperator(
    uint8 _seed,
    address _operator
  ) public {
    IERCXXXXPolicy.TransferKind _kind = _nonForcedKind(_seed);
    address _from = _kind == IERCXXXXPolicy.TransferKind.MINT ? address(0) : _alice;
    address _to = _kind == IERCXXXXPolicy.TransferKind.BURN ? address(0) : _bob;
    _balance(_alice, 10);
    IERCXXXXPolicy.TransferContext memory _context = _ctx(_from, _to, 1, _kind);
    bytes32 _reference = _policy.checkTransfer(_context);
    _context.operator = _operator;
    assertEq(_policy.checkTransfer(_context), _reference);
  }

  function test_CheckTransfer_WhenTheReceiverAlreadyHolds_ItIsNeverCapped() public {
    vm.prank(_owner);
    _policy.setCap(0);
    _balance(_alice, 10);
    _balance(_bob, 5);
    assertEq(_policy.checkTransfer(_ctx(_alice, _bob, 1, IERCXXXXPolicy.TransferKind.TRANSFER)), TRANSFER_OK);
  }

  function test_CheckTransfer_AtTheCap_ANewHolderIsRejectedUnlessTheSenderLeaves() public {
    vm.prank(_owner);
    _policy.setCap(1);
    _countNewHolder(_alice, 10);
    assertEq(_policy.checkTransfer(_ctx(_alice, _bob, 9, IERCXXXXPolicy.TransferKind.TRANSFER)), _policy.MAX_HOLDERS());
    assertEq(_policy.checkTransfer(_ctx(_alice, _bob, 10, IERCXXXXPolicy.TransferKind.TRANSFER)), TRANSFER_OK);
    assertEq(_policy.checkTransfer(_ctx(address(0), _bob, 1, IERCXXXXPolicy.TransferKind.MINT)), _policy.MAX_HOLDERS());
  }

  function test_CheckTransfer_AboveALoweredCap_NoNewHolderIsAdmitted() public {
    _countNewHolder(_alice, 10);
    _countNewHolder(_bob, 10);
    vm.prank(_owner);
    _policy.setCap(1);
    assertEq(
      _policy.checkTransfer(_ctx(_alice, _carol, 10, IERCXXXXPolicy.TransferKind.TRANSFER)), _policy.MAX_HOLDERS()
    );
    assertEq(_policy.checkTransfer(_ctx(_alice, _bob, 10, IERCXXXXPolicy.TransferKind.TRANSFER)), TRANSFER_OK);
    assertEq(_policy.checkTransfer(_ctx(_alice, address(0), 10, IERCXXXXPolicy.TransferKind.BURN)), TRANSFER_OK);
  }

  function test_CheckTransfer_WhenTheKindIsOutsideTheEnumeration_ItReverts() public view {
    IRawPolicy.RawContext memory _raw = IRawPolicy.RawContext({
      token: _token, from: _alice, to: _bob, tokenId: 0, amount: 1, operator: _alice, kind: 5, data: ''
    });
    (bool _success,) = address(_policy).staticcall(abi.encodeCall(IRawPolicy.checkTransfer, (_raw)));
    assertFalse(_success);

    _raw.kind = 4; // BURN: the highest valid value decodes
    (_success,) = address(_policy).staticcall(abi.encodeCall(IRawPolicy.checkTransfer, (_raw)));
    assertTrue(_success);
  }

  /*///////////////////////////////////////////////////////////////
                            AFTER TRANSFER
  //////////////////////////////////////////////////////////////*/

  function test_AfterTransfer_WhenTheCallerIsNotTheToken_ItReverts() public {
    vm.prank(_stranger);
    vm.expectRevert(abi.encodeWithSelector(IExamplePolicy.ExamplePolicy_OnlyToken.selector, _stranger));
    _policy.afterTransfer(_ctx(address(0), _alice, 1, IERCXXXXPolicy.TransferKind.MINT));
  }

  function test_AfterTransfer_WhenTheContextNamesAnotherToken_ItReverts() public {
    IERCXXXXPolicy.TransferContext memory _context = _ctx(address(0), _alice, 1, IERCXXXXPolicy.TransferKind.MINT);
    _context.token = _stranger;
    vm.prank(_token);
    vm.expectRevert(abi.encodeWithSelector(IExamplePolicy.ExamplePolicy_OnlyToken.selector, _token));
    _policy.afterTransfer(_context);
  }

  function test_AfterTransfer_CountsArrivalsAndDepartures() public {
    _countNewHolder(_alice, 10);
    assertEq(_policy.holderCount(), 1);

    // alice sends everything to bob: alice leaves, bob arrives
    _balance(_alice, 0);
    _balance(_bob, 10);
    vm.prank(_token);
    _policy.afterTransfer(_ctx(_alice, _bob, 10, IERCXXXXPolicy.TransferKind.TRANSFER));
    assertEq(_policy.holderCount(), 1);

    // bob burns everything
    _balance(_bob, 0);
    vm.prank(_token);
    _policy.afterTransfer(_ctx(_bob, address(0), 10, IERCXXXXPolicy.TransferKind.BURN));
    assertEq(_policy.holderCount(), 0);
  }

  function test_AfterTransfer_ZeroAmountsAndSelfTransfersChangeNothing() public {
    _countNewHolder(_alice, 10);
    vm.startPrank(_token);
    _policy.afterTransfer(_ctx(_alice, _bob, 0, IERCXXXXPolicy.TransferKind.TRANSFER));
    _policy.afterTransfer(_ctx(_alice, _alice, 10, IERCXXXXPolicy.TransferKind.TRANSFER));
    vm.stopPrank();
    assertEq(_policy.holderCount(), 1);
  }

  function test_WantsAfterTransferAndSupportsInterface() public view {
    assertTrue(_policy.wantsAfterTransfer());
    assertTrue(_policy.supportsInterface(type(IERCXXXXPolicy).interfaceId));
    assertTrue(_policy.supportsInterface(type(IERC165).interfaceId));
    assertFalse(_policy.supportsInterface(0xffffffff));
  }
}
