// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibSafe} from "../../../src/lib/LibSafe.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ISafe} from "../../../src/interface/ISafe.sol";

/// The Safe v1.4.1 calls the tests make to create a Safe and to move it out of
/// a configuration, all but `setup` callable only by the Safe itself.
interface ISafeAdmin {
    function setup(
        address[] calldata owners,
        uint256 threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;
    function enableModule(address module) external;
    function setGuard(address guard) external;
    function setFallbackHandler(address handler) external;
}

/// The SafeToL2Setup entry point `setup` delegatecalls.
interface ISafeToL2Setup {
    function setupToL2(address l2Singleton) external;
}

/// `createProxyWithNonce` has this signature on both the v1.3.0 and the v1.4.1
/// factory.
interface ISafeProxyFactory {
    function createProxyWithNonce(address singleton, bytes memory initializer, uint256 saltNonce)
        external
        returns (address proxy);
    function proxyCreationCode() external pure returns (bytes memory);
}

/// A guard v1.4.1 `setGuard` accepts: it checks only ERC-165 support.
contract AcceptingGuard {
    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

/// @title LibSafeTest
/// @notice Every assertion in `LibSafe` against Safes created on a fork through
/// the canonical factories, so a passing assertion is evidence about real Safe
/// code and every failure is driven by the Safe's own mutators or by a change
/// to the account it inspects.
contract LibSafeTest is Test {
    /// The canonical v1.3.0 `GnosisSafeProxyFactory`, the factory that creates
    /// proxies with `LibSafe.SAFE_V1_3_0_PROXY_CODEHASH`.
    address constant SAFE_V1_3_0_PROXY_FACTORY = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2;

    function externalAssertCanonicalContracts() external view {
        LibSafe.assertCanonicalContracts();
    }

    function externalAssertIdentity(ISafe target) external view {
        LibSafe.assertIdentity(target);
    }

    function externalAssertNoModules(ISafe target) external view {
        LibSafe.assertNoModules(target);
    }

    function externalAssertNoGuard(ISafe target) external view {
        LibSafe.assertNoGuard(target);
    }

    function externalAssertFallbackHandler(ISafe target, address expected) external view {
        LibSafe.assertFallbackHandler(target, expected);
    }

    function externalAssertLockedDown(ISafe target) external view {
        LibSafe.assertLockedDown(target);
    }

    function externalAssertOwnersInOrder(ISafe target, address[] memory expected) external view {
        LibSafe.assertOwnersInOrder(target, expected);
    }

    function externalAssertOwnersAsSet(ISafe target, address[] memory expected) external view {
        LibSafe.assertOwnersAsSet(target, expected);
    }

    function externalAssertThreshold(ISafe target, uint256 expected) external view {
        LibSafe.assertThreshold(target, expected);
    }

    /// Three owners, in the order `setup` receives them and so the order
    /// `getOwners()` returns them.
    function owners() internal returns (address[] memory list) {
        list = new address[](3);
        list[0] = makeAddr("owner a");
        list[1] = makeAddr("owner b");
        list[2] = makeAddr("owner c");
    }

    /// The `setup` calldata the Safe UI writes: the owners at threshold 2,
    /// `setupToL2` through `SafeToL2Setup`, and the compatibility fallback
    /// handler.
    function toL2Initializer() internal returns (bytes memory) {
        return abi.encodeCall(
            ISafeAdmin.setup,
            (
                owners(),
                2,
                LibSafe.SAFE_V1_4_1_TO_L2_SETUP,
                abi.encodeCall(ISafeToL2Setup.setupToL2, (LibSafe.SAFE_V1_4_1_L2_SINGLETON)),
                LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER,
                address(0),
                0,
                payable(address(0))
            )
        );
    }

    /// A Safe created on the selected chain through the v1.4.1 factory on the
    /// L1 singleton with `setupToL2`, as the Safe UI creates one.
    function createSafe() internal returns (ISafe) {
        return ISafe(
            ISafeProxyFactory(LibSafe.SAFE_V1_4_1_PROXY_FACTORY)
                .createProxyWithNonce(LibSafe.SAFE_V1_4_1_L1_SINGLETON, toL2Initializer(), 0)
        );
    }

    /// A Safe created by `setUp` on a Base fork. Every test starts from the
    /// state `setUp` leaves, fuzz runs included, so the fork is created once.
    ISafe safe;

    function setUp() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        safe = createSafe();
    }

    /// The storage slots are the hashes `GuardManager` and `FallbackManager`
    /// name them by.
    function testStorageSlotsAreTheirPreimages() external pure {
        assertEq(LibSafe.SAFE_GUARD_STORAGE_SLOT, keccak256("guard_manager.guard.address"));
        assertEq(LibSafe.SAFE_FALLBACK_HANDLER_STORAGE_SLOT, keccak256("fallback_manager.handler.address"));
        assertEq(LibSafe.SAFE_SINGLETON_STORAGE_SLOT, bytes32(0));
        assertEq(LibSafe.SAFE_MODULES_SENTINEL, address(1));
    }

    /// Every canonical contract is on every network this repo supports with its
    /// pinned code.
    function testCanonicalContractsOnEverySupportedNetwork() external {
        string[] memory networks = LibRainDeploy.supportedNetworks();
        uint256[] memory forkIds = LibRainDeploy.createForks(vm, networks);
        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            this.externalAssertCanonicalContracts();
        }
    }

