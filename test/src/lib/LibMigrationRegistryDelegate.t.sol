// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {IMigrationRegistryV5, MIGRATION_HEAD_GENESIS} from "../../../src/interface/IMigrationRegistryV5.sol";
import {IRegistryDelegatesV3} from "../../../src/interface/IRegistryDelegatesV3.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {MockMigrationApplier} from "../../concrete/MockMigrationApplier.sol";
import {LibAccountCode} from "../../lib/LibAccountCode.sol";

/// @title LibMigrationRegistryDelegateTest
/// @notice The delegation builders and read: each targets the pinned
/// registry, encodes exactly the call it names, lands as that call when sent,
/// and refuses a chain without the registry by its code hash.
contract LibMigrationRegistryDelegateTest is Test {
    address internal constant WRITER = address(0x1111);
    address internal constant DELEGATE = address(0x2222);
    bytes32 internal constant NAMESPACE = keccak256("namespace");
    bytes32 internal constant MIGRATION = keccak256("migration");
    bytes32 internal constant SECOND = keccak256("second");

    function deployRegistry() internal {
        LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
    }

    function send(address sender, address to, bytes memory data) internal {
        vm.prank(sender);
        (bool success,) = to.call(data);
        assertTrue(success);
    }

    function expectCodeHash(bytes32 actualCodeHash) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                actualCodeHash
            )
        );
    }

    function expectDelegationWrappersRefuse(bytes32 actualCodeHash) internal {
        expectCodeHash(actualCodeHash);
        this.externalApproveCall();
        expectCodeHash(actualCodeHash);
        this.externalRevokeCall();
        expectCodeHash(actualCodeHash);
        this.externalApproved();
        expectCodeHash(actualCodeHash);
        this.externalAppliedBy();
    }

    function externalApproveCall() external view returns (address, bytes memory) {
        return LibMigrationRegistry.approveV4Call(NAMESPACE, DELEGATE);
    }

    function externalRevokeCall() external view returns (address, bytes memory) {
        return LibMigrationRegistry.revokeV4Call(NAMESPACE, DELEGATE);
    }

    function externalApproved() external view returns (bool) {
        return LibMigrationRegistry.approvedV5(WRITER, NAMESPACE, DELEGATE);
    }

    function externalAppliedBy() external view returns (address) {
        return LibMigrationRegistry.appliedByV5(WRITER, NAMESPACE, MIGRATION);
    }

    /// Approve then revoke, built and sent by the writer, are what `approvedV5`
    /// answers.
    function testApproveAndRevokeCallsLand() external {
        deployRegistry();
        (address to, bytes memory data) = LibMigrationRegistry.approveV4Call(NAMESPACE, DELEGATE);
        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(data, abi.encodeCall(IRegistryDelegatesV3.approveV5, (NAMESPACE, DELEGATE)));
        send(WRITER, to, data);
        assertTrue(LibMigrationRegistry.approvedV5(WRITER, NAMESPACE, DELEGATE));

        (to, data) = LibMigrationRegistry.revokeV4Call(NAMESPACE, DELEGATE);
        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(data, abi.encodeCall(IRegistryDelegatesV3.revokeV5, (NAMESPACE, DELEGATE)));
        send(WRITER, to, data);
        assertFalse(LibMigrationRegistry.approvedV5(WRITER, NAMESPACE, DELEGATE));
    }

    /// A delegated write, built and sent by an approved delegate, lands in the
    /// writer's line.
    function testApplyMigrationCallDelegatedLands() external {
        deployRegistry();
        (address to, bytes memory data) = LibMigrationRegistry.approveV4Call(NAMESPACE, DELEGATE);
        send(WRITER, to, data);
        (to, data) = LibMigrationRegistry.applyMigrationV4Call(
            WRITER, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS), ""
        );
        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(
            data,
            abi.encodeCall(
                IMigrationRegistryV5.applyMigrationV5,
                (WRITER, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS), "")
            )
        );
        send(DELEGATE, to, data);
        assertEq(LibMigrationRegistry.appliedV5(WRITER, NAMESPACE, MIGRATION), block.timestamp);
    }

    /// A delegated history write carries its moment into the writer's line.
    function testApplyMigrationHistoryCallDelegatedLands(uint256 appliedAt) external {
        vm.warp(1_000_000);
        appliedAt = bound(appliedAt, 1, block.timestamp);
        deployRegistry();
        (address to, bytes memory data) = LibMigrationRegistry.approveV4Call(NAMESPACE, DELEGATE);
        send(WRITER, to, data);
        (to, data) = LibMigrationRegistry.applyMigrationHistoryV4Call(
            WRITER,
            NAMESPACE,
            MIGRATION,
            appliedAt,
            LibMigrationRegistry.onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS),
            ""
        );
        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(
            data,
            abi.encodeCall(
                IMigrationRegistryV5.applyMigrationHistoryV5,
                (
                    WRITER,
                    NAMESPACE,
                    MIGRATION,
                    appliedAt,
                    LibMigrationRegistry.onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS),
                    ""
                )
            )
        );
        send(DELEGATE, to, data);
        assertEq(LibMigrationRegistry.appliedV5(WRITER, NAMESPACE, MIGRATION), appliedAt);
    }

    /// The direct writes, made from a contract the writer approved, land in
    /// the writer's line and not the contract's.
    function testDirectWritesLandUnderTheNamedWriter() external {
        vm.warp(1_000_000);
        deployRegistry();
        vm.prank(WRITER);
        LibMigrationRegistry.approveV5(NAMESPACE, address(this));

        LibMigrationRegistry.applyMigrationV5(
            WRITER, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS), ""
        );
        assertEq(LibMigrationRegistry.appliedV5(WRITER, NAMESPACE, MIGRATION), block.timestamp);

        LibMigrationRegistry.applyMigrationHistoryV5(
            WRITER, NAMESPACE, SECOND, block.timestamp, LibMigrationRegistry.onto(WRITER, NAMESPACE, MIGRATION), ""
        );
        assertEq(LibMigrationRegistry.appliedV5(WRITER, NAMESPACE, SECOND), block.timestamp);
        assertEq(LibMigrationRegistry.headV5(WRITER, NAMESPACE), SECOND);
        assertEq(LibMigrationRegistry.headV5(address(this), NAMESPACE), MIGRATION_HEAD_GENESIS);
    }

    /// The approval builders and the read refuse a chain with no registry.
    function testNoRegistryIsRefused() external {
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);
        expectCodeHash(bytes32(0));
        this.externalApproveCall();
        expectCodeHash(bytes32(0));
        this.externalRevokeCall();
        expectCodeHash(bytes32(0));
        this.externalApproved();
    }

    /// The direct approve and revoke, made from a contract, approve and revoke
    /// for that contract's line.
    function testDirectApproveAndRevokeLand() external {
        deployRegistry();
        MockMigrationApplier applier = new MockMigrationApplier();
        applier.approveV5(NAMESPACE, DELEGATE);
        assertTrue(LibMigrationRegistry.approvedV5(address(applier), NAMESPACE, DELEGATE));
        assertFalse(LibMigrationRegistry.approvedV5(address(this), NAMESPACE, DELEGATE));
        applier.revokeV5(NAMESPACE, DELEGATE);
        assertFalse(LibMigrationRegistry.approvedV5(address(applier), NAMESPACE, DELEGATE));
    }

    /// The direct approve and revoke refuse an address with no registry.
    function testDirectApproveAndRevokeNoRegistryIsRefused() external {
        MockMigrationApplier applier = new MockMigrationApplier();
        expectCodeHash(bytes32(0));
        applier.approveV5(NAMESPACE, DELEGATE);
        expectCodeHash(bytes32(0));
        applier.revokeV5(NAMESPACE, DELEGATE);
    }

    /// The direct approve and revoke refuse other code at the registry
    /// address, naming its hash.
    function testDirectApproveAndRevokeWrongCodeIsRefused(bytes memory code) external {
        vm.assume(code.length > 0 && code[0] != 0xef);
        vm.assume(keccak256(code) != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH);
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, code);
        MockMigrationApplier applier = new MockMigrationApplier();
        expectCodeHash(keccak256(code));
        applier.approveV5(NAMESPACE, DELEGATE);
        expectCodeHash(keccak256(code));
        applier.revokeV5(NAMESPACE, DELEGATE);
    }

    /// `appliedByV5` reads the account that wrote the record.
    function testAppliedByReadsTheDelegate() external {
        deployRegistry();
        (address to, bytes memory data) = LibMigrationRegistry.approveV4Call(NAMESPACE, DELEGATE);
        send(WRITER, to, data);
        (to, data) = LibMigrationRegistry.applyMigrationV4Call(
            WRITER, NAMESPACE, MIGRATION, LibMigrationRegistry.onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS), ""
        );
        send(DELEGATE, to, data);
        assertEq(LibMigrationRegistry.appliedByV5(WRITER, NAMESPACE, MIGRATION), DELEGATE);
        assertEq(LibMigrationRegistry.appliedByV5(WRITER, NAMESPACE, SECOND), address(0));
    }

    /// `appliedByV5` refuses an address with no registry.
    function testAppliedByNoRegistryIsRefused() external {
        expectCodeHash(bytes32(0));
        this.externalAppliedBy();
    }

    /// Every delegation builder and read refuses other code at the registry
    /// address, naming its hash.
    function testDelegationWrappersWrongCodeIsRefused(bytes memory code) external {
        vm.assume(code.length > 0 && code[0] != 0xef);
        vm.assume(keccak256(code) != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH);
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, code);
        expectDelegationWrappersRefuse(keccak256(code));
    }

    /// Every delegation builder, read and direct approve and revoke refuses a
    /// registry address delegated to another account.
    function testDelegationWrappersDelegatedCodeIsRefused(address delegate) external {
        vm.assume(delegate != address(0));
        bytes memory designator = LibAccountCode.delegationDesignator(delegate);
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, designator);
        expectDelegationWrappersRefuse(keccak256(designator));
        MockMigrationApplier applier = new MockMigrationApplier();
        expectCodeHash(keccak256(designator));
        applier.approveV5(NAMESPACE, DELEGATE);
        expectCodeHash(keccak256(designator));
        applier.revokeV5(NAMESPACE, DELEGATE);
    }
}
