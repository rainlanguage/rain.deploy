// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {IRegistryDelegatesV3} from "../../../src/interface/IRegistryDelegatesV3.sol";
import {IMigrationRegistryV5, MIGRATION_HEAD_GENESIS} from "../../../src/interface/IMigrationRegistryV5.sol";
import {ConfigRegistry} from "../../../src/concrete/ConfigRegistry.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";

/// @title RegistryDelegatesUnscopedTest
/// Both registries' unscoped delegation: it lets the delegate write
/// under the approving account in any scope, under no other account, without
/// chaining, and independently of scoped approvals.
contract RegistryDelegatesUnscopedTest is Test {
    address internal constant ACCOUNT = address(0x1111);
    address internal constant DELEGATE = address(0x2222);
    address internal constant OTHER = address(0x3333);

    function registries() internal returns (address[] memory) {
        address[] memory both = new address[](2);
        both[0] = address(new ConfigRegistry());
        both[1] = address(new MigrationRegistry());
        return both;
    }

    /// A config write by `caller` under `authority` in `name`.
    function register(ConfigRegistry registry, address caller, address authority, bytes32 name) internal {
        vm.prank(caller);
        registry.registerV5(authority, name, "address", abi.encode(caller), "");
    }

    /// A migration write by `caller` in `writer`'s line in `namespace`, onto
    /// genesis.
    function applyAsCaller(MigrationRegistry registry, address caller, address writer, bytes32 namespace) internal {
        vm.prank(caller);
        registry.applyMigrationV5(
            writer, namespace, keccak256("m"), LibMigrationRegistry.onto(writer, namespace, MIGRATION_HEAD_GENESIS), ""
        );
    }

    /// Approving is the caller's, emitted, and read back; it sets no scoped
    /// approval.
    function testApproveUnscopedIsTheCallers(bytes32 scope) external {
        vm.assume(scope != bytes32(0));
        address[] memory both = registries();
        for (uint256 i = 0; i < both.length; i++) {
            IRegistryDelegatesV3 registry = IRegistryDelegatesV3(both[i]);
            vm.expectEmit(both[i]);
            emit IRegistryDelegatesV3.ApprovedUnscoped(ACCOUNT, DELEGATE);
            vm.prank(ACCOUNT);
            registry.approveUnscopedV5(DELEGATE);
            assertTrue(registry.approvedUnscopedV5(ACCOUNT, DELEGATE));
            assertFalse(registry.approvedUnscopedV5(OTHER, DELEGATE));
            assertFalse(registry.approvedUnscopedV5(ACCOUNT, OTHER));
            assertFalse(IRegistryDelegatesV3(both[i]).approvedV5(ACCOUNT, scope, DELEGATE));
        }
    }

    /// An unscoped delegate binds any name under its authority, and nothing
    /// under another authority.
    function testConfigDelegateWritesEveryName(bytes32 first, bytes32 second) external {
        vm.assume(first != second);
        ConfigRegistry registry = new ConfigRegistry();
        vm.prank(ACCOUNT);
        registry.approveUnscopedV5(DELEGATE);
        register(registry, DELEGATE, ACCOUNT, first);
        register(registry, DELEGATE, ACCOUNT, second);
        (bytes memory value,,) = registry.getV5(ACCOUNT, second);
        assertEq(value, abi.encode(DELEGATE));
        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV3.NotApproved.selector, OTHER, first, DELEGATE));
        register(registry, DELEGATE, OTHER, first);
    }

    /// An unscoped delegate writes any namespace of its writer's lines, and
    /// no other writer's.
    function testMigrationDelegateWritesEveryNamespace() external {
        MigrationRegistry registry = new MigrationRegistry();
        vm.prank(ACCOUNT);
        registry.approveUnscopedV5(DELEGATE);
        applyAsCaller(registry, DELEGATE, ACCOUNT, keccak256("a"));
        applyAsCaller(registry, DELEGATE, ACCOUNT, keccak256("b"));
        assertEq(registry.headV5(ACCOUNT, keccak256("b")), keccak256("m"));
        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV3.NotApproved.selector, OTHER, keccak256("a"), DELEGATE)
        );
        applyAsCaller(registry, DELEGATE, OTHER, keccak256("a"));
    }

    /// Revoking ends the delegate's writes in every scope it held only through
    /// the unscoped approval, and leaves a scoped approval standing.
    function testRevokeUnscopedLeavesScopedApprovals() external {
        ConfigRegistry registry = new ConfigRegistry();
        bytes32 kept = keccak256("kept");
        bytes32 lost = keccak256("lost");
        vm.startPrank(ACCOUNT);
        registry.approveUnscopedV5(DELEGATE);
        registry.approveV5(kept, DELEGATE);
        vm.expectEmit(address(registry));
        emit IRegistryDelegatesV3.RevokedUnscoped(ACCOUNT, DELEGATE);
        registry.revokeUnscopedV5(DELEGATE);
        vm.stopPrank();
        assertFalse(registry.approvedUnscopedV5(ACCOUNT, DELEGATE));
        assertTrue(registry.approvedV5(ACCOUNT, kept, DELEGATE));
        register(registry, DELEGATE, ACCOUNT, kept);
        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV3.NotApproved.selector, ACCOUNT, lost, DELEGATE));
        register(registry, DELEGATE, ACCOUNT, lost);
    }

    /// An unscoped delegate's own approvals are under itself: they let nobody
    /// write under the account that approved it.
    function testUnscopedApprovalDoesNotChain() external {
        ConfigRegistry registry = new ConfigRegistry();
        bytes32 name = keccak256("a.b");
        vm.prank(ACCOUNT);
        registry.approveUnscopedV5(DELEGATE);
        vm.startPrank(DELEGATE);
        registry.approveUnscopedV5(OTHER);
        registry.approveV5(name, OTHER);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV3.NotApproved.selector, ACCOUNT, name, OTHER));
        register(registry, OTHER, ACCOUNT, name);
    }

    /// The zero delegate is refused by approve, revoke and the read, and the
    /// migration registry refuses the zero writer in the read first.
    function testZeroKeysAreRefused() external {
        address[] memory both = registries();
        for (uint256 i = 0; i < both.length; i++) {
            IRegistryDelegatesV3 registry = IRegistryDelegatesV3(both[i]);
            vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV3.ZeroDelegate.selector));
            registry.approveUnscopedV5(address(0));
            vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV3.ZeroDelegate.selector));
            registry.revokeUnscopedV5(address(0));
            vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV3.ZeroDelegate.selector));
            registry.approvedUnscopedV5(ACCOUNT, address(0));
        }
        assertFalse(IRegistryDelegatesV3(both[0]).approvedUnscopedV5(address(0), DELEGATE));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV5.ZeroWriter.selector));
        IRegistryDelegatesV3(both[1]).approvedUnscopedV5(address(0), address(0));
    }
}
