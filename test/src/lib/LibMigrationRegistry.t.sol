// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {IMigrationRegistryV1, Prerequisite} from "../../../src/interface/IMigrationRegistryV1.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {MockMigrationApplier} from "../../concrete/MockMigrationApplier.sol";
import {DELEGATION_DESIGNATOR_LENGTH, LibAccountCode} from "../../lib/LibAccountCode.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

/// @title LibMigrationRegistryTest
/// Tests for `LibMigrationRegistry`. The registry is not mocked: the real
/// `MigrationRegistry` is deployed through the Zoltu factory, which is what puts
/// it at the pinned address with the pinned code hash.
///
/// External wrappers are used for the library functions so `vm.expectRevert`
/// lands at the correct call depth.
contract LibMigrationRegistryTest is Test {
    /// Deploys `MigrationRegistry` through the Zoltu factory, which lands it at
    /// the pinned address.
    /// @return The deployed registry.
    function deployRegistry() internal returns (IMigrationRegistryV1) {
        LibRainDeploy.etchZoltuFactory(vm);
        return IMigrationRegistryV1(LibRainDeploy.deployZoltu(type(MigrationRegistry).creationCode));
    }

    /// Occupant code that is ORDINARY contract code rather than a delegation
    /// designator. The designator kind is covered by the `DelegatedCode`
    /// cases: an account holding one carries 23 bytes of its own while
    /// executing the delegate's code, a shape `vm.etch` refuses at every other
    /// length.
    /// @param code The fuzzed candidate.
    function assumeOrdinaryCode(bytes memory code) internal pure {
        vm.assume(code.length > 0);
        vm.assume(!LibAccountCode.hasDelegationPrefix(code));
        vm.assume(keccak256(code) != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH);
    }

    /// The designator that delegates the registry address to `delegate`,
    /// refusing the clearing form, which the `NoRegistry` cases already cover.
    /// @param delegate The fuzzed delegate.
    /// @return designator The 23-byte designator.
    function assumedDesignator(address delegate) internal pure returns (bytes memory designator) {
        vm.assume(delegate != address(0));
        designator = LibAccountCode.delegationDesignator(delegate);
    }

    /// The code-hash revert for whatever occupies the registry address.
    function unexpectedCodeHash() internal view returns (bytes memory) {
        return abi.encodeWithSelector(
            LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.codehash
        );
    }

    function externalApplied(address writer, bytes32 migration) external view returns (uint256) {
        return LibMigrationRegistry.applied(writer, migration);
    }

    function externalApplyMigration(bytes32 migration, Prerequisite[] memory prerequisites) external {
        LibMigrationRegistry.applyMigration(migration, prerequisites);
    }

    function externalApplyMigrationHistory(bytes32 migration, uint256 appliedAt, Prerequisite[] memory prerequisites)
        external
    {
        LibMigrationRegistry.applyMigrationHistory(migration, appliedAt, prerequisites);
    }

    /// Every other test here depends on the pin being current; a stale pin
    /// would otherwise show up as an unrelated code-hash revert in all of them.
    function testDeployMatchesPins() external {
        deployRegistry();

        assertEq(
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.codehash,
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH
        );
    }

    function testAppliedUnappliedIsZero(address writer, bytes32 migration) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        deployRegistry();

        assertEq(LibMigrationRegistry.applied(writer, migration), 0);
    }

    function testApplyMigrationThenApplied(bytes32 migration, uint32 now_) external {
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(now_ != 0);
        deployRegistry();
        vm.warp(now_);

        LibMigrationRegistry.applyMigration(migration, new Prerequisite[](0));

        assertEq(LibMigrationRegistry.applied(address(this), migration), now_);
    }

    function testApplyMigrationHistoryThenApplied(bytes32 migration, uint32 appliedAt, uint32 writtenAt) external {
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(appliedAt != 0);
        vm.assume(writtenAt > appliedAt);
        deployRegistry();
        vm.warp(writtenAt);

        LibMigrationRegistry.applyMigrationHistory(migration, appliedAt, new Prerequisite[](0));

        assertEq(LibMigrationRegistry.applied(address(this), migration), appliedAt);
    }

    /// A sequence within one namespace, each naming its predecessor, through
    /// both writes.
    function testApplyMigrationSequence(bytes32 migrationA, bytes32 migrationB, bytes32 migrationC) external {
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, migrationC);
        vm.assume(migrationA != migrationB);
        vm.assume(migrationB != migrationC);
        vm.assume(migrationA != migrationC);
        deployRegistry();
        vm.warp(9000);

        LibMigrationRegistry.applyMigrationHistory(migrationA, 1000, new Prerequisite[](0));
        LibMigrationRegistry.applyMigrationHistory(migrationB, 2000, LibMigrationFuzz.one(address(this), migrationA));
        LibMigrationRegistry.applyMigration(migrationC, LibMigrationFuzz.one(address(this), migrationB));

        assertEq(LibMigrationRegistry.applied(address(this), migrationA), 1000);
        assertEq(LibMigrationRegistry.applied(address(this), migrationB), 2000);
        assertEq(LibMigrationRegistry.applied(address(this), migrationC), 9000);
    }

    /// The registry's own reverts arrive unmodified through both writes.
    function testApplyMigrationRegistryRevertsPassThrough(address other, bytes32 migration, bytes32 prerequisite)
        external
    {
        LibMigrationFuzz.assumeKey(vm, other, prerequisite);
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(other != address(this) || migration != prerequisite);
        deployRegistry();
        vm.warp(1000);
        Prerequisite[] memory prerequisites = LibMigrationFuzz.one(other, prerequisite);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        this.externalApplyMigration(migration, prerequisites);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.PrerequisiteNotApplied.selector, other, prerequisite)
        );
        this.externalApplyMigrationHistory(migration, 1000, prerequisites);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        this.externalApplyMigration(migration, LibMigrationFuzz.one(address(0), prerequisite));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        this.externalApplyMigration(bytes32(0), prerequisites);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroTimestamp.selector));
        this.externalApplyMigrationHistory(migration, 0, new Prerequisite[](0));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.FutureTimestamp.selector, 1001, 1000));
        this.externalApplyMigrationHistory(migration, 1001, new Prerequisite[](0));

        LibMigrationRegistry.applyMigration(migration, new Prerequisite[](0));
        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.MigrationAlreadyApplied.selector, address(this), migration)
        );
        this.externalApplyMigration(migration, new Prerequisite[](0));
    }

    function testAppliedRegistryRevertsPassThrough(address writer, bytes32 migration) external {
        LibMigrationFuzz.assumeKey(vm, writer, migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        this.externalApplied(address(0), migration);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        this.externalApplied(writer, bytes32(0));
    }

    /// The namespace is the CONTRACT that executes the library call, so a
    /// consumer chooses its namespace by choosing what sends the transaction,
    /// and a prerequisite is read from whichever namespace it names.
    function testApplyMigrationLandsUnderTheCallingContract(bytes32 migration, bytes32 prerequisite, uint32 appliedAt)
        external
    {
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        vm.assume(appliedAt != 0);
        deployRegistry();
        vm.warp(appliedAt);
        MockMigrationApplier upstream = new MockMigrationApplier();
        MockMigrationApplier applier = new MockMigrationApplier();
        MockMigrationApplier historian = new MockMigrationApplier();
        Prerequisite[] memory prerequisites = LibMigrationFuzz.one(address(upstream), prerequisite);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV1.PrerequisiteNotApplied.selector, address(upstream), prerequisite
            )
        );
        applier.applyMigration(migration, prerequisites);

        upstream.applyMigration(prerequisite, new Prerequisite[](0));
        applier.applyMigration(migration, prerequisites);
        historian.applyMigrationHistory(migration, appliedAt, prerequisites);

        assertEq(applier.applied(address(applier), migration), appliedAt);
        assertEq(historian.applied(address(historian), migration), appliedAt);
        assertEq(LibMigrationRegistry.applied(address(upstream), prerequisite), appliedAt);
        assertEq(LibMigrationRegistry.applied(address(upstream), migration), 0);
        assertEq(LibMigrationRegistry.applied(address(this), migration), 0);
    }

    /// A chain with no registry reverts on the code hash rather than calling
    /// into an empty account: an empty account reverts unguarded too, but
    /// anonymously, and this is what names it.
    function testAppliedNoRegistry(address writer, bytes32 migration) external {
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(unexpectedCodeHash());
        this.externalApplied(writer, migration);
    }

    function testApplyMigrationNoRegistry(bytes32 migration, Prerequisite[] memory prerequisites) external {
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(unexpectedCodeHash());
        this.externalApplyMigration(migration, prerequisites);
    }

    function testApplyMigrationHistoryNoRegistry(
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] memory prerequisites
    ) external {
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(unexpectedCodeHash());
        this.externalApplyMigrationHistory(migration, appliedAt, prerequisites);
    }

    /// Ordinary code other than the pinned registry at the address is the case
    /// that does NOT revert unguarded: it is free to answer zero to every
    /// migration, or to accept every write and record nothing.
    function testAppliedWrongCode(address writer, bytes32 migration, bytes memory code) external {
        assumeOrdinaryCode(code);
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, code);

        vm.expectRevert(unexpectedCodeHash());
        this.externalApplied(writer, migration);
    }

    function testApplyMigrationWrongCode(bytes32 migration, Prerequisite[] memory prerequisites, bytes memory code)
        external
    {
        assumeOrdinaryCode(code);
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, code);

        vm.expectRevert(unexpectedCodeHash());
        this.externalApplyMigration(migration, prerequisites);
    }

    function testApplyMigrationHistoryWrongCode(
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] memory prerequisites,
        bytes memory code
    ) external {
        assumeOrdinaryCode(code);
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, code);

        vm.expectRevert(unexpectedCodeHash());
        this.externalApplyMigrationHistory(migration, appliedAt, prerequisites);
    }

    /// An EOA that has DELEGATED the registry address under EIP-7702 is the
    /// other way an address gets occupied. The code hash refuses it without
    /// knowing anything about 7702: a delegated account hashes its designator,
    /// never the delegate's code.
    function testAppliedDelegatedCode(address writer, bytes32 migration, address delegate) external {
        bytes memory designator = assumedDesignator(delegate);
        assertEq(designator.length, DELEGATION_DESIGNATOR_LENGTH);
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, designator);
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.codehash, keccak256(designator));

        vm.expectRevert(unexpectedCodeHash());
        this.externalApplied(writer, migration);
    }

    function testApplyMigrationDelegatedCode(bytes32 migration, Prerequisite[] memory prerequisites, address delegate)
        external
    {
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, assumedDesignator(delegate));

        vm.expectRevert(unexpectedCodeHash());
        this.externalApplyMigration(migration, prerequisites);
    }

    function testApplyMigrationHistoryDelegatedCode(
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] memory prerequisites,
        address delegate
    ) external {
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, assumedDesignator(delegate));

        vm.expectRevert(unexpectedCodeHash());
        this.externalApplyMigrationHistory(migration, appliedAt, prerequisites);
    }
}