    /// Each canonical contract is checked: replacing any one's code, or
    /// removing it, fails on that contract.
    function testCanonicalContractsEachChecked(uint256 which, bool empty) external {
        address[5] memory accounts = [
            LibSafe.SAFE_V1_4_1_PROXY_FACTORY,
            LibSafe.SAFE_V1_4_1_L1_SINGLETON,
            LibSafe.SAFE_V1_4_1_L2_SINGLETON,
            LibSafe.SAFE_V1_4_1_TO_L2_SETUP,
            LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER
        ];
        bytes32[5] memory codehashes = [
            LibSafe.SAFE_V1_4_1_PROXY_FACTORY_CODEHASH,
            LibSafe.SAFE_V1_4_1_L1_SINGLETON_CODEHASH,
            LibSafe.SAFE_V1_4_1_L2_SINGLETON_CODEHASH,
            LibSafe.SAFE_V1_4_1_TO_L2_SETUP_CODEHASH,
            LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER_CODEHASH
        ];
        which = bound(which, 0, 4);
        vm.etch(accounts[which], empty ? bytes("") : bytes(hex"fe"));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeCodehashMismatch.selector, accounts[which], codehashes[which], accounts[which].codehash
            )
        );
        this.externalAssertCanonicalContracts();
    }

    /// The pinned init code hash is the factory's proxy creation code over the
    /// L1 singleton, and with it the CREATE2 derivation gives the address the
    /// factory creates.
    function testL1ProxyInitCodeHashDerivesFactoryAddress() external {
        assertEq(
            keccak256(
                abi.encodePacked(
                    ISafeProxyFactory(LibSafe.SAFE_V1_4_1_PROXY_FACTORY).proxyCreationCode(),
                    uint256(uint160(LibSafe.SAFE_V1_4_1_L1_SINGLETON))
                )
            ),
            LibSafe.SAFE_V1_4_1_L1_PROXY_INITCODE_HASH
        );
        bytes memory initializer = toL2Initializer();
        uint256 saltNonce = 7;
        address derived = vm.computeCreate2Address(
            keccak256(abi.encodePacked(keccak256(initializer), saltNonce)),
            LibSafe.SAFE_V1_4_1_L1_PROXY_INITCODE_HASH,
            LibSafe.SAFE_V1_4_1_PROXY_FACTORY
        );
        address created = ISafeProxyFactory(LibSafe.SAFE_V1_4_1_PROXY_FACTORY)
            .createProxyWithNonce(LibSafe.SAFE_V1_4_1_L1_SINGLETON, initializer, saltNonce);
        assertEq(created, derived);
    }

    /// The canonical contracts are on Base with their pinned code. Off Ethereum
    /// mainnet `setupToL2` moves the Safe to the L2 singleton, and
    /// the Safe passes every assertion in the configuration it was created in.
    function testCreatedSafePassesOnBase() external {
        this.externalAssertCanonicalContracts();
        assertEq(address(safe).codehash, LibSafe.SAFE_V1_4_1_PROXY_CODEHASH);
        assertEq(safe.masterCopy(), LibSafe.SAFE_V1_4_1_L2_SINGLETON);
        assertEq(
            LibSafe.readStorageAddress(safe, LibSafe.SAFE_SINGLETON_STORAGE_SLOT), LibSafe.SAFE_V1_4_1_L2_SINGLETON
        );
        this.externalAssertLockedDown(safe);
        this.externalAssertOwnersInOrder(safe, owners());
        this.externalAssertOwnersAsSet(safe, owners());
        this.externalAssertThreshold(safe, 2);
    }

    /// On Ethereum mainnet `setupToL2` is a no-op and the Safe stays on the L1
    /// singleton, which is equally a genuine v1.4.1 Safe.
    function testCreatedSafePassesOnEthereum() external {
        vm.createSelectFork(LibRainDeploy.ETHEREUM);
        ISafe l1 = createSafe();
        assertEq(l1.masterCopy(), LibSafe.SAFE_V1_4_1_L1_SINGLETON);
        this.externalAssertLockedDown(l1);
    }

    /// A v1.3.0 proxy on a v1.4.1 singleton is a v1.4.1 Safe, and its code is
    /// the pinned v1.3.0 proxy code.
    function testV130ProxyOnV141SingletonPasses() external {
        bytes memory initializer = abi.encodeCall(
            ISafeAdmin.setup,
            (
                owners(),
                2,
                address(0),
                "",
                LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER,
                address(0),
                0,
                payable(address(0))
            )
        );
        ISafe v130 = ISafe(
            ISafeProxyFactory(SAFE_V1_3_0_PROXY_FACTORY)
                .createProxyWithNonce(LibSafe.SAFE_V1_4_1_L2_SINGLETON, initializer, 0)
        );
        assertEq(address(v130).codehash, LibSafe.SAFE_V1_3_0_PROXY_CODEHASH);
        this.externalAssertLockedDown(v130);
    }

    /// Code at the Safe other than either proxy fails before anything is
    /// called on it, whether foreign code or none.
    function testIdentityRejectsUnknownProxyCode(bool empty) external {
        vm.etch(address(safe), empty ? bytes("") : bytes(hex"fe"));
        vm.expectRevert(
            abi.encodeWithSelector(LibSafe.SafeUnknownProxyCodehash.selector, address(safe), address(safe).codehash)
        );
        this.externalAssertIdentity(safe);
    }

    /// A proxy on any singleton but the two canonical ones fails, the older
    /// canonical v1.3.0 singleton included.
    function testIdentityRejectsUnknownSingleton(address singleton) external {
        vm.assume(singleton != LibSafe.SAFE_V1_4_1_L1_SINGLETON && singleton != LibSafe.SAFE_V1_4_1_L2_SINGLETON);
        vm.store(address(safe), LibSafe.SAFE_SINGLETON_STORAGE_SLOT, bytes32(uint256(uint160(singleton))));
        vm.expectRevert(abi.encodeWithSelector(LibSafe.SafeUnknownSingleton.selector, address(safe), singleton));
        this.externalAssertIdentity(safe);
    }

    /// Either canonical singleton address carrying other code fails, with the
    /// code hash pinned for that singleton.
    function testIdentityRejectsReplacedSingletonCode(bool l1) external {
        address singleton = l1 ? LibSafe.SAFE_V1_4_1_L1_SINGLETON : LibSafe.SAFE_V1_4_1_L2_SINGLETON;
        bytes32 expected = l1 ? LibSafe.SAFE_V1_4_1_L1_SINGLETON_CODEHASH : LibSafe.SAFE_V1_4_1_L2_SINGLETON_CODEHASH;
        vm.store(address(safe), LibSafe.SAFE_SINGLETON_STORAGE_SLOT, bytes32(uint256(uint160(singleton))));
        vm.etch(singleton, hex"fe");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeSingletonCodehashMismatch.selector, address(safe), singleton, expected, keccak256(hex"fe")
            )
        );
        this.externalAssertIdentity(safe);
    }

    /// A singleton reporting any other version fails.
    function testIdentityRejectsOtherVersion(string memory version) external {
        vm.assume(keccak256(bytes(version)) != keccak256(bytes(LibSafe.SAFE_V1_4_1_VERSION)));
        vm.mockCall(address(safe), abi.encodeCall(ISafe.VERSION, ()), abi.encode(version));
        vm.expectRevert(abi.encodeWithSelector(LibSafe.SafeVersionMismatch.selector, address(safe), version));
        this.externalAssertIdentity(safe);
    }

    /// A module enabled through the Safe fails, alone and through
    /// `assertLockedDown`.
    function testModuleRejected() external {
        address module = makeAddr("module");
        vm.prank(address(safe));
        ISafeAdmin(address(safe)).enableModule(module);
        bytes memory err = abi.encodeWithSelector(LibSafe.SafeUnexpectedModule.selector, address(safe), module);
        vm.expectRevert(err);
        this.externalAssertNoModules(safe);
        vm.expectRevert(err);
        this.externalAssertLockedDown(safe);
    }

    /// A guard set through the Safe fails, alone and through
    /// `assertLockedDown`, which also proves the slot is the one Safe writes.
    function testGuardRejected() external {
        address guard = address(new AcceptingGuard());
        vm.prank(address(safe));
        ISafeAdmin(address(safe)).setGuard(guard);
        assertEq(LibSafe.readStorageAddress(safe, LibSafe.SAFE_GUARD_STORAGE_SLOT), guard);
        bytes memory err = abi.encodeWithSelector(LibSafe.SafeUnexpectedGuard.selector, address(safe), guard);
        vm.expectRevert(err);
        this.externalAssertNoGuard(safe);
        vm.expectRevert(err);
        this.externalAssertLockedDown(safe);
    }

    /// A fallback handler set through the Safe fails against any other
    /// expectation, alone and through `assertLockedDown`, and passes against
    /// itself.
    function testFallbackHandlerChecked(address handler) external {
        vm.assume(handler != address(safe) && handler != LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER);
        vm.prank(address(safe));
        ISafeAdmin(address(safe)).setFallbackHandler(handler);
        this.externalAssertFallbackHandler(safe, handler);
        bytes memory err = abi.encodeWithSelector(
            LibSafe.SafeFallbackHandlerMismatch.selector,
            address(safe),
            LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER,
            handler
        );
        vm.expectRevert(err);
        this.externalAssertFallbackHandler(safe, LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER);
        vm.expectRevert(err);
        this.externalAssertLockedDown(safe);
    }

    /// `assertLockedDown` runs `assertIdentity`.
    function testLockedDownChecksIdentity() external {
        vm.etch(address(safe), hex"fe");
        vm.expectRevert(
            abi.encodeWithSelector(LibSafe.SafeUnknownProxyCodehash.selector, address(safe), keccak256(hex"fe"))
        );
        this.externalAssertLockedDown(safe);
    }

    /// A different owner count fails both owner assertions.
    function testOwnerCountMismatch() external {
        address[] memory expected = new address[](2);
        expected[0] = owners()[0];
        expected[1] = owners()[1];
        bytes memory err = abi.encodeWithSelector(LibSafe.SafeOwnerCountMismatch.selector, address(safe), 2, 3);
        vm.expectRevert(err);
        this.externalAssertOwnersInOrder(safe, expected);
        vm.expectRevert(err);
        this.externalAssertOwnersAsSet(safe, expected);
    }

    /// The same owners in another order pass as a set and fail in order, at
    /// the first position that differs.
    function testOwnersReordered() external {
        address[] memory expected = owners();
        (expected[1], expected[2]) = (expected[2], expected[1]);
        this.externalAssertOwnersAsSet(safe, expected);
        vm.expectRevert(
            abi.encodeWithSelector(LibSafe.SafeOwnerMismatch.selector, address(safe), 1, expected[1], expected[2])
        );
        this.externalAssertOwnersInOrder(safe, expected);
    }

    /// An owner replaced at any position fails both: in order at that
    /// position, as a set on the owner no longer expected.
    function testOwnerReplaced(uint256 index, address impostor) external {
        address[] memory actual = owners();
        vm.assume(impostor != actual[0] && impostor != actual[1] && impostor != actual[2]);
        index = bound(index, 0, 2);
        address[] memory expected = owners();
        expected[index] = impostor;
        vm.expectRevert(
            abi.encodeWithSelector(LibSafe.SafeOwnerMismatch.selector, address(safe), index, impostor, actual[index])
        );
        this.externalAssertOwnersInOrder(safe, expected);
        vm.expectRevert(abi.encodeWithSelector(LibSafe.SafeUnexpectedOwner.selector, address(safe), actual[index]));
        this.externalAssertOwnersAsSet(safe, expected);
    }

    /// A duplicate in the expected owners does not stand in for the owner it
    /// displaces.
    function testOwnersAsSetRejectsDuplicateExpected() external {
        address[] memory actual = owners();
        address[] memory expected = owners();
        expected[2] = expected[0];
        vm.expectRevert(abi.encodeWithSelector(LibSafe.SafeUnexpectedOwner.selector, address(safe), actual[2]));
        this.externalAssertOwnersAsSet(safe, expected);
    }

    /// Any threshold but the Safe's fails.
    function testThresholdMismatch(uint256 expected) external {
        vm.assume(expected != 2);
        vm.expectRevert(abi.encodeWithSelector(LibSafe.SafeThresholdMismatch.selector, address(safe), expected, 2));
        this.externalAssertThreshold(safe, expected);
    }
}
