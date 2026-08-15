// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {IMigrationRegistryV1, MIGRATION_HEAD_GENESIS} from "../../../src/interface/IMigrationRegistryV1.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {MockMigrationApplier} from "../../concrete/MockMigrationApplier.sol";

/// @title LibMigrationRegistryTest
/// Tests for `LibMigrationRegistry`. The registry is not mocked: the real
/// `MigrationRegistry` is deployed through the Zoltu factory, which is what puts
/// it at the pinned address with the pinned code hash, so every test runs
/// against the same bytecode a network would.
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

    /// A migration id that is neither of the two values the head space reserves.
    /// @param migration The fuzzed candidate.
    function assumeMigration(bytes32 migration) internal pure {
        vm.assume(migration != bytes32(0));
        vm.assume(migration != MIGRATION_HEAD_GENESIS);
    }

    /// External wrapper for `applied` so that `vm.expectRevert` works at the
    /// correct call depth.
    /// @param writer The namespace to read.
    /// @param migration The migration to ask about.
    /// @return When `writer` applied `migration`, or zero.
    function externalApplied(address writer, bytes32 migration) external view returns (uint256) {
        return LibMigrationRegistry.applied(writer, migration);
    }

    /// External wrapper for `head` so that `vm.expectRevert` works at the
    /// correct call depth.
    /// @param writer The namespace to read.
    /// @return The head of that namespace.
    function externalHead(address writer) external view returns (bytes32) {
        return LibMigrationRegistry.head(writer);
    }

    /// External wrapper for `applyMigration` so that `vm.expectRevert` works at
    /// the correct call depth.
    /// @param expectedHead The head this contract believes it is at.
    /// @param migration The migration to apply.
    function externalApplyMigration(bytes32 expectedHead, bytes32 migration) external {
        LibMigrationRegistry.applyMigration(expectedHead, migration);
    }

    /// The Zoltu deploy really does land the registry on its pinned address
    /// with its pinned code hash. Every other test here depends on that, and a
    /// pin that had gone stale would otherwise show up as an unrelated
    /// code-hash revert in all of them.
    function testDeployMatchesPins() external {
        deployRegistry();

        assertEq(
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.codehash,
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH
        );
    }

    /// An unapplied migration answers zero. This is the branch a caller
    /// asserts the pre-migration state in, and it is the ordinary state of
    /// every migration that has not run, so it is an answer rather than a
    /// revert.
    function testAppliedUnappliedIsZero(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        assumeMigration(migration);
        deployRegistry();

        assertEq(LibMigrationRegistry.applied(writer, migration), 0);
    }

    /// An applied migration answers the moment it was applied — read back
    /// through the library, so what `applyMigration` writes is what `applied`
    /// finds.
    function testApplyMigrationThenApplied(bytes32 migration, uint32 appliedAt) external {
        assumeMigration(migration);
        vm.assume(appliedAt != 0);
        deployRegistry();
        vm.warp(appliedAt);

        LibMigrationRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        assertEq(LibMigrationRegistry.applied(address(this), migration), appliedAt);
    }

    /// A namespace that has applied nothing reads back as genesis, and each
    /// record moves the head to itself. This is the value the next migration
    /// has to name, so it is read through the library rather than assumed.
    function testHeadFollowsTheRecords(bytes32 migrationA, bytes32 migrationB) external {
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);
        deployRegistry();

        assertEq(LibMigrationRegistry.head(address(this)), MIGRATION_HEAD_GENESIS);

        LibMigrationRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migrationA);
        assertEq(LibMigrationRegistry.head(address(this)), migrationA);

        LibMigrationRegistry.applyMigration(migrationA, migrationB);
        assertEq(LibMigrationRegistry.head(address(this)), migrationB);
    }

    /// A migration applied onto a head this namespace is not at is refused, and
    /// the registry's own revert arrives unmodified. This is a skipped step
    /// failing at the moment of applying rather than a chain quietly diverging.
    function testApplyMigrationSkippedPredecessorReverts(bytes32 migration, bytes32 skipped) external {
        assumeMigration(migration);
        assumeMigration(skipped);
        deployRegistry();

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV1.UnexpectedMigrationHead.selector, address(this), skipped, MIGRATION_HEAD_GENESIS
            )
        );
        this.externalApplyMigration(skipped, migration);

        assertEq(LibMigrationRegistry.applied(address(this), migration), 0);
    }

    /// The namespace is the CONTRACT that executes the library call. The
    /// library's functions are `internal`, so they inline into their caller and
    /// the registry sees that caller as `msg.sender` — which means a consumer
    /// chooses its namespace by choosing what sends the transaction, and cannot
    /// write anybody else's.
    function testApplyMigrationLandsUnderTheCallingContract(bytes32 migration) external {
        assumeMigration(migration);
        deployRegistry();
        MockMigrationApplier applier = new MockMigrationApplier();

        applier.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        assertEq(LibMigrationRegistry.applied(address(applier), migration), block.timestamp);
        assertEq(LibMigrationRegistry.applied(address(this), migration), 0);
    }

    /// One caller's record reaches no other namespace, and each answers only
    /// for itself — heads included, so one consumer's sequence neither blocks
    /// nor unblocks another's. This is the whole of the access control: a
    /// reader's choice of writer is the whole of who it trusts.
    function testApplyMigrationDoesNotReachAnotherNamespace(bytes32 migration) external {
        assumeMigration(migration);
        deployRegistry();
        MockMigrationApplier applier = new MockMigrationApplier();
        MockMigrationApplier other = new MockMigrationApplier();

        applier.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        assertEq(other.applied(address(applier), migration), block.timestamp);
        assertEq(other.applied(address(other), migration), 0);
        assertEq(other.head(address(applier)), migration);
        assertEq(other.head(address(other)), MIGRATION_HEAD_GENESIS);
    }

    /// Applying the same migration twice is refused, and the registry's own
    /// revert arrives unmodified — the library adds no handling of its own, so
    /// a re-dispatched migration fails naming the writer and the id.
    function testApplyMigrationTwiceReverts(bytes32 migration) external {
        assumeMigration(migration);
        deployRegistry();

        LibMigrationRegistry.applyMigration(MIGRATION_HEAD_GENESIS, migration);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.MigrationAlreadyApplied.selector, address(this), migration)
        );
        this.externalApplyMigration(MIGRATION_HEAD_GENESIS, migration);
    }

    /// The registry's zero-id refusal arrives unmodified through
    /// `applyMigration`.
    function testApplyMigrationZeroMigrationReverts() external {
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        this.externalApplyMigration(MIGRATION_HEAD_GENESIS, bytes32(0));
    }

    /// The registry's genesis-id refusal arrives unmodified through
    /// `applyMigration`.
    function testApplyMigrationGenesisMigrationReverts() external {
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        this.externalApplyMigration(MIGRATION_HEAD_GENESIS, MIGRATION_HEAD_GENESIS);
    }

    /// The registry's zero-writer refusal arrives unmodified through `applied`.
    function testAppliedZeroWriterReverts(bytes32 migration) external {
        assumeMigration(migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        this.externalApplied(address(0), migration);
    }

    /// The registry's zero-id refusal arrives unmodified through `applied`.
    function testAppliedZeroMigrationReverts(address writer) external {
        vm.assume(writer != address(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        this.externalApplied(writer, bytes32(0));
    }

    /// The registry's genesis-id refusal arrives unmodified through `applied`.
    function testAppliedGenesisMigrationReverts(address writer) external {
        vm.assume(writer != address(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.GenesisMigration.selector));
        this.externalApplied(writer, MIGRATION_HEAD_GENESIS);
    }

    /// The registry's zero-writer refusal arrives unmodified through `head`.
    function testHeadZeroWriterReverts() external {
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroWriter.selector));
        this.externalHead(address(0));
    }

    /// A chain with no registry deployed reverts on the code hash rather than
    /// calling into an empty account. That call would succeed and return
    /// nothing, which `abi.decode` would read as zero — "this migration has
    /// not been applied", on every chain the registry was never deployed to,
    /// which is exactly the silent pre-migration branch this library exists to
    /// make impossible.
    function testAppliedNoRegistry(address writer, bytes32 migration) external {
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalApplied(writer, migration);
    }

    /// Reading a head off a chain with no registry is refused for a sharper
    /// version of the same reason: the empty-account read decodes as zero, and
    /// zero is a value no head can ever hold, so an unverified read hands back
    /// something that is not a head at all.
    function testHeadNoRegistry(address writer) external {
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalHead(writer);
    }

    /// Writing to a chain with no registry is refused for the mirror reason: an
    /// `applyMigration` into an empty account is a migration that reports itself
    /// applied and is not, which leaves every reader asserting the
    /// pre-migration state forever.
    function testApplyMigrationNoRegistry(bytes32 expectedHead, bytes32 migration) external {
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalApplyMigration(expectedHead, migration);
    }

    /// A chain where something other than the pinned registry occupies the
    /// address reverts on the code hash, so a migration is never read from code
    /// the caller did not compile against.
    function testAppliedWrongCode(address writer, bytes32 migration, bytes memory code) external {
        vm.assume(code.length > 0);
        vm.assume(keccak256(code) != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH);
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, code);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(code)
            )
        );
        this.externalApplied(writer, migration);
    }

    /// Nor is a head.
    function testHeadWrongCode(address writer, bytes memory code) external {
        vm.assume(code.length > 0);
        vm.assume(keccak256(code) != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH);
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, code);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(code)
            )
        );
        this.externalHead(writer);
    }

    /// And never applied into it either.
    function testApplyMigrationWrongCode(bytes32 expectedHead, bytes32 migration, bytes memory code) external {
        vm.assume(code.length > 0);
        vm.assume(keccak256(code) != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH);
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, code);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(code)
            )
        );
        this.externalApplyMigration(expectedHead, migration);
    }
}
