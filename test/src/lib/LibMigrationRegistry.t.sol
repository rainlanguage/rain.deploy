// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IRegistryDelegatesV1} from "../../../src/interface/IRegistryDelegatesV1.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    IMigrationRegistryV4,
    MIGRATION_HEAD_GENESIS,
    Prerequisite
} from "../../../src/interface/IMigrationRegistryV4.sol";
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
    function deployRegistry() internal returns (IMigrationRegistryV4) {
        return IMigrationRegistryV4(LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode));
    }

    /// Occupant code that is ORDINARY contract code rather than a delegation
    /// designator, which is the kind the `WrongCode` cases fuzz.
    ///
    /// `LibAccountCode` is what says why the split exists. The designator kind
    /// is covered on its own by the `DelegatedCode` cases, because an account
    /// holding one executes the delegate's code while carrying 23 bytes of its
    /// own — a shape no amount of fuzzing `bytes` can construct, and one
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
    /// @return The 23-byte designator.
    function assumedDesignator(address delegate) internal pure returns (bytes memory) {
        vm.assume(delegate != address(0));
        bytes memory designator = LibAccountCode.delegationDesignator(delegate);
        return designator;
    }

    /// External wrapper for `appliedV4` so that `vm.expectRevert` works at the
    /// correct call depth.
    /// @param writer The writer to read.
    /// @param namespace The line under `writer` to read.
    /// @param migration The migration to ask about.
    /// @return When `writer` applied `migration` in `namespace`, or zero.
    function externalApplied(address writer, bytes32 namespace, bytes32 migration) external view returns (uint256) {
        return LibMigrationRegistry.appliedV4(writer, namespace, migration);
    }

    /// External wrapper for `appliedOntoV4` so that `vm.expectRevert` works at
    /// the correct call depth.
    /// @param writer The writer to read.
    /// @param namespace The line under `writer` to read.
    /// @param migration The migration to ask about.
    /// @return What `writer` applied `migration` onto in `namespace`, or zero.
    function externalAppliedOnto(address writer, bytes32 namespace, bytes32 migration) external view returns (bytes32) {
        return LibMigrationRegistry.appliedOntoV4(writer, namespace, migration);
    }

    /// External wrapper for `appliedAfterV4` so that `vm.expectRevert` works at
    /// the correct call depth.
    /// @param writer The writer to read.
    /// @param namespace The line under `writer` to read.
    /// @param migration The migration to ask about.
    /// @return What `writer` applied `migration` after in `namespace`, or
    /// empty.
    function externalAppliedAfter(address writer, bytes32 namespace, bytes32 migration)
        external
        view
        returns (Prerequisite[] memory)
    {
        return LibMigrationRegistry.appliedAfterV4(writer, namespace, migration);
    }

    /// External wrapper for `headV4` so that `vm.expectRevert` works at the
    /// correct call depth.
    /// @param writer The writer to read.
    /// @param namespace The line under `writer` to read.
    /// @return The head of that line.
    function externalHead(address writer, bytes32 namespace) external view returns (bytes32) {
        return LibMigrationRegistry.headV4(writer, namespace);
    }

    /// External wrapper for `applyMigrationV4` so that `vm.expectRevert` works at
    /// the correct call depth.
    /// @param namespace The line to apply in.
    /// @param migration The migration to apply.
    /// @param prerequisites This contract at its head, then the migrations
    /// that must already be applied.
    function externalApplyMigration(string memory namespace, string memory migration, Prerequisite[] memory prerequisites)
        external
    {
        LibMigrationRegistry.applyMigrationV4(address(this), namespace, migration, prerequisites);
    }

    /// External wrapper for `applyMigrationHistoryV4` so that `vm.expectRevert`
    /// works at the correct call depth.
    /// @param namespace The line to apply in.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment to record against it.
    /// @param prerequisites This contract at its head, then the migrations
    /// that must already be applied.
    function externalApplyMigrationHistory(
        string memory namespace,
        string memory migration,
        uint256 appliedAt,
        Prerequisite[] memory prerequisites
    ) external {
        LibMigrationRegistry.applyMigrationHistoryV4(address(this), namespace, migration, appliedAt, prerequisites);
    }

    /// One entry, as a list. As the whole list it is a writer at its head in
    /// a namespace, waiting on nothing else.
    /// @param writer The entry's writer.
    /// @param namespace The entry's namespace.
    /// @param migration The entry's migration.
    /// @return The one-entry list.
    function one(address writer, bytes32 namespace, bytes32 migration) internal pure returns (Prerequisite[] memory) {
        Prerequisite[] memory prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: writer, namespace: namespace, migration: migration});
        return prerequisites;
    }

    /// The list a write takes: `writer` in `namespace` at `headV4`, then
    /// `prerequisites`.
    /// @param writer The writer writing.
    /// @param namespace The line it is writing.
    /// @param head The head it believes it is at.
    /// @param prerequisites The migrations that must already be applied.
    /// @return The list.
    function headThen(address writer, bytes32 namespace, bytes32 head, Prerequisite[] memory prerequisites)
        internal
        pure
        returns (Prerequisite[] memory)
    {
        Prerequisite[] memory list = new Prerequisite[](prerequisites.length + 1);
        list[0] = Prerequisite({writer: writer, namespace: namespace, migration: head});
        for (uint256 i = 0; i < prerequisites.length; i++) {
            list[i + 1] = prerequisites[i];
        }
        return list;
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
    function testAppliedUnappliedIsZero(address writer, bytes32 namespace, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        assertEq(LibMigrationRegistry.appliedV4(writer, namespace, migration), 0);
    }

    /// An applied migration answers the moment it was applied — read back
    /// through the library, so what `applyMigrationV4` writes is what `appliedV4`
    /// finds. The head alone is a migration that waits on nothing else, and
    /// reads back as given. The moment is a whole `uint256` timestamp, so a chain
    /// whose clock is past any narrower bound reads back exactly what it
    /// recorded.
    function testApplyMigrationThenApplied(string memory namespace, string memory migration, uint64 appliedAt) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(appliedAt != 0);
        deployRegistry();
        vm.warp(appliedAt);

        LibMigrationRegistry.applyMigrationV4(
            address(this), namespace, migration, one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS)
        );

        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationHash), appliedAt);
        assertEq(
            abi.encode(LibMigrationRegistry.appliedAfterV4(address(this), namespaceHash, migrationHash)),
            abi.encode(one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS))
        );
    }

    /// A line that has applied nothing reads back as genesis, and each
    /// record moves the head to itself. This is the value the next migration
    /// has to name, so it is read through the library rather than assumed.
    function testHeadFollowsTheRecords(string memory namespace, string memory migrationA, string memory migrationB) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        bytes32 migrationBHash = keccak256(bytes(migrationB));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationAHash != migrationBHash);
        deployRegistry();

        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), MIGRATION_HEAD_GENESIS);

        LibMigrationRegistry.applyMigrationV4(
            address(this), namespace, migrationA, one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS)
        );
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), migrationAHash);

        LibMigrationRegistry.applyMigrationV4(
            address(this), namespace, migrationB, one(address(this), namespaceHash, migrationAHash)
        );
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), migrationBHash);
    }

    /// Two lines under one writer have two heads: a record in one leaves the
    /// other at genesis, and each advances on its own records only.
    function testHeadIsPerNamespace(string memory namespace, string memory otherNamespace, string memory migrationA, string memory migrationB)
        external
    {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 otherNamespaceHash = keccak256(bytes(otherNamespace));
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        bytes32 migrationBHash = keccak256(bytes(migrationB));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeNamespace(vm, otherNamespace);
        vm.assume(namespaceHash != otherNamespaceHash);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationAHash != migrationBHash);
        deployRegistry();

        LibMigrationRegistry.applyMigrationV4(
            address(this), namespace, migrationA, one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS)
        );
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), migrationAHash);
        assertEq(LibMigrationRegistry.headV4(address(this), otherNamespaceHash), MIGRATION_HEAD_GENESIS);

        LibMigrationRegistry.applyMigrationV4(
            address(this), otherNamespace, migrationB, one(address(this), otherNamespaceHash, MIGRATION_HEAD_GENESIS)
        );
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), migrationAHash);
        assertEq(LibMigrationRegistry.headV4(address(this), otherNamespaceHash), migrationBHash);

        LibMigrationRegistry.applyMigrationV4(
            address(this), namespace, migrationB, one(address(this), namespaceHash, migrationAHash)
        );
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), migrationBHash);
        assertEq(LibMigrationRegistry.headV4(address(this), otherNamespaceHash), migrationBHash);
        assertEq(LibMigrationRegistry.appliedOntoV4(address(this), namespaceHash, migrationBHash), migrationAHash);
        assertEq(LibMigrationRegistry.appliedOntoV4(address(this), otherNamespaceHash, migrationBHash), MIGRATION_HEAD_GENESIS);
    }

    /// A migration applied onto a head this line is not at is refused, and
    /// the registry's own revert arrives unmodified. This is a skipped step
    /// failing at the moment of applying rather than a chain quietly diverging.
    function testApplyMigrationSkippedPredecessorReverts(string memory namespace, string memory migration, string memory skipped)
        external
    {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        bytes32 skippedHash = keccak256(bytes(skipped));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, skipped);
        deployRegistry();

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.UnexpectedMigrationHead.selector,
                address(this),
                namespaceHash,
                address(this),
                namespaceHash,
                skippedHash,
                MIGRATION_HEAD_GENESIS
            )
        );
        this.externalApplyMigration(namespace, migration, one(address(this), namespaceHash, skippedHash));

        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationHash), 0);
    }

    /// The first entry is the writer's own head in the namespace the write
    /// names, so one naming another writer or another line is refused even
    /// when its migration is exactly the head both lines are at. The list is
    /// passed to the registry as the caller wrote it: nothing here repairs an
    /// entry that names the wrong line into one that names the right one.
    function testApplyMigrationHeadEntryIsTheWriterInTheNamespace(
        address other,
        string memory namespace,
        string memory otherNamespace,
        string memory migration
    ) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 otherNamespaceHash = keccak256(bytes(otherNamespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        vm.assume(other != address(0));
        vm.assume(other != address(this));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeNamespace(vm, otherNamespace);
        vm.assume(namespaceHash != otherNamespaceHash);
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.UnexpectedMigrationHead.selector,
                address(this),
                namespaceHash,
                other,
                namespaceHash,
                MIGRATION_HEAD_GENESIS,
                MIGRATION_HEAD_GENESIS
            )
        );
        this.externalApplyMigration(namespace, migration, one(other, namespaceHash, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.UnexpectedMigrationHead.selector,
                address(this),
                namespaceHash,
                address(this),
                otherNamespaceHash,
                MIGRATION_HEAD_GENESIS,
                MIGRATION_HEAD_GENESIS
            )
        );
        this.externalApplyMigration(namespace, migration, one(address(this), otherNamespaceHash, MIGRATION_HEAD_GENESIS));

        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationHash), 0);
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), MIGRATION_HEAD_GENESIS);
        assertEq(LibMigrationRegistry.headV4(other, namespaceHash), MIGRATION_HEAD_GENESIS);
        assertEq(LibMigrationRegistry.headV4(address(this), otherNamespaceHash), MIGRATION_HEAD_GENESIS);
    }

    /// The writer is the CONTRACT that executes the library call. The
    /// library's functions are `internal`, so they inline into their caller and
    /// the registry sees that caller as `msg.sender` — so naming the calling
    /// contract as `writer` writes its own line, and any other writer's line
    /// needs that writer's approval. The prerequisite is read from whichever line it
    /// names — here another consumer's — and that line is untouched.
    function testApplyMigrationLandsUnderTheCallingContract(string memory namespace, string memory migration, string memory prerequisite)
        external
    {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        bytes32 prerequisiteHash = keccak256(bytes(prerequisite));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        // The upstream assertion asks whether `migrationHash` reached its
        // line, which is only a question when it is not the
        // prerequisiteHash that was put there.
        vm.assume(migrationHash != prerequisiteHash);
        deployRegistry();
        MockMigrationApplier upstream = new MockMigrationApplier();
        MockMigrationApplier applier = new MockMigrationApplier();
        upstream.applyMigrationV4(
            address(upstream), namespace, prerequisite, one(address(upstream), namespaceHash, MIGRATION_HEAD_GENESIS)
        );

        applier.applyMigrationV4(
            address(applier),
            namespace,
            migration,
            headThen(
                address(applier), namespaceHash, MIGRATION_HEAD_GENESIS, one(address(upstream), namespaceHash, prerequisiteHash)
            )
        );

        assertEq(LibMigrationRegistry.appliedV4(address(applier), namespaceHash, migrationHash), block.timestamp);
        assertEq(LibMigrationRegistry.appliedOntoV4(address(applier), namespaceHash, migrationHash), MIGRATION_HEAD_GENESIS);
        assertEq(LibMigrationRegistry.appliedV4(address(upstream), namespaceHash, migrationHash), 0);
        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationHash), 0);
        assertEq(LibMigrationRegistry.headV4(address(upstream), namespaceHash), prerequisiteHash);
    }

    /// One writer's record reaches no other writer, and each answers only
    /// for itself — heads included, so one consumer's sequence neither blocks
    /// nor unblocks another's. A reader trusts the writer it chooses and that
    /// writer's delegates.
    function testApplyMigrationDoesNotReachAnotherWriter(string memory namespace, string memory migration) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();
        MockMigrationApplier applier = new MockMigrationApplier();
        MockMigrationApplier other = new MockMigrationApplier();

        applier.applyMigrationV4(
            address(applier), namespace, migration, one(address(applier), namespaceHash, MIGRATION_HEAD_GENESIS)
        );

        assertEq(other.appliedV4(address(applier), namespaceHash, migrationHash), block.timestamp);
        assertEq(other.appliedV4(address(other), namespaceHash, migrationHash), 0);
        assertEq(other.headV4(address(applier), namespaceHash), migrationHash);
        assertEq(other.headV4(address(other), namespaceHash), MIGRATION_HEAD_GENESIS);
    }

    /// Applying the same migration twice, onto the head it became, is refused,
    /// and the registry's own revert arrives unmodified — the library adds no
    /// handling of its own, so the refusal names the writer, the namespace
    /// and the id.
    function testApplyMigrationTwiceReverts(string memory namespace, string memory migration) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        LibMigrationRegistry.applyMigrationV4(
            address(this), namespace, migration, one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.MigrationAlreadyApplied.selector, address(this), namespaceHash, migrationHash
            )
        );
        this.externalApplyMigration(namespace, migration, one(address(this), namespaceHash, migrationHash));
    }

    /// The registry's empty-migration refusal arrives unmodified through both
    /// write paths, and nothing is recorded in the line.
    function testApplyMigrationEmptyMigrationReverts(string memory namespace) external {
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.EmptyMigration.selector));
        this.externalApplyMigration(namespace, "", one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.EmptyMigration.selector));
        this.externalApplyMigrationHistory(
            namespace, "", block.timestamp, one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS)
        );

        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, keccak256("")), 0);
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), MIGRATION_HEAD_GENESIS);
    }

    /// The registry's genesis refusal arrives unmodified through both write
    /// paths: the string that hashes to `MIGRATION_HEAD_GENESIS` cannot be
    /// applied.
    function testApplyMigrationGenesisMigrationReverts(string memory namespace) external {
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.GenesisMigration.selector));
        this.externalApplyMigration(
            namespace,
            "rain.migration-registry.head.genesis",
            one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS)
        );
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.GenesisMigration.selector));
        this.externalApplyMigrationHistory(
            namespace,
            "rain.migration-registry.head.genesis",
            block.timestamp,
            one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS)
        );

        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), MIGRATION_HEAD_GENESIS);
    }

    /// The registry's empty-namespace refusal arrives unmodified through
    /// `applyMigrationV4`, whatever head entry the list names, and nothing is
    /// recorded in any line.
    function testApplyMigrationEmptyNamespaceReverts(string memory namespace, string memory migration) external {
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        bytes32 emptyHash = keccak256("");
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.EmptyNamespace.selector));
        this.externalApplyMigration("", migration, one(address(this), emptyHash, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.EmptyNamespace.selector));
        this.externalApplyMigration("", migration, one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS));

        assertEq(LibMigrationRegistry.appliedV4(address(this), emptyHash, migrationHash), 0);
        assertEq(LibMigrationRegistry.headV4(address(this), emptyHash), MIGRATION_HEAD_GENESIS);
        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationHash), 0);
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), MIGRATION_HEAD_GENESIS);
    }

    /// The registry's empty-namespace refusal arrives unmodified through
    /// `applyMigrationHistoryV4`, and nothing is recorded in any line.
    function testApplyMigrationHistoryEmptyNamespaceReverts(
        string memory namespace,
        string memory migration,
        uint32 appliedAt
    ) external {
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(appliedAt != 0);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        bytes32 emptyHash = keccak256("");
        deployRegistry();
        vm.warp(appliedAt);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.EmptyNamespace.selector));
        this.externalApplyMigrationHistory("", migration, appliedAt, one(address(this), emptyHash, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.EmptyNamespace.selector));
        this.externalApplyMigrationHistory(
            "", migration, appliedAt, one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS)
        );

        assertEq(LibMigrationRegistry.appliedV4(address(this), emptyHash, migrationHash), 0);
        assertEq(LibMigrationRegistry.headV4(address(this), emptyHash), MIGRATION_HEAD_GENESIS);
        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationHash), 0);
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), MIGRATION_HEAD_GENESIS);
    }

    /// `applyMigrationV4` through the library lands the record once its
    /// prerequisite is applied, `appliedV4` reads it back as the block the write
    /// landed in, and `appliedAfterV4` reads the list back as given.
    function testApplyMigrationWithPrerequisiteThenApplied(
        address other,
        string memory namespace,
        string memory migration,
        string memory prerequisite,
        uint32 blockMoment
    ) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        bytes32 prerequisiteHash = keccak256(bytes(prerequisite));
        vm.assume(other != address(0));
        vm.assume(other != address(this));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(blockMoment != 0);
        vm.warp(blockMoment);
        IMigrationRegistryV4 registry = deployRegistry();
        vm.prank(other);
        registry.applyMigrationV4(other, namespace, prerequisite, one(other, namespaceHash, MIGRATION_HEAD_GENESIS));

        Prerequisite[] memory list =
            headThen(address(this), namespaceHash, MIGRATION_HEAD_GENESIS, one(other, namespaceHash, prerequisiteHash));
        LibMigrationRegistry.applyMigrationV4(address(this), namespace, migration, list);

        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationHash), blockMoment);
        assertEq(LibMigrationRegistry.appliedOntoV4(address(this), namespaceHash, migrationHash), MIGRATION_HEAD_GENESIS);
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), migrationHash);

        assertEq(abi.encode(LibMigrationRegistry.appliedAfterV4(address(this), namespaceHash, migrationHash)), abi.encode(list));
    }

    /// The calling contract's own other namespace is another line, so a record
    /// in it is a prerequisite like any other writer's: refused by name while
    /// unapplied, then landed and read back as given once applied.
    function testApplyMigrationOwnOtherNamespacePrerequisite(
        string memory namespace,
        string memory otherNamespace,
        string memory migrationA,
        string memory migrationB
    ) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 otherNamespaceHash = keccak256(bytes(otherNamespace));
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        bytes32 migrationBHash = keccak256(bytes(migrationB));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeNamespace(vm, otherNamespace);
        vm.assume(namespaceHash != otherNamespaceHash);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        deployRegistry();

        Prerequisite[] memory list =
            headThen(address(this), namespaceHash, MIGRATION_HEAD_GENESIS, one(address(this), otherNamespaceHash, migrationAHash));
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.PrerequisiteNotApplied.selector, address(this), otherNamespaceHash, migrationAHash
            )
        );
        this.externalApplyMigration(namespace, migrationB, list);
        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationBHash), 0);

        LibMigrationRegistry.applyMigrationV4(
            address(this), otherNamespace, migrationA, one(address(this), otherNamespaceHash, MIGRATION_HEAD_GENESIS)
        );
        LibMigrationRegistry.applyMigrationV4(address(this), namespace, migrationB, list);

        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationBHash), block.timestamp);
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), migrationBHash);
        assertEq(LibMigrationRegistry.headV4(address(this), otherNamespaceHash), migrationAHash);
        assertEq(
            abi.encode(LibMigrationRegistry.appliedAfterV4(address(this), namespaceHash, migrationBHash)), abi.encode(list)
        );
    }

    /// An entry after the head naming the calling contract in the SAME
    /// namespace is refused by the registry, and the refusal arrives
    /// unmodified through both writes.
    function testApplyMigrationOwnLinePrerequisiteReverts(string memory namespace, string memory migration, string memory own) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        bytes32 ownHash = keccak256(bytes(own));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, own);
        deployRegistry();

        Prerequisite[] memory list =
            headThen(address(this), namespaceHash, MIGRATION_HEAD_GENESIS, one(address(this), namespaceHash, ownHash));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.OwnPrerequisite.selector, ownHash));
        this.externalApplyMigration(namespace, migration, list);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.OwnPrerequisite.selector, ownHash));
        this.externalApplyMigrationHistory(namespace, migration, block.timestamp, list);

        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationHash), 0);
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), MIGRATION_HEAD_GENESIS);
    }

    /// The registry's `PrerequisiteNotApplied` reaches the caller unmodified
    /// through both writes, naming the prerequisite, and nothing is recorded.
    function testApplyMigrationPrerequisiteNotApplied(
        address other,
        string memory namespace,
        string memory migration,
        string memory prerequisite
    ) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        bytes32 prerequisiteHash = keccak256(bytes(prerequisite));
        vm.assume(other != address(0));
        vm.assume(other != address(this));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migrationHash != prerequisiteHash);
        deployRegistry();
        Prerequisite[] memory prerequisites =
            headThen(address(this), namespaceHash, MIGRATION_HEAD_GENESIS, one(other, namespaceHash, prerequisiteHash));
        bytes memory err = abi.encodeWithSelector(
            IMigrationRegistryV4.PrerequisiteNotApplied.selector, other, namespaceHash, prerequisiteHash
        );

        vm.expectRevert(err);
        this.externalApplyMigration(namespace, migration, prerequisites);

        vm.expectRevert(err);
        this.externalApplyMigrationHistory(namespace, migration, block.timestamp, prerequisites);

        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationHash), 0);
        assertEq(LibMigrationRegistry.appliedAfterV4(address(this), namespaceHash, migrationHash).length, 0);
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), MIGRATION_HEAD_GENESIS);
    }

    /// A prerequisite that is not a record key is refused by both writes
    /// exactly as `appliedV4` refuses the same key, and nothing is recorded.
    function testApplyMigrationPrerequisiteNotARecordKeyReverts(address other, string memory namespace, string memory migration)
        external
    {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        vm.assume(other != address(0));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        Prerequisite[] memory zeroWriter =
            headThen(address(this), namespaceHash, MIGRATION_HEAD_GENESIS, one(address(0), namespaceHash, migrationHash));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        this.externalApplyMigration(namespace, migration, zeroWriter);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        this.externalApplyMigrationHistory(namespace, migration, block.timestamp, zeroWriter);

        Prerequisite[] memory zeroNamespace =
            headThen(address(this), namespaceHash, MIGRATION_HEAD_GENESIS, one(other, bytes32(0), migrationHash));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        this.externalApplyMigration(namespace, migration, zeroNamespace);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        this.externalApplyMigrationHistory(namespace, migration, block.timestamp, zeroNamespace);

        Prerequisite[] memory zeroMigration =
            headThen(address(this), namespaceHash, MIGRATION_HEAD_GENESIS, one(other, namespaceHash, bytes32(0)));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroMigration.selector));
        this.externalApplyMigration(namespace, migration, zeroMigration);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroMigration.selector));
        this.externalApplyMigrationHistory(namespace, migration, block.timestamp, zeroMigration);

        Prerequisite[] memory genesis =
            headThen(address(this), namespaceHash, MIGRATION_HEAD_GENESIS, one(other, namespaceHash, MIGRATION_HEAD_GENESIS));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.GenesisMigration.selector));
        this.externalApplyMigration(namespace, migration, genesis);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.GenesisMigration.selector));
        this.externalApplyMigrationHistory(namespace, migration, block.timestamp, genesis);

        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationHash), 0);
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), MIGRATION_HEAD_GENESIS);
    }

    /// The registry's zero-writer refusal arrives unmodified through `appliedV4`.
    function testAppliedZeroWriterReverts(bytes32 namespace, bytes32 migration) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        this.externalApplied(address(0), namespace, migration);
    }

    /// The registry's zero-namespace refusal arrives unmodified through
    /// `appliedV4`.
    function testAppliedZeroNamespaceReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        this.externalApplied(writer, bytes32(0), migration);
    }

    /// The registry's zero-id refusal arrives unmodified through `appliedV4`.
    function testAppliedZeroMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroMigration.selector));
        this.externalApplied(writer, namespace, bytes32(0));
    }

    /// The registry's genesis-id refusal arrives unmodified through `appliedV4`.
    function testAppliedGenesisMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.GenesisMigration.selector));
        this.externalApplied(writer, namespace, MIGRATION_HEAD_GENESIS);
    }

    /// The registry's zero-writer refusal arrives unmodified through `headV4`.
    function testHeadZeroWriterReverts(bytes32 namespace) external {
        vm.assume(namespace != bytes32(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        this.externalHead(address(0), namespace);
    }

    /// The registry's zero-namespace refusal arrives unmodified through
    /// `headV4`.
    function testHeadZeroNamespaceReverts(address writer) external {
        vm.assume(writer != address(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        this.externalHead(writer, bytes32(0));
    }

    /// A chain with no registry deployed reverts on the code hash rather than
    /// calling into an empty account, and the point of that is the NAME. An
    /// empty account has no returndata for `abi.decode` to read, so the call
    /// reverts unguarded too — anonymously, saying nothing about whether the
    /// registry is absent or the migration unapplied. Those are different
    /// facts, and this error is what tells them apart. The case that would
    /// answer the lie instead of reverting is occupying code, covered by
    /// `testAppliedWrongCode` and `testAppliedDelegatedCode`.
    function testAppliedNoRegistry(address writer, bytes32 namespace, bytes32 migration) external {
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalApplied(writer, namespace, migration);
    }

    /// A codeless registry address that EXISTS hashes to the empty string, not
    /// to zero, and anyone can bring it into existence on a chain without the
    /// registry by sending it a single wei. The guard fires either way, so what
    /// this pins is the value a caller reading `actualCodeHash` off the revert
    /// is handed.
    function testAppliedNoRegistryFundedAccount(address writer, bytes32 namespace, bytes32 migration, uint256 balance)
        external
    {
        balance = bound(balance, 1, type(uint128).max);
        vm.deal(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, balance);

        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.codehash, keccak256(""));

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                keccak256("")
            )
        );
        this.externalApplied(writer, namespace, migration);
    }

    /// Reading a head off a chain with no registry is refused for the same
    /// reason and with the same named error: an unguarded read reverts here
    /// anyway, because there is no returndata for a `bytes32` to decode from,
    /// so what the check adds is which chain state it was. A head that is not
    /// a head is what occupying code can return, not what an empty one does.
    function testHeadNoRegistry(address writer, bytes32 namespace) external {
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalHead(writer, namespace);
    }

    /// Writing to a chain with no registry is refused by the code hash rather
    /// than by solc's own existence check, which an `applyMigrationV4` into an
    /// empty account hits regardless — no return data is expected, so the
    /// callee is checked to exist and the write reverts unnamed. A migration
    /// that reports itself applied and is not is what a write into occupying
    /// code does, and `testApplyMigrationWrongCode` is where that is covered.
    function testApplyMigrationNoRegistry(string memory namespace, string memory migration, Prerequisite[] memory prerequisites)
        external
    {
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalApplyMigration(namespace, migration, prerequisites);
    }

    /// A chain where ordinary code other than the pinned registry occupies the
    /// address reverts on the code hash, so a migration is never read from code
    /// the caller did not compile against.
    function testAppliedWrongCode(address writer, bytes32 namespace, bytes32 migration, bytes memory code) external {
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
        this.externalApplied(writer, namespace, migration);
    }

    /// The check is on the code HASH, not on how much code is there. Code the
    /// exact length of the registry's own, differing anywhere in it, is refused
    /// exactly as any other occupying code is, naming the hash of what is
    /// actually at the address.
    function testAppliedCodeOfTheRegistrysOwnLength(address writer, bytes32 namespace, bytes32 migration, uint256 index)
        external
    {
        deployRegistry();
        bytes memory code = LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code;
        uint256 length = code.length;
        code[index % length] = ~code[index % length];
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, code);
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, length);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(code)
            )
        );
        this.externalApplied(writer, namespace, migration);
    }

    /// Nor is a head.
    function testHeadWrongCode(address writer, bytes32 namespace, bytes memory code) external {
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
        this.externalHead(writer, namespace);
    }

    /// And never applied into it either. Occupying code is equally free to
    /// answer "applied" to every prerequisite, so the list is fuzzed too.
    function testApplyMigrationWrongCode(
        string memory namespace,
        string memory migration,
        Prerequisite[] memory prerequisites,
        bytes memory code
    ) external {
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
        this.externalApplyMigration(namespace, migration, prerequisites);
    }

    /// A chain where an EOA has DELEGATED the registry address under EIP-7702
    /// is refused on the code hash exactly as ordinary wrong code is. This is
    /// the other way an address gets occupied, and the worse one for a reader:
    /// the account carries 23 bytes of designator while executing whatever the
    /// delegate holds, so an address that looks like nothing at all can answer
    /// `appliedV4` with any timestamp it likes.
    ///
    /// The code hash refuses it without knowing anything about 7702 — a
    /// delegated account hashes its designator and never the delegate's code,
    /// so it can never present the pinned registry's hash.
    /// @param writer The writer a reader would ask about.
    /// @param namespace The line a reader would ask about.
    /// @param migration The migration a reader would ask about.
    /// @param delegate The account the registry address is delegated to.
    function testAppliedDelegatedCode(address writer, bytes32 namespace, bytes32 migration, address delegate) external {
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
        this.externalApplied(writer, namespace, migration);
    }

    /// Nor is a head read out of a delegated account.
    /// @param writer The writer a reader would ask about.
    /// @param namespace The line a reader would ask about.
    /// @param delegate The account the registry address is delegated to.
    function testHeadDelegatedCode(address writer, bytes32 namespace, address delegate) external {
        bytes memory designator = assumedDesignator(delegate);

        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, designator);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(designator)
            )
        );
        this.externalHead(writer, namespace);
    }

    /// And a migration is never applied into one. This is the write, so the
    /// delegate would otherwise be handed a record the writer believes is in
    /// the registry and every later reader asserts against.
    /// @param namespace The line being written.
    /// @param migration The migration being applied.
    /// @param prerequisites The list being named.
    /// @param delegate The account the registry address is delegated to.
    function testApplyMigrationDelegatedCode(
        string memory namespace,
        string memory migration,
        Prerequisite[] memory prerequisites,
        address delegate
    ) external {
        bytes memory designator = assumedDesignator(delegate);

        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, designator);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(designator)
            )
        );
        this.externalApplyMigration(namespace, migration, prerequisites);
    }

    /// A migration recorded with a supplied moment reads back as that moment
    /// through the library, so what `applyMigrationHistoryV4` writes is what
    /// `appliedV4` finds — and it is not the block the write landed in.
    function testApplyMigrationHistoryThenApplied(
        string memory namespace,
        string memory migration,
        uint32 appliedAt,
        uint32 writtenAt
    ) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(appliedAt != 0);
        vm.assume(writtenAt > appliedAt);
        deployRegistry();
        vm.warp(writtenAt);

        LibMigrationRegistry.applyMigrationHistoryV4(
            address(this), namespace, migration, appliedAt, one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS)
        );

        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationHash), appliedAt);
        assertEq(
            abi.encode(LibMigrationRegistry.appliedAfterV4(address(this), namespaceHash, migrationHash)),
            abi.encode(one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS))
        );
    }

    /// `applyMigrationHistoryV4` through the library records the supplied moment
    /// once its prerequisite is applied, and reads the list back as given.
    function testApplyMigrationHistoryWithPrerequisiteThenApplied(
        address other,
        string memory namespace,
        string memory migration,
        string memory prerequisite,
        uint32 appliedAt,
        uint32 blockMoment
    ) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        bytes32 prerequisiteHash = keccak256(bytes(prerequisite));
        vm.assume(other != address(0));
        vm.assume(other != address(this));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(appliedAt != 0);
        vm.assume(blockMoment >= appliedAt);
        vm.warp(blockMoment);
        IMigrationRegistryV4 registry = deployRegistry();
        vm.prank(other);
        registry.applyMigrationV4(other, namespace, prerequisite, one(other, namespaceHash, MIGRATION_HEAD_GENESIS));

        Prerequisite[] memory list =
            headThen(address(this), namespaceHash, MIGRATION_HEAD_GENESIS, one(other, namespaceHash, prerequisiteHash));
        LibMigrationRegistry.applyMigrationHistoryV4(address(this), namespace, migration, appliedAt, list);

        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationHash), appliedAt);
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), migrationHash);
        assertEq(abi.encode(LibMigrationRegistry.appliedAfterV4(address(this), namespaceHash, migrationHash)), abi.encode(list));
    }

    /// A line backfilled in head order keeps every moment it was given, and
    /// the chain reads back as the order it was applied in. This is a consumer
    /// whose migrations ran before this registry reached the chain recording
    /// what actually happened rather than the day it got round to writing it
    /// down.
    function testApplyMigrationHistoryBackfillsASequence(
        string memory namespace,
        string memory migrationA,
        string memory migrationB,
        string memory migrationC
    ) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        bytes32 migrationBHash = keccak256(bytes(migrationB));
        bytes32 migrationCHash = keccak256(bytes(migrationC));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, migrationC);
        vm.assume(migrationAHash != migrationBHash);
        vm.assume(migrationBHash != migrationCHash);
        vm.assume(migrationAHash != migrationCHash);
        deployRegistry();
        vm.warp(9000);

        LibMigrationRegistry.applyMigrationHistoryV4(
            address(this), namespace, migrationA, 1000, one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS)
        );
        LibMigrationRegistry.applyMigrationHistoryV4(
            address(this), namespace, migrationB, 2000, one(address(this), namespaceHash, migrationAHash)
        );
        LibMigrationRegistry.applyMigrationHistoryV4(
            address(this), namespace, migrationC, 3000, one(address(this), namespaceHash, migrationBHash)
        );

        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationAHash), 1000);
        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationBHash), 2000);
        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationCHash), 3000);
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), migrationCHash);

        bytes32 cursor = LibMigrationRegistry.headV4(address(this), namespaceHash);
        cursor = LibMigrationRegistry.appliedOntoV4(address(this), namespaceHash, cursor);
        assertEq(cursor, migrationBHash);
        cursor = LibMigrationRegistry.appliedOntoV4(address(this), namespaceHash, cursor);
        assertEq(cursor, migrationAHash);
        cursor = LibMigrationRegistry.appliedOntoV4(address(this), namespaceHash, cursor);
        assertEq(cursor, MIGRATION_HEAD_GENESIS);
    }

    /// The registry's zero-moment refusal arrives unmodified through
    /// `applyMigrationHistoryV4`, so a consumer that left its `appliedAt`
    /// uninitialised is told so rather than writing a record that reads back as
    /// none.
    function testApplyMigrationHistoryZeroTimestampReverts(string memory namespace, string memory migration) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroTimestamp.selector));
        this.externalApplyMigrationHistory(
            namespace, migration, 0, one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS)
        );
    }

    /// The registry's future-moment refusal arrives unmodified through
    /// `applyMigrationHistoryV4`.
    function testApplyMigrationHistoryFutureTimestampReverts(string memory namespace, string memory migration, uint32 blockMoment)
        external
    {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();
        vm.warp(blockMoment);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.FutureTimestamp.selector, uint256(blockMoment) + 1, uint256(blockMoment)
            )
        );
        this.externalApplyMigrationHistory(
            namespace, migration, uint256(blockMoment) + 1, one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS)
        );
    }

    /// The registry's before-the-head refusal arrives unmodified through
    /// `applyMigrationHistoryV4`, so a consumer backfilling its history out of
    /// order is told which moment it contradicted.
    function testApplyMigrationHistoryTimestampBeforeHeadReverts(
        string memory namespace,
        string memory migrationA,
        string memory migrationB
    ) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        bytes32 migrationBHash = keccak256(bytes(migrationB));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationAHash != migrationBHash);
        deployRegistry();
        vm.warp(9000);

        LibMigrationRegistry.applyMigrationHistoryV4(
            address(this), namespace, migrationA, 2000, one(address(this), namespaceHash, MIGRATION_HEAD_GENESIS)
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.TimestampBeforeHead.selector, 1999, 2000));
        this.externalApplyMigrationHistory(namespace, migrationB, 1999, one(address(this), namespaceHash, migrationAHash));
    }

    /// Naming the calling CONTRACT as the writer of `applyMigrationHistoryV4`
    /// writes its own line, so a consumer backfilling its history writes it
    /// without anyone's approval, and the prerequisite is read from the line it names.
    function testApplyMigrationHistoryLandsUnderTheCallingContract(
        string memory namespace,
        string memory migration,
        string memory prerequisite,
        uint32 appliedAt
    ) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        bytes32 prerequisiteHash = keccak256(bytes(prerequisite));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        // The upstream assertion asks whether `migrationHash` reached its
        // line, which is only a question when it is not the
        // prerequisiteHash that was put there.
        vm.assume(migrationHash != prerequisiteHash);
        vm.assume(appliedAt != 0);
        deployRegistry();
        vm.warp(appliedAt);
        MockMigrationApplier upstream = new MockMigrationApplier();
        MockMigrationApplier applier = new MockMigrationApplier();
        upstream.applyMigrationV4(
            address(upstream), namespace, prerequisite, one(address(upstream), namespaceHash, MIGRATION_HEAD_GENESIS)
        );

        Prerequisite[] memory prerequisites = headThen(
            address(applier), namespaceHash, MIGRATION_HEAD_GENESIS, one(address(upstream), namespaceHash, prerequisiteHash)
        );
        applier.applyMigrationHistoryV4(address(applier), namespace, migration, appliedAt, prerequisites);

        assertEq(LibMigrationRegistry.appliedV4(address(applier), namespaceHash, migrationHash), appliedAt);
        assertEq(LibMigrationRegistry.appliedOntoV4(address(applier), namespaceHash, migrationHash), MIGRATION_HEAD_GENESIS);
        assertEq(LibMigrationRegistry.appliedV4(address(upstream), namespaceHash, migrationHash), 0);
        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationHash), 0);
    }

    /// An unapplied migration answers a zero head, which is the same "no record"
    /// answer `appliedV4` gives as a zero moment.
    function testAppliedOntoUnappliedIsZero(address writer, bytes32 namespace, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        assertEq(LibMigrationRegistry.appliedOntoV4(writer, namespace, migration), bytes32(0));
    }

    /// The registry's zero-writer refusal arrives unmodified through
    /// `appliedOntoV4`.
    function testAppliedOntoZeroWriterReverts(bytes32 namespace, bytes32 migration) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        this.externalAppliedOnto(address(0), namespace, migration);
    }

    /// The registry's zero-namespace refusal arrives unmodified through
    /// `appliedOntoV4`.
    function testAppliedOntoZeroNamespaceReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        this.externalAppliedOnto(writer, bytes32(0), migration);
    }

    /// The registry's zero-id refusal arrives unmodified through `appliedOntoV4`.
    function testAppliedOntoZeroMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroMigration.selector));
        this.externalAppliedOnto(writer, namespace, bytes32(0));
    }

    /// The registry's genesis-id refusal arrives unmodified through
    /// `appliedOntoV4`.
    function testAppliedOntoGenesisMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.GenesisMigration.selector));
        this.externalAppliedOnto(writer, namespace, MIGRATION_HEAD_GENESIS);
    }

    /// Reading a chain step off a chain with no registry is refused by the code
    /// hash, with the same named error as every other read.
    function testAppliedOntoNoRegistry(address writer, bytes32 namespace, bytes32 migration) external {
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalAppliedOnto(writer, namespace, migration);
    }

    /// Nor is a chain step read out of ordinary occupying code, which is free to
    /// answer a head that was never applied and send a walk anywhere it likes.
    function testAppliedOntoWrongCode(address writer, bytes32 namespace, bytes32 migration, bytes memory code)
        external
    {
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
        this.externalAppliedOnto(writer, namespace, migration);
    }

    /// Nor out of a delegated account.
    /// @param writer The writer a reader would ask about.
    /// @param namespace The line a reader would ask about.
    /// @param migration The migration a reader would ask about.
    /// @param delegate The account the registry address is delegated to.
    function testAppliedOntoDelegatedCode(address writer, bytes32 namespace, bytes32 migration, address delegate)
        external
    {
        bytes memory designator = assumedDesignator(delegate);

        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, designator);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(designator)
            )
        );
        this.externalAppliedOnto(writer, namespace, migration);
    }

    /// An unapplied migration answers an empty list, which is the same "no
    /// record" answer `appliedV4` gives as a zero moment: no record was applied
    /// after anything, and every record was applied after its head.
    function testAppliedAfterUnappliedIsEmpty(address writer, bytes32 namespace, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        assertEq(LibMigrationRegistry.appliedAfterV4(writer, namespace, migration).length, 0);
    }

    /// The registry's zero-writer refusal arrives unmodified through
    /// `appliedAfterV4`.
    function testAppliedAfterZeroWriterReverts(bytes32 namespace, bytes32 migration) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        this.externalAppliedAfter(address(0), namespace, migration);
    }

    /// The registry's zero-namespace refusal arrives unmodified through
    /// `appliedAfterV4`.
    function testAppliedAfterZeroNamespaceReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroNamespace.selector));
        this.externalAppliedAfter(writer, bytes32(0), migration);
    }

    /// The registry's zero-id refusal arrives unmodified through
    /// `appliedAfterV4`.
    function testAppliedAfterZeroMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroMigration.selector));
        this.externalAppliedAfter(writer, namespace, bytes32(0));
    }

    /// The registry's genesis-id refusal arrives unmodified through
    /// `appliedAfterV4`.
    function testAppliedAfterGenesisMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.GenesisMigration.selector));
        this.externalAppliedAfter(writer, namespace, MIGRATION_HEAD_GENESIS);
    }

    /// Reading a record's list off a chain with no registry is refused by the
    /// code hash, with the same named error as every other read.
    function testAppliedAfterNoRegistry(address writer, bytes32 namespace, bytes32 migration) external {
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalAppliedAfter(writer, namespace, migration);
    }

    /// Nor is a list read out of ordinary occupying code, which is free to
    /// answer an empty list for every record and read as "never applied".
    function testAppliedAfterWrongCode(address writer, bytes32 namespace, bytes32 migration, bytes memory code)
        external
    {
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
        this.externalAppliedAfter(writer, namespace, migration);
    }

    /// Nor out of a delegated account.
    /// @param writer The writer a reader would ask about.
    /// @param namespace The line a reader would ask about.
    /// @param migration The migration a reader would ask about.
    /// @param delegate The account the registry address is delegated to.
    function testAppliedAfterDelegatedCode(address writer, bytes32 namespace, bytes32 migration, address delegate)
        external
    {
        bytes memory designator = assumedDesignator(delegate);

        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, designator);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(designator)
            )
        );
        this.externalAppliedAfter(writer, namespace, migration);
    }

    /// `applyMigrationHistoryV4` checks the code hash too, so a backfill is never
    /// written to a chain with no registry.
    function testApplyMigrationHistoryNoRegistry(
        string memory namespace,
        string memory migration,
        uint256 appliedAt,
        Prerequisite[] memory prerequisites
    ) external {
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalApplyMigrationHistory(namespace, migration, appliedAt, prerequisites);
    }

    /// Nor into ordinary occupying code.
    function testApplyMigrationHistoryWrongCode(
        string memory namespace,
        string memory migration,
        uint256 appliedAt,
        Prerequisite[] memory prerequisites,
        bytes memory code
    ) external {
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
        this.externalApplyMigrationHistory(namespace, migration, appliedAt, prerequisites);
    }

    /// Nor into a delegated account.
    /// @param namespace The line being written.
    /// @param migration The migration being applied.
    /// @param appliedAt The moment being recorded.
    /// @param prerequisites The list being named.
    /// @param delegate The account the registry address is delegated to.
    function testApplyMigrationHistoryDelegatedCode(
        string memory namespace,
        string memory migration,
        uint256 appliedAt,
        Prerequisite[] memory prerequisites,
        address delegate
    ) external {
        bytes memory designator = assumedDesignator(delegate);

        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, designator);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(designator)
            )
        );
        this.externalApplyMigrationHistory(namespace, migration, appliedAt, prerequisites);
    }

    /// An empty list names no head, so the registry's refusal arrives
    /// unmodified through both writes, naming the zero it was handed, and
    /// nothing is recorded.
    function testApplyMigrationEmptyListReverts(string memory namespace, string memory migration) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.UnexpectedMigrationHead.selector,
                address(this),
                namespaceHash,
                address(0),
                bytes32(0),
                bytes32(0),
                MIGRATION_HEAD_GENESIS
            )
        );
        this.externalApplyMigration(namespace, migration, new Prerequisite[](0));
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.UnexpectedMigrationHead.selector,
                address(this),
                namespaceHash,
                address(0),
                bytes32(0),
                bytes32(0),
                MIGRATION_HEAD_GENESIS
            )
        );
        this.externalApplyMigrationHistory(namespace, migration, block.timestamp, new Prerequisite[](0));

        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationHash), 0);
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), MIGRATION_HEAD_GENESIS);
    }

    /// `appliedAfterV4` through the library is the list the write passed, entry
    /// for entry, on both writes and however long the list is.
    function testAppliedAfterIsTheListPassed(
        string memory namespace,
        string memory migrationA,
        string memory migrationB,
        bytes32[] memory seeds
    ) external {
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        vm.assume(migrationAHash != keccak256(bytes(migrationB)));
        IMigrationRegistryV4 registry = deployRegistry();

        Prerequisite[] memory prerequisites = new Prerequisite[](seeds.length);
        for (uint256 i = 0; i < seeds.length; i++) {
            address writer = address(uint160(uint256(keccak256(abi.encode(seeds[i], "writer")))));
            string memory seedNamespace = vm.toString(keccak256(abi.encode(seeds[i], "namespace")));
            string memory seedMigration = vm.toString(keccak256(abi.encode(seeds[i], "migration")));
            bytes32 seedNamespaceHash = keccak256(bytes(seedNamespace));
            bytes32 seedMigrationHash = keccak256(bytes(seedMigration));
            vm.assume(writer != address(0));
            vm.assume(writer != address(this));
            LibMigrationFuzz.assumeMigration(vm, seedMigration);
            prerequisites[i] = Prerequisite({writer: writer, namespace: seedNamespaceHash, migration: seedMigrationHash});
            // Two seeds may derive one record; it is applied once and listed twice.
            if (registry.appliedV4(writer, seedNamespaceHash, seedMigrationHash) != 0) {
                continue;
            }
            bytes32 head = registry.headV4(writer, seedNamespaceHash);
            vm.prank(writer);
            registry.applyMigrationV4(writer, seedNamespace, seedMigration, one(writer, seedNamespaceHash, head));
        }

        Prerequisite[] memory listA = headThen(address(this), namespaceHash, MIGRATION_HEAD_GENESIS, prerequisites);
        LibMigrationRegistry.applyMigrationV4(address(this), namespace, migrationA, listA);
        assertEq(
            abi.encode(LibMigrationRegistry.appliedAfterV4(address(this), namespaceHash, migrationAHash)),
            abi.encode(listA)
        );

        Prerequisite[] memory listB = headThen(address(this), namespaceHash, migrationAHash, prerequisites);
        LibMigrationRegistry.applyMigrationHistoryV4(address(this), namespace, migrationB, block.timestamp, listB);
        assertEq(
            abi.encode(LibMigrationRegistry.appliedAfterV4(address(this), namespaceHash, keccak256(bytes(migrationB)))),
            abi.encode(listB)
        );
    }

    /// `onto` is one entry, and that entry is exactly the writer, the
    /// namespace and the head it was given, each in its own field. It is
    /// pure, so it answers the same with no registry deployed.
    function testOntoIsTheHeadAlone(address writer, bytes32 namespace, bytes32 headMigration) external pure {
        Prerequisite[] memory prerequisites = LibMigrationRegistry.onto(writer, namespace, headMigration);

        assertEq(prerequisites.length, 1);
        assertEq(prerequisites[0].writer, writer);
        assertEq(prerequisites[0].namespace, namespace);
        assertEq(prerequisites[0].migration, headMigration);
    }

    /// A line written entirely with `onto` lands on a deployed registry, on
    /// both writes: the first migration onto genesis, the next onto the
    /// first. Each record answers the list `onto` built as what it was
    /// applied after, and the head it named as what it was applied onto.
    function testOntoRoundTripsThroughApplyMigration(
        string memory namespace,
        string memory migrationA,
        string memory migrationB,
        uint32 appliedAt
    ) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        bytes32 migrationBHash = keccak256(bytes(migrationB));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationAHash != migrationBHash);
        vm.assume(appliedAt != 0);
        deployRegistry();
        vm.warp(appliedAt);

        Prerequisite[] memory listA = LibMigrationRegistry.onto(address(this), namespaceHash, MIGRATION_HEAD_GENESIS);
        LibMigrationRegistry.applyMigrationV4(address(this), namespace, migrationA, listA);

        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationAHash), appliedAt);
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), migrationAHash);
        assertEq(LibMigrationRegistry.appliedOntoV4(address(this), namespaceHash, migrationAHash), MIGRATION_HEAD_GENESIS);
        assertEq(
            abi.encode(LibMigrationRegistry.appliedAfterV4(address(this), namespaceHash, migrationAHash)), abi.encode(listA)
        );

        Prerequisite[] memory listB = LibMigrationRegistry.onto(address(this), namespaceHash, migrationAHash);
        LibMigrationRegistry.applyMigrationHistoryV4(address(this), namespace, migrationB, appliedAt, listB);

        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationBHash), appliedAt);
        assertEq(LibMigrationRegistry.headV4(address(this), namespaceHash), migrationBHash);
        assertEq(LibMigrationRegistry.appliedOntoV4(address(this), namespaceHash, migrationBHash), migrationAHash);
        assertEq(
            abi.encode(LibMigrationRegistry.appliedAfterV4(address(this), namespaceHash, migrationBHash)), abi.encode(listB)
        );
    }

    /// `onto` a head the line has moved past is refused, naming the head it
    /// gave and the head the line is at: the list carries the script's
    /// belief, and a stale belief fails rather than lands.
    function testOntoStaleHeadIsRefused(string memory namespace, string memory migrationA, string memory migrationB) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        bytes32 migrationBHash = keccak256(bytes(migrationB));
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationAHash != migrationBHash);
        deployRegistry();

        LibMigrationRegistry.applyMigrationV4(
            address(this),
            namespace,
            migrationA,
            LibMigrationRegistry.onto(address(this), namespaceHash, MIGRATION_HEAD_GENESIS)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV4.UnexpectedMigrationHead.selector,
                address(this),
                namespaceHash,
                address(this),
                namespaceHash,
                MIGRATION_HEAD_GENESIS,
                migrationAHash
            )
        );
        this.externalApplyMigration(
            namespace, migrationB, LibMigrationRegistry.onto(address(this), namespaceHash, MIGRATION_HEAD_GENESIS)
        );
        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationBHash), 0);
    }

    /// Finds the one `Migrated` log in `logs` and checks it came from the
    /// registry.
    /// @param logs The recorded logs.
    /// @return The log's data.
    function migratedData(Vm.Log[] memory logs) internal pure returns (bytes memory) {
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(logs[0].topics.length, 1);
        assertEq(logs[0].topics[0], IMigrationRegistryV4.Migrated.selector);
        return logs[0].data;
    }

    /// The strings `Migrated` carries hash to the keys it carries, and those
    /// keys are the ones the record is stored and read under, on both write
    /// paths.
    function testMigratedStringsHashToStoredKeys(
        string memory namespace,
        string memory migrationA,
        string memory migrationB,
        uint32 appliedAt,
        uint32 landedAt
    ) external {
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(keccak256(bytes(migrationA)) != keccak256(bytes(migrationB)));
        vm.assume(appliedAt != 0);
        vm.assume(landedAt >= appliedAt);
        deployRegistry();
        vm.warp(landedAt);

        vm.recordLogs();
        LibMigrationRegistry.applyMigrationHistoryV4(
            address(this), namespace, migrationA, appliedAt, one(address(this), keccak256(bytes(namespace)), MIGRATION_HEAD_GENESIS)
        );
        (
            address sender,
            address writer,
            bytes32 namespaceHash,
            string memory loggedNamespace,
            bytes32 migrationHash,
            string memory loggedMigration,
            uint256 loggedAppliedAt
        ) = abi.decode(
            migratedData(vm.getRecordedLogs()), (address, address, bytes32, string, bytes32, string, uint256)
        );
        assertEq(sender, address(this));
        assertEq(writer, address(this));
        assertEq(loggedNamespace, namespace);
        assertEq(loggedMigration, migrationA);
        assertEq(namespaceHash, keccak256(bytes(loggedNamespace)));
        assertEq(migrationHash, keccak256(bytes(loggedMigration)));
        assertEq(loggedAppliedAt, appliedAt);
        assertEq(LibMigrationRegistry.appliedV4(writer, namespaceHash, migrationHash), appliedAt);
        assertEq(LibMigrationRegistry.headV4(writer, namespaceHash), migrationHash);

        vm.recordLogs();
        LibMigrationRegistry.applyMigrationV4(address(this), namespace, migrationB, one(address(this), namespaceHash, migrationHash));
        bytes32 previous = migrationHash;
        (sender, writer, namespaceHash, loggedNamespace, migrationHash, loggedMigration, loggedAppliedAt) = abi.decode(
            migratedData(vm.getRecordedLogs()), (address, address, bytes32, string, bytes32, string, uint256)
        );
        assertEq(loggedNamespace, namespace);
        assertEq(loggedMigration, migrationB);
        assertEq(namespaceHash, keccak256(bytes(loggedNamespace)));
        assertEq(migrationHash, keccak256(bytes(loggedMigration)));
        assertEq(loggedAppliedAt, landedAt);
        assertEq(LibMigrationRegistry.appliedV4(writer, namespaceHash, migrationHash), landedAt);
        assertEq(LibMigrationRegistry.appliedOntoV4(writer, namespaceHash, migrationHash), previous);
        assertEq(LibMigrationRegistry.headV4(writer, namespaceHash), migrationHash);
    }

    /// An empty namespace is refused before an empty migration, and an empty
    /// migration before the moment, on both write paths.
    function testApplyMigrationEmptyStringsRefusalOrder(string memory namespace) external {
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        bytes32 emptyHash = keccak256("");
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.EmptyNamespace.selector));
        this.externalApplyMigration("", "", one(address(this), emptyHash, MIGRATION_HEAD_GENESIS));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.EmptyNamespace.selector));
        this.externalApplyMigrationHistory("", "", 0, one(address(this), emptyHash, MIGRATION_HEAD_GENESIS));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.EmptyMigration.selector));
        this.externalApplyMigrationHistory(
            namespace, "", 0, one(address(this), keccak256(bytes(namespace)), MIGRATION_HEAD_GENESIS)
        );
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.EmptyNamespace.selector));
        this.externalApplyMigrationHistory(
            "", "rain.migration-registry.head.genesis", 0, new Prerequisite[](0)
        );
    }

    /// The writer and the caller are refused before an empty string is: the
    /// zero writer as `ZeroWriter`, an unapproved caller as `NotApproved`
    /// scoped to the hash of the empty namespace.
    function testApplyMigrationEmptyStringsRefusedAfterTheCaller(address writer) external {
        vm.assume(writer != address(0));
        deployRegistry();
        MockMigrationApplier applier = new MockMigrationApplier();
        vm.assume(writer != address(applier));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        applier.applyMigrationV4(address(0), "", "", new Prerequisite[](0));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV4.ZeroWriter.selector));
        applier.applyMigrationHistoryV4(address(0), "", "", 0, new Prerequisite[](0));

        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, writer, keccak256(""), address(applier))
        );
        applier.applyMigrationV4(writer, "", "", new Prerequisite[](0));
        vm.expectRevert(
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, writer, keccak256(""), address(applier))
        );
        applier.applyMigrationHistoryV4(writer, "", "", 0, new Prerequisite[](0));
    }
}
