// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {IMigrationRegistryV1} from "../../../src/interface/IMigrationRegistryV1.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {MockMigrationRecorder} from "../../concrete/MockMigrationRecorder.sol";

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

    /// External wrapper for `applied` so that `vm.expectRevert` works at the
    /// correct call depth.
    /// @param writer The namespace to read.
    /// @param migration The migration to ask about.
    /// @return Whether `writer` has recorded `migration`.
    function externalApplied(address writer, bytes32 migration) external view returns (bool) {
        return LibMigrationRegistry.applied(writer, migration);
    }

    /// External wrapper for `record` so that `vm.expectRevert` works at the
    /// correct call depth.
    /// @param migration The migration to record.
    function externalRecord(bytes32 migration) external {
        LibMigrationRegistry.record(migration);
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

    /// An unrecorded migration answers `false`. This is the branch a caller
    /// asserts the pre-migration state in, and it is the ordinary state of
    /// every migration that has not run, so it is an answer rather than a
    /// revert.
    function testAppliedUnrecordedIsFalse(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(migration != bytes32(0));
        deployRegistry();

        assertFalse(LibMigrationRegistry.applied(writer, migration));
    }

    /// A recorded migration answers `true` — read back through the library, so
    /// what `record` writes is what `applied` finds.
    function testRecordThenApplied(bytes32 migration) external {
        vm.assume(migration != bytes32(0));
        deployRegistry();

        LibMigrationRegistry.record(migration);

        assertTrue(LibMigrationRegistry.applied(address(this), migration));
    }

    /// The namespace is the CONTRACT that executes the library call. The
    /// library's functions are `internal`, so they inline into their caller and
    /// the registry sees that caller as `msg.sender` — which means a consumer
    /// chooses its namespace by choosing what sends the transaction, and cannot
    /// write anybody else's.
    function testRecordLandsUnderTheCallingContract(bytes32 migration) external {
        vm.assume(migration != bytes32(0));
        deployRegistry();
        MockMigrationRecorder recorder = new MockMigrationRecorder();

        recorder.record(migration);

        assertTrue(LibMigrationRegistry.applied(address(recorder), migration));
        assertFalse(LibMigrationRegistry.applied(address(this), migration));
    }

    /// One caller's record reaches no other namespace, and each answers only
    /// for itself. This is the whole of the access control: a reader's choice
    /// of writer is the whole of who it trusts.
    function testRecordDoesNotReachAnotherNamespace(bytes32 migration) external {
        vm.assume(migration != bytes32(0));
        deployRegistry();
        MockMigrationRecorder recorder = new MockMigrationRecorder();
        MockMigrationRecorder other = new MockMigrationRecorder();

        recorder.record(migration);

        assertTrue(other.applied(address(recorder), migration));
        assertFalse(other.applied(address(other), migration));
    }

    /// Recording the same migration twice is refused, and the registry's own
    /// revert arrives unmodified — the library adds no handling of its own, so
    /// a re-dispatched migration fails naming the writer and the id.
    function testRecordTwiceReverts(bytes32 migration) external {
        vm.assume(migration != bytes32(0));
        deployRegistry();

        LibMigrationRegistry.record(migration);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV1.MigrationAlreadyRecorded.selector, address(this), migration)
        );
        this.externalRecord(migration);
    }

    /// The registry's zero-id refusal arrives unmodified through `record`.
    function testRecordZeroMigrationReverts() external {
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV1.ZeroMigration.selector));
        this.externalRecord(bytes32(0));
    }

    /// The registry's zero-writer refusal arrives unmodified through `applied`.
    function testAppliedZeroWriterReverts(bytes32 migration) external {
        vm.assume(migration != bytes32(0));
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

    /// A chain with no registry deployed reverts on the code hash rather than
    /// calling into an empty account. That call would succeed and return
    /// nothing, which `abi.decode` would read as `false` — "this migration has
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

    /// Writing to a chain with no registry is refused for the mirror reason: a
    /// `record` into an empty account is a migration that reports itself
    /// recorded and is not, which leaves every reader asserting the
    /// pre-migration state forever.
    function testRecordNoRegistry(bytes32 migration) external {
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalRecord(migration);
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

    /// And never recorded into it either.
    function testRecordWrongCode(bytes32 migration, bytes memory code) external {
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
        this.externalRecord(migration);
    }
}
