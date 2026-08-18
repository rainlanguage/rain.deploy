// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {IMigrationRegistryV1, MIGRATION_HEAD_GENESIS} from "../../../src/interface/IMigrationRegistryV1.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {MockMigrationApplier} from "../../concrete/MockMigrationApplier.sol";
import {DELEGATION_DESIGNATOR_LENGTH, LibAccountCode} from "../../lib/LibAccountCode.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

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

    /// Occupant code that is ORDINARY contract code rather than a delegation
    /// designator, which is the kind the three `WrongCode` cases fuzz.
    ///
    /// `LibAccountCode` is what says why the split exists. The designator kind
    /// is covered on its own by the three `DelegatedCode` cases, because an
    /// account holding one executes the delegate's code while carrying 23 bytes
    /// of its own — a shape no amount of fuzzing `bytes` can construct, and one
    /// `vm.etch` refuses at every length but that.
    /// @param code The fuzzed candidate.
    function assumeOrdinaryCode(bytes memory code) internal pure {
        vm.assume(code.length > 0);
        vm.assume(!LibAccountCode.hasDelegationPrefix(code));
    }

    /// The designator that delegates the registry address to `delegate`,
    /// refusing the clearing form — a delegation to zero leaves the account
    /// empty, which is what the `NoRegistry` cases already cover.
    /// @param delegate The fuzzed delegate.
    /// @return designator The 23-byte designator.
    function assumedDesignator(address delegate) internal pure returns (bytes memory designator) {
        vm.assume(delegate != address(0));
        designator = LibAccountCode.delegationDesignator(delegate);
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
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        assertEq(LibMigrationRegistry.applied(writer, migration), 0);
    }

    /// An applied migration answers the moment it was applied — read back
    /// through the library, so what `applyMigration` writes is what `applied`
    /// finds.
    function testApplyMigrationThenApplied(bytes32 migration, uint32 appliedAt) external {
        LibMigrationFuzz.assumeMigration(vm, migration);
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
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
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
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, skipped);
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
        LibMigrationFuzz.assumeMigration(vm, migration);
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
        LibMigrationFuzz.assumeMigration(vm, migration);
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
        LibMigrationFuzz.assumeMigration(vm, migration);
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
        LibMigrationFuzz.assumeMigration(vm, migration);
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
    /// calling into an empty account, and the point of that is the NAME. An
    /// empty account has no returndata for `abi.decode` to read, so the call
    /// reverts unguarded too — anonymously, saying nothing about whether the
    /// registry is absent or the migration unapplied. Those are different
    /// facts, and this error is what tells them apart. The case that would
    /// answer the lie instead of reverting is occupying code, covered by
    /// `testAppliedWrongCode` and `testAppliedDelegatedCode`.
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

    /// Reading a head off a chain with no registry is refused for the same
    /// reason and with the same named error: an unguarded read reverts here
    /// anyway, because there is no returndata for a `bytes32` to decode from,
    /// so what the check adds is which chain state it was. A head that is not
    /// a head is what occupying code can return, not what an empty one does.
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

    /// Writing to a chain with no registry is refused by the code hash rather
    /// than by solc's own existence check, which an `applyMigration` into an
    /// empty account hits regardless — no return data is expected, so the
    /// callee is checked to exist and the write reverts unnamed. A migration
    /// that reports itself applied and is not is what a write into occupying
    /// code does, and `testApplyMigrationWrongCode` is where that is covered.
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

    /// A chain where ordinary code other than the pinned registry occupies the
    /// address reverts on the code hash, so a migration is never read from code
    /// the caller did not compile against.
    function testAppliedWrongCode(address writer, bytes32 migration, bytes memory code) external {
        assumeOrdinaryCode(code);
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
        assumeOrdinaryCode(code);
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
        assumeOrdinaryCode(code);
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

    /// A chain where an EOA has DELEGATED the registry address under EIP-7702
    /// is refused on the code hash exactly as ordinary wrong code is. This is
    /// the other way an address gets occupied, and the worse one for a reader:
    /// the account carries 23 bytes of designator while executing whatever the
    /// delegate holds, so an address that looks like nothing at all can answer
    /// `applied` with any timestamp it likes.
    ///
    /// The code hash refuses it without knowing anything about 7702 — a
    /// delegated account hashes its designator and never the delegate's code,
    /// so it can never present the pinned registry's hash.
    /// @param writer The namespace a reader would ask about.
    /// @param migration The migration a reader would ask about.
    /// @param delegate The account the registry address is delegated to.
    function testAppliedDelegatedCode(address writer, bytes32 migration, address delegate) external {
        bytes memory designator = assumedDesignator(delegate);
        assertEq(designator.length, DELEGATION_DESIGNATOR_LENGTH);

        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, designator);
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.codehash, keccak256(designator));

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(designator)
            )
        );
        this.externalApplied(writer, migration);
    }

    /// Nor is a head read out of a delegated account.
    /// @param writer The namespace a reader would ask about.
    /// @param delegate The account the registry address is delegated to.
    function testHeadDelegatedCode(address writer, address delegate) external {
        bytes memory designator = assumedDesignator(delegate);

        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, designator);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(designator)
            )
        );
        this.externalHead(writer);
    }

    /// And a migration is never applied into one. This is the write, so the
    /// delegate would otherwise be handed a record the writer believes is in
    /// the registry and every later reader asserts against.
    /// @param expectedHead The head the writer believes it is at.
    /// @param migration The migration being applied.
    /// @param delegate The account the registry address is delegated to.
    function testApplyMigrationDelegatedCode(bytes32 expectedHead, bytes32 migration, address delegate) external {
        bytes memory designator = assumedDesignator(delegate);

        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, designator);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(designator)
            )
        );
        this.externalApplyMigration(expectedHead, migration);
    }
}
