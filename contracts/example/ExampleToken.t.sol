// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IAccessControl} from '@openzeppelin/contracts/access/IAccessControl.sol';
import {IERC20Errors} from '@openzeppelin/contracts/interfaces/draft-IERC6093.sol';
import {Pausable} from '@openzeppelin/contracts/utils/Pausable.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

import {IERC7943Fungible} from 'interfaces/IERC7943Fungible.sol';
import {IERCXXXX} from 'interfaces/IERCXXXX.sol';
import {IERCXXXXPolicy, TRANSFER_OK} from 'interfaces/IERCXXXXPolicy.sol';
import {IExampleToken} from 'interfaces/IExampleToken.sol';

import {ExampleToken} from 'contracts/example/ExampleToken.sol';
import {Helpers} from 'contracts/test/Helpers.sol';

/// @notice ExampleToken in isolation: the policy is a mocked address
contract ExampleTokenUnitTest is Helpers {
  bytes32 internal constant _REJECT = keccak256('REJECT');

  ExampleToken internal _token;
  address internal _policy;
  address internal _admin = makeAddr('admin');
  address internal _minter = makeAddr('minter');
  address internal _enforcer = makeAddr('enforcer');
  address internal _pauser = makeAddr('pauser');
  address internal _alice = makeAddr('alice');
  address internal _bob = makeAddr('bob');
  address internal _spender = makeAddr('spender');

  function setUp() public {
    _policy = _mockPolicy('policy');
    _token = new ExampleToken('Example', 'EX', _admin, _policy);

    vm.startPrank(_admin);
    _token.grantRole(_token.MINTER_ROLE(), _minter);
    _token.grantRole(_token.ENFORCER_ROLE(), _enforcer);
    _token.grantRole(_token.PAUSER_ROLE(), _pauser);
    vm.stopPrank();

    vm.prank(_minter);
    _token.mint(_alice, 1000);
    vm.prank(_alice);
    _token.approve(_spender, type(uint256).max);
  }

  /// @notice A policy address that advertises the interface and permits everything until a test says otherwise
  function _mockPolicy(
    string memory _label
  ) internal returns (address _mocked) {
    _mocked = _mockContract(_label);
    vm.mockCall(_mocked, abi.encodeCall(IERC165.supportsInterface, (type(IERC165).interfaceId)), abi.encode(true));
    vm.mockCall(_mocked, abi.encodeCall(IERC165.supportsInterface, (bytes4(0xffffffff))), abi.encode(false));
    vm.mockCall(
      _mocked, abi.encodeCall(IERC165.supportsInterface, (type(IERCXXXXPolicy).interfaceId)), abi.encode(true)
    );
    vm.mockCall(_mocked, abi.encodeWithSelector(IERCXXXXPolicy.checkTransfer.selector), abi.encode(TRANSFER_OK));
    vm.mockCall(_mocked, abi.encodeWithSelector(IERCXXXXPolicy.checkSend.selector), abi.encode(TRANSFER_OK));
    vm.mockCall(_mocked, abi.encodeWithSelector(IERCXXXXPolicy.checkReceive.selector), abi.encode(TRANSFER_OK));
    vm.mockCall(_mocked, abi.encodeCall(IERCXXXXPolicy.wantsAfterTransfer, ()), abi.encode(false));
  }

  function _ctx(
    address _from,
    address _to,
    uint256 _amount,
    address _operator,
    IERCXXXXPolicy.TransferKind _kind
  ) internal view returns (IERCXXXXPolicy.TransferContext memory _context) {
    _context = IERCXXXXPolicy.TransferContext({
      token: address(_token),
      from: _from,
      to: _to,
      tokenId: 0,
      amount: _amount,
      operator: _operator,
      kind: _kind,
      data: ''
    });
  }

  function _rejectTransfers() internal {
    vm.mockCall(_policy, abi.encodeWithSelector(IERCXXXXPolicy.checkTransfer.selector), abi.encode(_REJECT));
  }

  /*///////////////////////////////////////////////////////////////
                            POLICY INSTALLATION
  //////////////////////////////////////////////////////////////*/

  function test_WhenConstructed_ItInstallsThePolicyAndEmits() public {
    vm.expectEmit();
    emit IERCXXXX.PolicyChanged(address(0), _policy);
    ExampleToken _fresh = new ExampleToken('Example', 'EX', _admin, _policy);
    assertEq(_fresh.policy(), _policy);
  }

  function test_WhenThePolicyDoesNotAdvertiseTheInterface_ItReverts() public {
    address _other = _mockPolicy('other');
    vm.mockCall(
      _other, abi.encodeCall(IERC165.supportsInterface, (type(IERCXXXXPolicy).interfaceId)), abi.encode(false)
    );
    vm.prank(_admin);
    vm.expectRevert(abi.encodeWithSelector(IExampleToken.ExampleToken_PolicyNotSupported.selector, _other));
    _token.setPolicy(_other);
  }

  function test_WhenANonAdminSetsThePolicy_ItReverts() public {
    address _other = _mockPolicy('other');
    bytes32 _adminRole = _token.DEFAULT_ADMIN_ROLE();
    vm.prank(_alice);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, _alice, _adminRole)
    );
    _token.setPolicy(_other);
  }

  function test_WhenTheAdminSetsThePolicy_ItReplacesItAndEmits() public {
    address _other = _mockPolicy('other');
    vm.expectEmit(address(_token));
    emit IERCXXXX.PolicyChanged(_policy, _other);
    vm.prank(_admin);
    _token.setPolicy(_other);
    assertEq(_token.policy(), _other);
  }

  /*///////////////////////////////////////////////////////////////
                            MOVEMENTS
  //////////////////////////////////////////////////////////////*/

  function test_WhenAHolderTransfers_ItAsksOnceWithTheTransferContext() public {
    IERCXXXXPolicy.TransferContext memory _expected =
      _ctx(_alice, _bob, 10, _alice, IERCXXXXPolicy.TransferKind.TRANSFER);
    vm.expectCall(_policy, abi.encodeCall(IERCXXXXPolicy.checkTransfer, (_expected)), 1);
    vm.expectCall(_policy, abi.encodeCall(IERCXXXXPolicy.wantsAfterTransfer, ()), 1);
    vm.expectCall(_policy, abi.encodeWithSelector(IERCXXXXPolicy.afterTransfer.selector), 0);
    vm.prank(_alice);
    assertTrue(_token.transfer(_bob, 10));
    assertEq(_token.balanceOf(_bob), 10);
  }

  function test_WhenASpenderTransfers_TheOperatorIsTheSpender() public {
    IERCXXXXPolicy.TransferContext memory _expected =
      _ctx(_alice, _bob, 10, _spender, IERCXXXXPolicy.TransferKind.TRANSFER);
    vm.expectCall(_policy, abi.encodeCall(IERCXXXXPolicy.checkTransfer, (_expected)), 1);
    vm.prank(_spender);
    assertTrue(_token.transferFrom(_alice, _bob, 10));
  }

  function test_WhenThePolicyRejects_ItRevertsWithTheReason() public {
    _rejectTransfers();
    vm.prank(_alice);
    vm.expectRevert(abi.encodeWithSelector(IERCXXXX.ERCXXXXPolicyRejected.selector, _REJECT));
    _token.transfer(_bob, 10);
  }

  function test_WhenThePolicyWantsTheCallback_ItCallsAfterTransferWithTheSameContext() public {
    vm.mockCall(_policy, abi.encodeCall(IERCXXXXPolicy.wantsAfterTransfer, ()), abi.encode(true));
    vm.mockCall(_policy, abi.encodeWithSelector(IERCXXXXPolicy.afterTransfer.selector), '');
    IERCXXXXPolicy.TransferContext memory _expected =
      _ctx(_alice, _bob, 10, _alice, IERCXXXXPolicy.TransferKind.TRANSFER);
    vm.expectCall(_policy, abi.encodeCall(IERCXXXXPolicy.afterTransfer, (_expected)), 1);
    vm.prank(_alice);
    _token.transfer(_bob, 10);
  }

  function test_WhenPaused_ItRevertsWithoutAskingThePolicy() public {
    vm.prank(_pauser);
    _token.pause();
    vm.expectCall(_policy, abi.encodeWithSelector(IERCXXXXPolicy.checkTransfer.selector), 0);
    vm.prank(_alice);
    vm.expectRevert(Pausable.EnforcedPause.selector);
    _token.transfer(_bob, 10);
  }

  function test_WhenTheAmountExceedsTheUnfrozenBalance_ItRevertsWithTheERC7943Error() public {
    vm.prank(_enforcer);
    _token.setFrozenTokens(_alice, 950);
    vm.prank(_alice);
    vm.expectRevert(
      abi.encodeWithSelector(IERC7943Fungible.ERC7943InsufficientUnfrozenBalance.selector, _alice, 51, 50)
    );
    _token.transfer(_bob, 51);
  }

  function test_WhenTheAmountExceedsTheBalance_ItRevertsWithTheERC20Error() public {
    vm.prank(_alice);
    vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, _alice, 1000, 1001));
    _token.transfer(_bob, 1001);
  }

  function test_WhenMinting_ItSendsMintWithTheMinterAsOperator() public {
    IERCXXXXPolicy.TransferContext memory _expected =
      _ctx(address(0), _bob, 5, _minter, IERCXXXXPolicy.TransferKind.MINT);
    vm.expectCall(_policy, abi.encodeCall(IERCXXXXPolicy.checkTransfer, (_expected)), 1);
    vm.prank(_minter);
    _token.mint(_bob, 5);
  }

  function test_WhenANonMinterMints_ItReverts() public {
    bytes32 _minterRole = _token.MINTER_ROLE();
    vm.prank(_alice);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, _alice, _minterRole)
    );
    _token.mint(_bob, 5);
  }

  function test_WhenAHolderBurns_ItSendsBurn() public {
    IERCXXXXPolicy.TransferContext memory _expected =
      _ctx(_alice, address(0), 5, _alice, IERCXXXXPolicy.TransferKind.BURN);
    vm.expectCall(_policy, abi.encodeCall(IERCXXXXPolicy.checkTransfer, (_expected)), 1);
    vm.prank(_alice);
    _token.burn(5);
    assertEq(_token.totalSupply(), 995);
  }

  /*///////////////////////////////////////////////////////////////
                            ENFORCEMENT
  //////////////////////////////////////////////////////////////*/

  function test_WhenForcing_ItSendsForcedWhilePausedAndPastTheFrozenAmount() public {
    vm.prank(_enforcer);
    _token.setFrozenTokens(_alice, 1500);
    vm.prank(_pauser);
    _token.pause();
    IERCXXXXPolicy.TransferContext memory _expected =
      _ctx(_alice, _bob, 100, _enforcer, IERCXXXXPolicy.TransferKind.FORCED);
    vm.expectCall(_policy, abi.encodeCall(IERCXXXXPolicy.checkTransfer, (_expected)), 1);
    vm.expectEmit(address(_token));
    emit IERC7943Fungible.ForcedTransfer(_alice, _bob, 100);
    vm.prank(_enforcer);
    assertTrue(_token.forcedTransfer(_alice, _bob, 100));
    assertEq(_token.balanceOf(_bob), 100);
  }

  function test_WhenThePolicyRejectsAForcedTransfer_ItReverts() public {
    _rejectTransfers();
    vm.prank(_enforcer);
    vm.expectRevert(abi.encodeWithSelector(IERCXXXX.ERCXXXXPolicyRejected.selector, _REJECT));
    _token.forcedTransfer(_alice, _bob, 100);
  }

  function test_WhenForcingFromZero_ItRevertsWithInvalidSender() public {
    vm.prank(_enforcer);
    vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
    _token.forcedTransfer(address(0), _bob, 1);
  }

  function test_WhenANonEnforcerForces_ItReverts() public {
    bytes32 _enforcerRole = _token.ENFORCER_ROLE();
    vm.prank(_alice);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, _alice, _enforcerRole)
    );
    _token.forcedTransfer(_alice, _bob, 1);
  }

  /// @notice Only the frozen part of what moves is unfrozen; a freeze above the balance keeps withholding
  function testFuzz_WhenForcing_ItUnfreezesOnlyTheFrozenPartMoved(
    uint256 _frozenAmount,
    uint256 _amount
  ) public {
    _frozenAmount = bound(_frozenAmount, 0, 3000);
    _amount = bound(_amount, 0, 1000);
    vm.prank(_enforcer);
    _token.setFrozenTokens(_alice, _frozenAmount);

    uint256 _free = 1000 > _frozenAmount ? 1000 - _frozenAmount : 0;
    uint256 _expected = _amount > _free ? _frozenAmount - (_amount - _free) : _frozenAmount;
    if (_amount > _free) {
      vm.expectEmit(address(_token));
      emit IERC7943Fungible.Frozen(_alice, _expected);
    }
    vm.prank(_enforcer);
    _token.forcedTransfer(_alice, _bob, _amount);
    assertEq(_token.getFrozenTokens(_alice), _expected);
  }

  function test_WhenFreezingAboveTheBalance_ItStoresAndEmits() public {
    vm.expectEmit(address(_token));
    emit IERC7943Fungible.Frozen(_alice, 5000);
    vm.prank(_enforcer);
    assertTrue(_token.setFrozenTokens(_alice, 5000));
    assertEq(_token.getFrozenTokens(_alice), 5000);
  }

  /*///////////////////////////////////////////////////////////////
                            PRE-FLIGHTS
  //////////////////////////////////////////////////////////////*/

  function test_CanTransfer_WhenThePolicyPermits_ItBuildsTheHoldersContext() public {
    IERCXXXXPolicy.TransferContext memory _expected =
      _ctx(_alice, _bob, 10, _alice, IERCXXXXPolicy.TransferKind.TRANSFER);
    vm.expectCall(_policy, abi.encodeCall(IERCXXXXPolicy.checkTransfer, (_expected)), 1);
    vm.prank(_spender);
    assertTrue(_token.canTransfer(_alice, _bob, 10));
  }

  function test_CanTransfer_WhenMintShaped_ItAsksForAMintWithTheCallerAsOperator() public {
    IERCXXXXPolicy.TransferContext memory _expected =
      _ctx(address(0), _bob, 10, _minter, IERCXXXXPolicy.TransferKind.MINT);
    vm.expectCall(_policy, abi.encodeCall(IERCXXXXPolicy.checkTransfer, (_expected)), 1);
    vm.prank(_minter);
    assertTrue(_token.canTransfer(address(0), _bob, 10));
  }

  function test_CanTransfer_WhenBurnShaped_ItAsksForABurn() public {
    IERCXXXXPolicy.TransferContext memory _expected =
      _ctx(_alice, address(0), 10, _alice, IERCXXXXPolicy.TransferKind.BURN);
    vm.expectCall(_policy, abi.encodeCall(IERCXXXXPolicy.checkTransfer, (_expected)), 1);
    assertTrue(_token.canTransfer(_alice, address(0), 10));
  }

  function test_CanTransfer_WhenBothEndpointsAreZero_ItReturnsFalseWithoutAsking() public {
    vm.expectCall(_policy, abi.encodeWithSelector(IERCXXXXPolicy.checkTransfer.selector), 0);
    assertFalse(_token.canTransfer(address(0), address(0), 1));
  }

  function test_CanTransfer_WhenPausedOrFrozen_ItReturnsFalse() public {
    vm.prank(_enforcer);
    _token.setFrozenTokens(_alice, 995);
    assertTrue(_token.canTransfer(_alice, _bob, 5));
    assertFalse(_token.canTransfer(_alice, _bob, 6));
    vm.prank(_pauser);
    _token.pause();
    assertFalse(_token.canTransfer(_alice, _bob, 5));
  }

  function test_CanTransfer_WhenThePolicyRejects_ItReturnsFalse() public {
    _rejectTransfers();
    assertFalse(_token.canTransfer(_alice, _bob, 10));
  }

  function test_CanTransfer_WhenThePolicyReverts_ItReturnsFalseWithoutReverting() public {
    vm.mockCallRevert(_policy, abi.encodeWithSelector(IERCXXXXPolicy.checkTransfer.selector), 'failure');
    assertFalse(_token.canTransfer(_alice, _bob, 10));
  }

  function test_CanTransfer_WhenTheAnswerIsShorterThanAWord_ItReturnsFalse() public {
    vm.mockCall(
      _policy, abi.encodeWithSelector(IERCXXXXPolicy.checkTransfer.selector), abi.encodePacked(bytes31(TRANSFER_OK))
    );
    assertFalse(_token.canTransfer(_alice, _bob, 10));
  }

  function test_CanSendAndCanReceive_ForwardThePolicysAnswer() public {
    // Each check is asked twice below: once permitting, once rejecting.
    vm.expectCall(_policy, abi.encodeCall(IERCXXXXPolicy.checkSend, (address(_token), _alice)), 2);
    vm.expectCall(_policy, abi.encodeCall(IERCXXXXPolicy.checkReceive, (address(_token), _alice)), 2);
    assertTrue(_token.canSend(_alice));
    assertTrue(_token.canReceive(_alice));

    vm.mockCall(_policy, abi.encodeWithSelector(IERCXXXXPolicy.checkSend.selector), abi.encode(_REJECT));
    vm.mockCall(_policy, abi.encodeWithSelector(IERCXXXXPolicy.checkReceive.selector), abi.encode(bytes32(0)));
    assertFalse(_token.canSend(_alice));
    assertFalse(_token.canReceive(_alice));
  }

  function test_SupportsInterface() public view {
    assertTrue(_token.supportsInterface(0x3edbb4c4)); // ERC-7943 fungible, as stated in ERC-7943
    assertTrue(_token.supportsInterface(type(IERCXXXX).interfaceId));
    assertTrue(_token.supportsInterface(type(IAccessControl).interfaceId));
    assertTrue(_token.supportsInterface(type(IERC165).interfaceId));
    assertFalse(_token.supportsInterface(0xffffffff));
  }
}
