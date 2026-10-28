// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Multicall} from "@openzeppelin-contracts-5.7.0/utils/Multicall.sol";

import {IRegistryDelegatesV2} from "../../../src/interface/IRegistryDelegatesV2.sol";
import {IConfigRegistryV4} from "../../../src/interface/IConfigRegistryV4.sol";
import {IMigrationRegistryV4, MIGRATION_HEAD_GENESIS} from "../../../src/interface/IMigrationRegistryV4.sol";
import {ConfigRegistry} from "../../../src/concrete/ConfigRegistry.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";

/// @title RegistryDelegatesMulticallTest
/// Both registries' `multicall`: every call in a batch runs as the account that
/// sent it, a batch is all or nothing, and a delegate batching gains nothing it
/// could not do call by call.
contract RegistryDelegatesMulticallTest is Test {
    address internal constant ACCOUNT = address(0x1111);
    address internal constant DELEGATE = address(0x2222);
    bytes32 internal constant FIRST = keccak256("a.b");
    bytes32 internal constant SECOND = keccak256("c.d");

    function approvals(bytes32 first, bytes32 second, address delegate) internal pure returns (bytes[] memory) {
        bytes[] memory batch = new bytes[](2);
        batch[0] = abi.encodeCall(IRegistryDelegatesV2.approveV4, (first, delegate));
        batch[1] = abi.encodeCall(IRegistryDelegatesV2.approveV4, (second, delegate));
        return batch;
    }

    function registries() internal returns (address[] memory) {
        address[] memory both = new address[](2);
        both[0] = address(new ConfigRegistry());
        both[1] = address(new MigrationRegistry());
        return both;
    }

    /// An account's batch approves every scope under the account, each
    /// emitted by the registry with the account as sender.
    function testBatchApprovesUnderTheSender() external {
        address[] memory both = registries();
        for (uint256 i = 0; i < both.length; i++) {
            vm.expectEmit(both[i]);
            emit IRegistryDelegatesV2.Approved(ACCOUNT, FIRST, DELEGATE);
            vm.expectEmit(both[i]);
            emit IRegistryDelegatesV2.Approved(ACCOUNT, SECOND, DELEGATE);
            vm.prank(ACCOUNT);
            Multicall(both[i]).multicall(approvals(FIRST, SECOND, DELEGATE));
            assertTrue(IRegistryDelegatesV2(both[i]).approvedV4(ACCOUNT, FIRST, DELEGATE));
            assertTrue(IRegistryDelegatesV2(both[i]).approvedV4(ACCOUNT, SECOND, DELEGATE));
            assertFalse(IRegistryDelegatesV2(both[i]).approvedV4(address(this), FIRST, DELEGATE));
        }
    }

    /// One refused call reverts the whole batch with its own error, and the
    /// calls before it are not kept.
    function testBatchIsAllOrNothing() external {
        address[] memory both = registries();
        for (uint256 i = 0; i < both.length; i++) {
            bytes[] memory batch = approvals(FIRST, SECOND, DELEGATE);
            batch[1] = abi.encodeCall(IRegistryDelegatesV2.approveV4, (SECOND, address(0)));
            vm.prank(ACCOUNT);
            vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV2.ZeroDelegate.selector));
            Multicall(both[i]).multicall(batch);
            assertFalse(IRegistryDelegatesV2(both[i]).approvedV4(ACCOUNT, FIRST, DELEGATE));
        }
    }

    /// A delegate's batch of approvals approves under the delegate, never under
    /// the account that approved it.
    function testDelegateBatchCannotApproveForItsAccount() external {
        address[] memory both = registries();
        address other = address(0x3333);
        for (uint256 i = 0; i < both.length; i++) {
            vm.prank(ACCOUNT);
            IRegistryDelegatesV2(both[i]).approveV4(FIRST, DELEGATE);
            vm.prank(DELEGATE);
            Multicall(both[i]).multicall(approvals(FIRST, SECOND, other));
            assertFalse(IRegistryDelegatesV2(both[i]).approvedV4(ACCOUNT, FIRST, other));
            assertFalse(IRegistryDelegatesV2(both[i]).approvedV4(ACCOUNT, SECOND, other));
            assertTrue(IRegistryDelegatesV2(both[i]).approvedV4(DELEGATE, FIRST, other));
        }
    }

    /// An authority binds a name and approves a delegate in one transaction.
    function testConfigBatchBindsAndApproves() external {
        ConfigRegistry registry = new ConfigRegistry();
        bytes[] memory batch = new bytes[](2);
        batch[0] = abi.encodeCall(IConfigRegistryV4.registerV4, (ACCOUNT, FIRST, "address", abi.encode(DELEGATE), ""));
        batch[1] = abi.encodeCall(IRegistryDelegatesV2.approveV4, (SECOND, DELEGATE));
        vm.prank(ACCOUNT);
        registry.multicall(batch);
        (bytes memory value,,) = registry.getV4(ACCOUNT, FIRST);
        assertEq(value, abi.encode(DELEGATE));
        assertTrue(registry.approvedV4(ACCOUNT, SECOND, DELEGATE));
    }

    /// A delegate's batch of writes is refused at the first scope it is not
    /// approved for, and keeps none of the batch.
    function testDelegateBatchIsRefusedOutsideItsApproval() external {
        MigrationRegistry registry = new MigrationRegistry();
        vm.prank(ACCOUNT);
        registry.approveV4(FIRST, DELEGATE);
        bytes[] memory batch = new bytes[](2);
        batch[0] = abi.encodeCall(
            IMigrationRegistryV4.applyMigrationV4,
            (ACCOUNT, FIRST, keccak256("m"), LibMigrationRegistry.onto(ACCOUNT, FIRST, MIGRATION_HEAD_GENESIS), "")
        );
        batch[1] = abi.encodeCall(
            IMigrationRegistryV4.applyMigrationV4,
            (ACCOUNT, SECOND, keccak256("m"), LibMigrationRegistry.onto(ACCOUNT, SECOND, MIGRATION_HEAD_GENESIS), "")
        );
        vm.prank(DELEGATE);
        vm.expectRevert(abi.encodeWithSelector(IRegistryDelegatesV2.NotApproved.selector, ACCOUNT, SECOND, DELEGATE));
        registry.multicall(batch);
        assertEq(registry.headV4(ACCOUNT, FIRST), MIGRATION_HEAD_GENESIS);
    }
}
