// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Errors} from '@openzeppelin/contracts/interfaces/draft-IERC6093.sol';
import {Pausable} from '@openzeppelin/contracts/utils/Pausable.sol';
import {ReentrancyGuardTransient} from '@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol';
import {stdError} from 'forge-std/StdError.sol';

import {IERC7943Fungible} from 'interfaces/IERC7943Fungible.sol';
import {IERCXXXX} from 'interfaces/IERCXXXX.sol';
import {IERCXXXXPolicy, TRANSFER_OK} from 'interfaces/IERCXXXXPolicy.sol';
import {IExamplePolicy} from 'interfaces/IExamplePolicy.sol';

import {ExamplePolicy} from 'contracts/example/ExamplePolicy.sol';
import {ExampleToken} from 'contracts/example/ExampleToken.sol';
import {
  BadBoolPolicy,
  EchoContract,
  ForgetfulPolicy,
  ReentrantPolicy,
  RevertingPolicy,
  ShortBoolPolicy,
  ShortReturnPolicy
} from 'contracts/test/FaultyPolicies.sol';
import {ForcedThenTransfer} from 'contracts/test/ForcedThenTransfer.sol';
import {Helpers} from 'contracts/test/Helpers.sol';
import {SeedAndInstall} from 'contracts/test/SeedAndInstall.sol';

/// @notice The ERC-20 Transfer event, for `vm.expectEmit`
interface IERC20Events {
  event Transfer(address indexed from, address indexed to, uint256 value);
}

