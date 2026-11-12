// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {IRegistryDelegatesV3} from "../../../src/interface/IRegistryDelegatesV3.sol";
import {IMigrationRegistryV5, MIGRATION_HEAD_GENESIS} from "../../../src/interface/IMigrationRegistryV5.sol";
import {ConfigRegistry} from "../../../src/concrete/ConfigRegistry.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibRegistryDelegates} from "../../../src/lib/LibRegistryDelegates.sol";

/// @title LibRegistryDelegatesApprovedTest
/// `approved` on both registries: what `checkWrite` lets through, and each
/// registry's own key refusals, the account itself included.
contract LibRegistryDelegatesApprovedTest is Test {
    address internal constant ACCOUNT = address(0x1111);
    address internal constant DELEGATE = address(0x2222);
    address internal constant OTHER = address(0x3333);
    bytes32 internal constant SCOPE = keccak256("scope");
    bytes32 internal constant OTHER_SCOPE = keccak256("other");

    function registries() internal returns (IRegistryDelegatesV3[] memory) {
        IRegistryDelegatesV3[] memory both = new IRegistryDelegatesV3[](2);
        both[0] = IRegistryDelegatesV3(address(new ConfigRegistry()));
        both[1] = IRegistryDelegatesV3(address(new MigrationRegistry()));
        return both;
    }

    function externalApproved(IRegistryDelegatesV3 registry, address account, bytes32 scope, address delegate)
        external
        view
        returns (bool)
    {
        return LibRegistryDelegates.approved(registry, account, scope, delegate);
    }

    function approve(IRegistryDelegatesV3 registry, address account, bytes32 scope, address delegate) internal {
        vm.prank(account);
        registry.approveV5(scope, delegate);
    }

    function approveUnscoped(IRegistryDelegatesV3 registry, address account, address delegate) internal {
        vm.prank(account);
        registry.approveUnscopedV5(delegate);
    }

    /// Whether `caller`'s write under `account` in `scope` lands; any refusal
    /// must be `NotApproved`.
    function writes(IRegistryDelegatesV3 registry, bool isConfig, address caller, address account, bytes32 scope)
        internal
        returns (bool)
    {
        bytes memory data = isConfig
            ? abi.encodeCall(ConfigRegistry.registerV5, (account, scope, "address", abi.encode(caller), ""))
            : abi.encodeCall(
                IMigrationRegistryV5.applyMigrationV5,
                (account, scope, keccak256("m"), LibMigrationRegistry.onto(account, scope, MIGRATION_HEAD_GENESIS), "")
            );
        vm.prank(caller);
        (bool success, bytes memory returnData) = address(registry).call(data);
        if (!success) {
            assertEq(
                returnData, abi.encodeWithSelector(IRegistryDelegatesV3.NotApproved.selector, account, scope, caller)
            );
        }
        return success;
    }

    /// The account itself is approved with no approval stored.
    function testAccountItselfIsApproved(address account, bytes32 scope) external {
        vm.assume(account != address(0) && scope != bytes32(0));
        IRegistryDelegatesV3[] memory both = registries();
        for (uint256 i = 0; i < both.length; i++) {
            assertTrue(LibRegistryDelegates.approved(both[i], account, scope, account));
        }
    }

    /// A delegate approved for the scope only is approved.
    function testScopedOnlyIsApproved() external {
        IRegistryDelegatesV3[] memory both = registries();
        for (uint256 i = 0; i < both.length; i++) {
            approve(both[i], ACCOUNT, SCOPE, DELEGATE);
            assertFalse(both[i].approvedUnscopedV5(ACCOUNT, DELEGATE));
            assertTrue(LibRegistryDelegates.approved(both[i], ACCOUNT, SCOPE, DELEGATE));
        }
    }

    /// A delegate approved unscoped only is approved in any scope.
    function testUnscopedOnlyIsApproved(bytes32 scope) external {
        vm.assume(scope != bytes32(0));
        IRegistryDelegatesV3[] memory both = registries();
        for (uint256 i = 0; i < both.length; i++) {
            approveUnscoped(both[i], ACCOUNT, DELEGATE);
            assertFalse(both[i].approvedV5(ACCOUNT, scope, DELEGATE));
            assertTrue(LibRegistryDelegates.approved(both[i], ACCOUNT, scope, DELEGATE));
        }
    }

    /// A delegate approved both scoped and unscoped is approved.
    function testScopedAndUnscopedIsApproved() external {
        IRegistryDelegatesV3[] memory both = registries();
        for (uint256 i = 0; i < both.length; i++) {
            approve(both[i], ACCOUNT, SCOPE, DELEGATE);
            approveUnscoped(both[i], ACCOUNT, DELEGATE);
            assertTrue(LibRegistryDelegates.approved(both[i], ACCOUNT, SCOPE, DELEGATE));
        }
    }

    /// Another account with no approval is not approved.
    function testNeitherIsNotApproved(address account, bytes32 scope, address delegate) external {
        vm.assume(account != address(0) && scope != bytes32(0) && delegate != address(0) && delegate != account);
        IRegistryDelegatesV3[] memory both = registries();
        for (uint256 i = 0; i < both.length; i++) {
            assertFalse(LibRegistryDelegates.approved(both[i], account, scope, delegate));
        }
    }

    /// An approval for another scope does not approve this one.
    function testOtherScopeApprovalIsNotApproved() external {
        IRegistryDelegatesV3[] memory both = registries();
        for (uint256 i = 0; i < both.length; i++) {
            approve(both[i], ACCOUNT, OTHER_SCOPE, DELEGATE);
            assertTrue(LibRegistryDelegates.approved(both[i], ACCOUNT, OTHER_SCOPE, DELEGATE));
            assertFalse(LibRegistryDelegates.approved(both[i], ACCOUNT, SCOPE, DELEGATE));
        }
    }

    /// Another account's scoped and unscoped approvals do not approve under
    /// this one.
    function testOtherAccountApprovalIsNotApproved() external {
        IRegistryDelegatesV3[] memory both = registries();
        for (uint256 i = 0; i < both.length; i++) {
            approve(both[i], OTHER, SCOPE, DELEGATE);
            approveUnscoped(both[i], OTHER, DELEGATE);
            assertTrue(LibRegistryDelegates.approved(both[i], OTHER, SCOPE, DELEGATE));
            assertFalse(LibRegistryDelegates.approved(both[i], ACCOUNT, SCOPE, DELEGATE));
        }
    }

    /// Revoking each approval ends it, and the other stands until it is
    /// revoked too.
    function testRevokedIsNotApproved() external {
        IRegistryDelegatesV3[] memory both = registries();
        for (uint256 i = 0; i < both.length; i++) {
            approve(both[i], ACCOUNT, SCOPE, DELEGATE);
            vm.prank(ACCOUNT);
            both[i].revokeV5(SCOPE, DELEGATE);
            assertFalse(LibRegistryDelegates.approved(both[i], ACCOUNT, SCOPE, DELEGATE));

            approve(both[i], ACCOUNT, SCOPE, DELEGATE);
            approveUnscoped(both[i], ACCOUNT, DELEGATE);
            vm.prank(ACCOUNT);
            both[i].revokeUnscopedV5(DELEGATE);
            assertTrue(LibRegistryDelegates.approved(both[i], ACCOUNT, SCOPE, DELEGATE));
            vm.prank(ACCOUNT);
            both[i].revokeV5(SCOPE, DELEGATE);
            assertFalse(LibRegistryDelegates.approved(both[i], ACCOUNT, SCOPE, DELEGATE));
        }
    }

    /// `approved` is true exactly when the registry's own write lets the
    /// delegate through.
    function testApprovedIsWhatCheckWriteLetsThrough(bool isSelf, bool scoped, bool unscoped, bool otherScope)
        external
    {
        address delegate = isSelf ? ACCOUNT : DELEGATE;
        bytes32 approvedScope = otherScope ? OTHER_SCOPE : SCOPE;
        IRegistryDelegatesV3[] memory both = registries();
        for (uint256 i = 0; i < both.length; i++) {
            if (scoped) {
                approve(both[i], ACCOUNT, approvedScope, delegate);
            }
            if (unscoped) {
                approveUnscoped(both[i], ACCOUNT, delegate);
            }
            bool answer = LibRegistryDelegates.approved(both[i], ACCOUNT, SCOPE, delegate);
            assertEq(answer, isSelf || (scoped && !otherScope) || unscoped);
            assertEq(writes(both[i], i == 0, delegate, ACCOUNT, SCOPE), answer);
        }
    }

    /// The zero delegate is refused by both registries with their own
    /// `ZeroDelegate`, the zero account asking about itself included.
    function testZeroDelegateIsRefused(address account, bytes32 scope) external {
        vm.assume(account != address(0) && scope != bytes32(0));
        IRegistryDelegatesV3[] memory both = registries();
        for (uint256 i = 0; i < both.length; i++) {
            vm.expectRevert(IRegistryDelegatesV3.ZeroDelegate.selector);
            this.externalApproved(both[i], account, scope, address(0));
        }
        vm.expectRevert(IRegistryDelegatesV3.ZeroDelegate.selector);
        this.externalApproved(both[0], address(0), scope, address(0));
    }

    /// The migration registry refuses the zero writer and the zero namespace
    /// with its own errors, the writer asking about itself included.
    function testMigrationZeroKeysAreRefused(address writer, bytes32 namespace, address delegate) external {
        vm.assume(writer != address(0) && namespace != bytes32(0) && delegate != address(0));
        IRegistryDelegatesV3 registry = IRegistryDelegatesV3(address(new MigrationRegistry()));

        vm.expectRevert(IMigrationRegistryV5.ZeroWriter.selector);
        this.externalApproved(registry, address(0), namespace, delegate);
        vm.expectRevert(IMigrationRegistryV5.ZeroWriter.selector);
        this.externalApproved(registry, address(0), namespace, address(0));
        vm.expectRevert(IMigrationRegistryV5.ZeroNamespace.selector);
        this.externalApproved(registry, writer, bytes32(0), delegate);
        vm.expectRevert(IMigrationRegistryV5.ZeroNamespace.selector);
        this.externalApproved(registry, writer, bytes32(0), writer);
    }

    /// The config registry keys every account: the zero account approved
    /// nobody, and the zero scope is answered like any other.
    function testConfigZeroAccountAndScopeAreAnswered(address delegate) external {
        vm.assume(delegate != address(0) && delegate != ACCOUNT);
        IRegistryDelegatesV3 registry = IRegistryDelegatesV3(address(new ConfigRegistry()));
        assertFalse(LibRegistryDelegates.approved(registry, address(0), SCOPE, delegate));
        assertFalse(LibRegistryDelegates.approved(registry, ACCOUNT, bytes32(0), delegate));
        assertTrue(LibRegistryDelegates.approved(registry, ACCOUNT, bytes32(0), ACCOUNT));
        approve(registry, ACCOUNT, bytes32(0), delegate);
        assertTrue(LibRegistryDelegates.approved(registry, ACCOUNT, bytes32(0), delegate));
    }
}