/// @notice ERC-XXXX conformance: the example token and policy together, and the token against faulty policies
contract ERCXXXXIntegrationTest is Helpers {
  struct Scenario {
    uint8 allowMask;
    bool paused;
    uint256 frozen;
    uint256 cap;
  }

  address internal _admin = makeAddr('admin');
  address internal _minter = makeAddr('minter');
  address internal _enforcer = makeAddr('enforcer');
  address internal _pauser = makeAddr('pauser');
  address internal _spender = makeAddr('spender');
  address[4] internal _actors = [makeAddr('a'), makeAddr('b'), makeAddr('c'), makeAddr('d')];

  ExamplePolicy internal _policy;
  ExampleToken internal _token;

  function setUp() public {
    // The policy is bound to the token, so it is deployed for the token's predicted address.
    address _predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
    _policy = new ExamplePolicy(_predicted, _admin, 10);
    _token = new ExampleToken('Example', 'EX', _admin, address(_policy));
    assertEq(address(_token), _predicted);

    vm.startPrank(_admin);
    _token.grantRole(_token.MINTER_ROLE(), _minter);
    _token.grantRole(_token.ENFORCER_ROLE(), _enforcer);
    _token.grantRole(_token.PAUSER_ROLE(), _pauser);
    for (uint256 _i; _i < _actors.length; ++_i) {
      _policy.setAllowlisted(_actors[_i], true);
    }
    vm.stopPrank();

    vm.startPrank(_minter);
    _token.mint(_actors[0], 1000);
    _token.mint(_actors[1], 1000);
    vm.stopPrank();
    assertEq(_policy.holderCount(), 2);

    for (uint256 _i; _i < _actors.length; ++_i) {
      vm.prank(_actors[_i]);
      _token.approve(_spender, type(uint256).max);
    }
  }

  function _install(
    address _newPolicy
  ) internal {
    vm.prank(_admin);
    _token.setPolicy(_newPolicy);
  }

  function _transferContext() internal view returns (IERCXXXXPolicy.TransferContext memory _context) {
    _context = IERCXXXXPolicy.TransferContext({
      token: address(_token),
      from: _actors[0],
      to: _actors[1],
      tokenId: 0,
      amount: 1,
      operator: _actors[0],
      kind: IERCXXXXPolicy.TransferKind.TRANSFER,
      data: ''
    });
  }

  /*///////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  function test_SelectorsInterfaceIdsAndTheSuccessValue() public pure {
    assertEq(TRANSFER_OK, keccak256('TRANSFER_OK'));
    assertEq(TRANSFER_OK, 0xf059ed422c5a003e2d831cdef17f0af416cf22aae18c781d82aaacaa5c77fd3f);
    assertEq(IERCXXXXPolicy.checkSend.selector, bytes4(0xec1cb5d7));
    assertEq(IERCXXXXPolicy.checkReceive.selector, bytes4(0x8b203e96));
    assertEq(IERCXXXXPolicy.checkTransfer.selector, bytes4(0x64a1a08e));
    assertEq(IERCXXXXPolicy.wantsAfterTransfer.selector, bytes4(0x38bff1a5));
    assertEq(IERCXXXXPolicy.afterTransfer.selector, bytes4(0x2595b359));
    assertEq(IERCXXXX.policy.selector, bytes4(0x0505c8c9));
    assertEq(
      IERCXXXXPolicy.checkTransfer.selector,
      bytes4(keccak256('checkTransfer((address,address,address,uint256,uint256,address,uint8,bytes))'))
    );
    assertEq(type(IERCXXXXPolicy).interfaceId, bytes4(0x1eb76933));
    assertEq(type(IERCXXXX).interfaceId, bytes4(0x0505c8c9));
    assertEq(type(IERC7943Fungible).interfaceId, bytes4(0x3edbb4c4)); // as stated in ERC-7943
  }

  /*///////////////////////////////////////////////////////////////
                            FAILING CLOSED
  //////////////////////////////////////////////////////////////*/

  /// @notice A forgotten branch returns zero. Zero is not success, so the movement is rejected and the pre-flight agrees
  function test_WhenAPolicyForgetsAKind_ItsZeroRejects() public {
    _install(address(new ForgetfulPolicy()));

    assertFalse(_token.canTransfer(address(0), _actors[2], 1));
    vm.prank(_minter);
    vm.expectRevert(abi.encodeWithSelector(IERCXXXX.ERCXXXXPolicyRejected.selector, bytes32(0)));
    _token.mint(_actors[2], 1);

    assertTrue(_token.canTransfer(_actors[0], _actors[1], 1)); // the branch the author wrote still works
  }

  function test_WhenThePolicyReverts_ThePreflightIsFalseAndTheMovementReverts() public {
    _install(address(new RevertingPolicy()));

    assertFalse(_token.canTransfer(_actors[0], _actors[1], 1));
    vm.prank(_actors[0]);
    vm.expectRevert(RevertingPolicy.RevertingPolicy_Failure.selector);
    _token.transfer(_actors[1], 1);
  }

  function test_WhenTheAnswerIsShorterThanAWord_ThePreflightIsFalseAndTheMovementReverts() public {
    _install(address(new ShortReturnPolicy()));

    assertFalse(_token.canTransfer(_actors[0], _actors[1], 1));
    vm.prank(_actors[0]);
    vm.expectRevert();
    _token.transfer(_actors[1], 1);
  }

  /// @notice A malformed `wantsAfterTransfer` answer must not be read as `false`: the callback could be skipped
  function test_WhenWantsAfterTransferIsMalformed_TheMovementReverts() public {
    _install(address(new BadBoolPolicy()));
    vm.prank(_actors[0]);
    vm.expectRevert();
    _token.transfer(_actors[1], 1);

    _install(address(new ShortBoolPolicy()));
    vm.prank(_actors[0]);
    vm.expectRevert();
    _token.transfer(_actors[1], 1);
  }

  /// @notice Why the success value is not a selector: an echo of `checkTransfer` calldata is `bytes32(selector)`,
  ///         because the first argument word of a call with one dynamic tuple is the offset 0x20
  function test_AnEchoingContractReturnsTheSelectorWord() public {
    EchoContract _echo = new EchoContract();
    bytes32 _answer = IERCXXXXPolicy(address(_echo)).checkTransfer(_transferContext());
    assertEq(_answer, bytes32(IERCXXXXPolicy.checkTransfer.selector));
    assertTrue(_answer != TRANSFER_OK);
  }

  /*///////////////////////////////////////////////////////////////
                            CALLBACK
  //////////////////////////////////////////////////////////////*/

  function test_AfterTransferCannotStartAnotherMovement() public {
    ReentrantPolicy _reentrant = new ReentrantPolicy();
    // Fund it while the example policy is installed, then install it.
    vm.prank(_admin);
    _policy.setAllowlisted(address(_reentrant), true);
    vm.prank(_minter);
    _token.mint(address(_reentrant), 10);
    _install(address(_reentrant));

    vm.prank(_actors[0]);
    vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
    _token.transfer(_actors[1], 1);
  }

  /*///////////////////////////////////////////////////////////////
                            ERC-7943 CHECKS
  //////////////////////////////////////////////////////////////*/

  function test_CanSendAndCanReceiveFollowThePolicy() public {
    assertTrue(_token.canSend(_actors[0]));
    assertTrue(_token.canReceive(_actors[0]));
    vm.prank(_admin);
    _policy.setAllowlisted(_actors[0], false);
    assertFalse(_token.canSend(_actors[0]));
    assertFalse(_token.canReceive(_actors[0]));
    // ERC-7943: canTransfer performs both checks; here they arrive through checkTransfer.
    assertFalse(_token.canTransfer(_actors[0], _actors[1], 1));
    assertFalse(_token.canTransfer(_actors[1], _actors[0], 1));
  }

  /*///////////////////////////////////////////////////////////////
                            PRE-FLIGHT PARITY
  //////////////////////////////////////////////////////////////*/

  function _scenario(
    uint8 _allowMask,
    bool _paused,
    uint256 _frozen,
    uint256 _cap
  ) internal pure returns (Scenario memory _s) {
    _s = Scenario({allowMask: _allowMask, paused: _paused, frozen: bound(_frozen, 0, 1500), cap: bound(_cap, 0, 4)});
  }

  function _apply(
    Scenario memory _s,
    address _from
  ) internal {
    vm.startPrank(_admin);
    for (uint256 _i; _i < _actors.length; ++_i) {
      _policy.setAllowlisted(_actors[_i], (_s.allowMask >> _i) & 1 == 1);
    }
    _policy.setCap(_s.cap);
    vm.stopPrank();
    if (_from != address(0)) {
      vm.prank(_enforcer);
      _token.setFrozenTokens(_from, _s.frozen);
    }
    if (_s.paused) {
      vm.prank(_pauser);
      _token.pause();
    }
  }

  function testFuzz_CanTransferPredictsTransfer(
    uint8 _allowMask,
    bool _paused,
    uint256 _frozen,
    uint256 _cap,
    uint256 _fromSeed,
    uint256 _toSeed,
    uint256 _amount
  ) public {
    address _from = _actors[bound(_fromSeed, 0, 3)];
    address _to = _actors[bound(_toSeed, 0, 3)];
    _amount = bound(_amount, 0, 1200);
    _apply(_scenario(_allowMask, _paused, _frozen, _cap), _from);

    bool _predicted = _token.canTransfer(_from, _to, _amount);
    vm.prank(_from);
    (bool _succeeded,) = address(_token).call(abi.encodeCall(_token.transfer, (_to, _amount)));
    assertEq(_succeeded, _predicted);
  }

  /// @notice The same decision when a spender submits: TRANSFER does not depend on `operator`
  function testFuzz_CanTransferPredictsTransferFrom(
    uint8 _allowMask,
    bool _paused,
    uint256 _frozen,
    uint256 _cap,
    uint256 _fromSeed,
    uint256 _toSeed,
    uint256 _amount
  ) public {
    address _from = _actors[bound(_fromSeed, 0, 3)];
    address _to = _actors[bound(_toSeed, 0, 3)];
    _amount = bound(_amount, 0, 1200);
    _apply(_scenario(_allowMask, _paused, _frozen, _cap), _from);

    bool _predicted = _token.canTransfer(_from, _to, _amount);
    vm.prank(_spender);
    (bool _succeeded,) = address(_token).call(abi.encodeCall(_token.transferFrom, (_from, _to, _amount)));
    assertEq(_succeeded, _predicted);
  }

  function testFuzz_CanTransferPredictsMint(
    uint8 _allowMask,
    bool _paused,
    uint256 _cap,
    uint256 _toSeed,
    uint256 _amount
  ) public {
    address _to = _actors[bound(_toSeed, 0, 3)];
    _amount = bound(_amount, 0, 1200);
    _apply(_scenario(_allowMask, _paused, 0, _cap), address(0));

    bool _predicted = _token.canTransfer(address(0), _to, _amount);
    vm.prank(_minter);
    (bool _succeeded,) = address(_token).call(abi.encodeCall(_token.mint, (_to, _amount)));
    assertEq(_succeeded, _predicted);
  }

  function testFuzz_CanTransferPredictsBurn(
    uint8 _allowMask,
    bool _paused,
    uint256 _frozen,
    uint256 _cap,
    uint256 _fromSeed,
    uint256 _amount
  ) public {
    address _from = _actors[bound(_fromSeed, 0, 3)];
    _amount = bound(_amount, 0, 1200);
    _apply(_scenario(_allowMask, _paused, _frozen, _cap), _from);

    bool _predicted = _token.canTransfer(_from, address(0), _amount);
    vm.prank(_from);
    (bool _succeeded,) = address(_token).call(abi.encodeCall(_token.burn, (_amount)));
    assertEq(_succeeded, _predicted);
  }

  /*///////////////////////////////////////////////////////////////
                            HOLDER CAP
  //////////////////////////////////////////////////////////////*/

  function test_AFullBalanceMoveToANewHolderPassesAtTheCap() public {
    vm.prank(_admin);
    _policy.setCap(2);
    assertFalse(_token.canTransfer(_actors[0], _actors[2], 999)); // a third holder
    assertTrue(_token.canTransfer(_actors[0], _actors[2], 1000)); // net zero: actors[0] leaves
    vm.prank(_actors[0]);
    _token.transfer(_actors[2], 1000);
    assertEq(_policy.holderCount(), 2);
  }

  function test_ALoweredCapIsARatchet() public {
    vm.prank(_admin);
    _policy.setCap(1);
    assertFalse(_token.canTransfer(_actors[0], _actors[2], 1000)); // net zero, but the count is above the cap
    assertTrue(_token.canTransfer(_actors[0], _actors[1], 1)); // existing holders still transact
    assertTrue(_token.canTransfer(_actors[0], address(0), 1000)); // and can exit
  }

  /*///////////////////////////////////////////////////////////////
                            REPLACING THE POLICY ON A LIVE TOKEN
  //////////////////////////////////////////////////////////////*/

  /// @notice A second example policy for the same token, allowlisting every actor
  function _secondPolicy() internal returns (ExamplePolicy _second) {
    _second = new ExamplePolicy(address(_token), _admin, 10);
    vm.startPrank(_admin);
    for (uint256 _i; _i < _actors.length; ++_i) {
      _second.setAllowlisted(_actors[_i], true);
    }
    vm.stopPrank();
  }

  function test_AReplacementSeededWithTheTrueCountLetsAHolderExit() public {
    ExamplePolicy _second = _secondPolicy();
    uint256 _trueCount = _policy.holderCount(); // 2: actors[0] and actors[1]; read before the prank
    vm.prank(_admin);
    _second.seedHolderCount(_trueCount);
    _install(address(_second));

    vm.prank(_actors[0]);
    _token.transfer(_actors[1], 1000); // a full exit to an existing holder
    assertEq(_second.holderCount(), 1);
  }

  /// @notice Why the seed exists: an unseeded replacement starts at zero and underflows on the first full exit
  function test_AnUnseededReplacementBlocksAFullExit() public {
    _install(address(_secondPolicy()));
    vm.prank(_actors[0]);
    vm.expectRevert(stdError.arithmeticError);
    _token.transfer(_actors[1], 1000);
  }

  /// @notice A→B→A, steps 1–3: B is installed with the true count, then two holders arrive that A never sees
  function _swapAwayAndMintTwoHolders() internal returns (ExamplePolicy _b) {
    _b = _secondPolicy();
    uint256 _trueCount = _policy.holderCount(); // 2; read before the prank
    vm.prank(_admin);
    _b.seedHolderCount(_trueCount);
    _install(address(_b));
    vm.startPrank(_minter);
    _token.mint(_actors[2], 10);
    _token.mint(_actors[3], 10);
    vm.stopPrank();
    assertEq(_b.holderCount(), 4);
  }

  /// @notice Reinstalling is a new installation: without a reseed, A's count is stale and its cap admits too many
  function test_AReinstalledPolicyWithoutAReseedAdmitsHoldersPastTheCap() public {
    _swapAwayAndMintTwoHolders();
    vm.prank(_admin);
    _policy.setCap(4);
    _install(address(_policy));
    assertEq(_policy.holderCount(), 2); // stale: A saw neither mint

    address _fifth = makeAddr('fifth');
    vm.prank(_admin);
    _policy.setAllowlisted(_fifth, true);
    vm.prank(_minter);
    _token.mint(_fifth, 10); // admitted: 2 + 1 <= 4, yet five accounts now hold the token
    assertEq(_policy.holderCount(), 3);
  }

  function test_AReinstalledPolicyReseededWithTheTrueCountEnforcesTheCap() public {
    ExamplePolicy _b = _swapAwayAndMintTwoHolders();
    uint256 _trueCount = _b.holderCount(); // 4; read before the prank
    vm.startPrank(_admin);
    _policy.setCap(4);
    _policy.seedHolderCount(_trueCount); // allowed: the token consults B, not A
    vm.stopPrank();
    _install(address(_policy));
    assertEq(_policy.holderCount(), 4);

    address _fifth = makeAddr('fifth');
    bytes32 _maxHolders = _policy.MAX_HOLDERS();
    vm.prank(_admin);
    _policy.setAllowlisted(_fifth, true);
    vm.prank(_minter);
    vm.expectRevert(abi.encodeWithSelector(IERCXXXX.ERCXXXXPolicyRejected.selector, _maxHolders));
    _token.mint(_fifth, 10);

    vm.prank(_actors[2]);
    _token.transfer(_actors[3], 10); // a full exit to an existing holder
    assertEq(_policy.holderCount(), 3);
  }

  /**
   * @notice The snapshot window: governance reads the count (2), a holder arrives before the batch runs (3 now), then
   *         a policy B with a cap of 3 is seeded and installed in one call by `_helper`
   */
  function _snapshotThenAHolderArrives()
    internal
    returns (SeedAndInstall _helper, ExamplePolicy _b, uint256 _snapshot)
  {
    _snapshot = _policy.holderCount(); // 2, read when the batch is prepared
    _helper = new SeedAndInstall();
    _b = _secondPolicy();
    bytes32 _adminRole = _token.DEFAULT_ADMIN_ROLE(); // read before the prank, which the next call would consume
    vm.startPrank(_admin);
    _b.setCap(3);
    _b.transferOwnership(address(_helper));
    _token.grantRole(_adminRole, address(_helper));
    vm.stopPrank();

    vm.prank(_actors[0]);
    _token.transfer(_actors[2], 10); // a new holder, before the batch executes
    assertEq(_policy.holderCount(), 3);
  }

  /// @notice Batching a count read off-chain closes the seed-to-install gap, not the snapshot window
  function test_WhenAHolderArrivesBeforeTheBatch_AnOffChainSeedIsStale() public {
    (SeedAndInstall _helper, ExamplePolicy _b, uint256 _snapshot) = _snapshotThenAHolderArrives();
    _helper.seedAndInstall(address(_token), address(_b), _snapshot);
    assertEq(_b.holderCount(), 2); // three accounts hold the token

    vm.prank(_minter);
    _token.mint(_actors[3], 10); // admitted: 2 + 1 <= 3, yet four accounts now hold the token
    assertEq(_b.holderCount(), 3);
  }

  /// @notice Reading the count on-chain in the installing call closes the snapshot window
  function test_WhenAHolderArrivesBeforeTheBatch_AnOnChainReadInstallsTheTrueCount() public {
    (SeedAndInstall _helper, ExamplePolicy _b,) = _snapshotThenAHolderArrives();
    _helper.seedFromAndInstall(address(_token), address(_b), address(_policy));
    assertEq(_b.holderCount(), 3);

    bytes32 _maxHolders = _b.MAX_HOLDERS();
    vm.prank(_minter);
    vm.expectRevert(abi.encodeWithSelector(IERCXXXX.ERCXXXXPolicyRejected.selector, _maxHolders));
    _token.mint(_actors[3], 10);
  }

  function test_OnceInstalled_ThePolicyCannotBeSeeded() public {
    vm.prank(_admin);
    vm.expectRevert(IExamplePolicy.ExamplePolicy_AlreadyInstalled.selector);
    _policy.seedHolderCount(5);
  }

  /*///////////////////////////////////////////////////////////////
                            ENFORCEMENT
  //////////////////////////////////////////////////////////////*/

  function test_AForcedTransferWorksWhilePausedAndAboveTheCapAndIsCounted() public {
    vm.prank(_admin);
    _policy.setCap(2);
    vm.prank(_enforcer);
    _token.setFrozenTokens(_actors[0], 1500); // more than the balance: also withholds future receipts
    vm.prank(_pauser);
    _token.pause();

    vm.expectEmit(address(_token));
    emit IERC7943Fungible.Frozen(_actors[0], 1400);
    vm.expectEmit(address(_token));
    emit IERC20Events.Transfer(_actors[0], _actors[2], 100);
    vm.expectEmit(address(_token));
    emit IERC7943Fungible.ForcedTransfer(_actors[0], _actors[2], 100);
    vm.prank(_enforcer);
    _token.forcedTransfer(_actors[0], _actors[2], 100);

    assertEq(_token.getFrozenTokens(_actors[0]), 1400);
    assertEq(_policy.holderCount(), 3); // exempt from the cap, still counted
  }

  /// @notice Only the frozen part of what moves is unfrozen: 1000 held, 950 frozen, 50 free; moving 100 unfreezes 50
  function test_AForcedTransferUnfreezesOnlyTheFrozenPart() public {
    vm.prank(_enforcer);
    _token.setFrozenTokens(_actors[0], 950);
    vm.expectEmit(address(_token));
    emit IERC7943Fungible.Frozen(_actors[0], 900);
    vm.prank(_enforcer);
    _token.forcedTransfer(_actors[0], _actors[2], 100);
    assertEq(_token.getFrozenTokens(_actors[0]), 900);
  }

  /// @notice While paused, a forced transfer goes through, but an ordinary transfer right after it, in the same call, does not
  function test_AForcedTransferDoesNotLeakItsKindToTheNextMovement() public {
    ForcedThenTransfer _helper = new ForcedThenTransfer();
    bytes32 _enforcerRole = _token.ENFORCER_ROLE(); // read before the prank, which the next call would consume
    vm.startPrank(_admin);
    _token.grantRole(_enforcerRole, address(_helper));
    _policy.setAllowlisted(address(_helper), true);
    vm.stopPrank();
    vm.prank(_minter);
    _token.mint(address(_helper), 10);
    vm.prank(_pauser);
    _token.pause();

    vm.expectRevert(Pausable.EnforcedPause.selector);
    _helper.run(address(_token), _actors[0], _actors[1], 5, _actors[1], 3);
  }

  function test_AForcedTransferStillNeedsAnEligibleReceiver() public {
    vm.prank(_admin);
    _policy.setAllowlisted(_actors[2], false);
    bytes32 _reason = _policy.RECEIVER_NOT_ELIGIBLE(); // read before the prank, which the next call would consume
    vm.prank(_enforcer);
    vm.expectRevert(abi.encodeWithSelector(IERCXXXX.ERCXXXXPolicyRejected.selector, _reason));
    _token.forcedTransfer(_actors[0], _actors[2], 100);
  }

  function test_AFrozenAmountRevertsWithTheERC7943ErrorAndAnOverdraftWithTheERC20Error() public {
    vm.prank(_enforcer);
    _token.setFrozenTokens(_actors[0], 950);
    vm.prank(_actors[0]);
    vm.expectRevert(
      abi.encodeWithSelector(IERC7943Fungible.ERC7943InsufficientUnfrozenBalance.selector, _actors[0], 51, 50)
    );
    _token.transfer(_actors[1], 51);

    vm.prank(_actors[0]);
    vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, _actors[0], 1000, 1001));
    _token.transfer(_actors[1], 1001);
  }
}
