// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    IMigrationRegistryV2,
    MIGRATION_HEAD_GENESIS,
    Prerequisite
} from "../../../src/interface/IMigrationRegistryV2.sol";
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
    function deployRegistry() internal returns (IMigrationRegistryV2) {
        LibRainDeploy.etchZoltuFactory(vm);
        return IMigrationRegistryV2(LibRainDeploy.deployZoltu(type(MigrationRegistry).creationCode));
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
    /// @return designator The 23-byte designator.
    function assumedDesignator(address delegate) internal pure returns (bytes memory designator) {
        vm.assume(delegate != address(0));
        designator = LibAccountCode.delegationDesignator(delegate);
    }

    /// External wrapper for `applied` so that `vm.expectRevert` works at the
    /// correct call depth.
    /// @param writer The writer to read.
    /// @param namespace The line under `writer` to read.
    /// @param migration The migration to ask about.
    /// @return When `writer` applied `migration` in `namespace`, or zero.
    function externalApplied(address writer, bytes32 namespace, bytes32 migration) external view returns (uint256) {
        return LibMigrationRegistry.applied(writer, namespace, migration);
    }

    /// External wrapper for `appliedOnto` so that `vm.expectRevert` works at
    /// the correct call depth.
    /// @param writer The writer to read.
    /// @param namespace The line under `writer` to read.
    /// @param migration The migration to ask about.
    /// @return What `writer` applied `migration` onto in `namespace`, or zero.
    function externalAppliedOnto(address writer, bytes32 namespace, bytes32 migration) external view returns (bytes32) {
        return LibMigrationRegistry.appliedOnto(writer, namespace, migration);
    }

    /// External wrapper for `appliedAfter` so that `vm.expectRevert` works at
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
        return LibMigrationRegistry.appliedAfter(writer, namespace, migration);
    }

    /// External wrapper for `head` so that `vm.expectRevert` works at the
    /// correct call depth.
    /// @param writer The writer to read.
    /// @param namespace The line under `writer` to read.
    /// @return The head of that line.
    function externalHead(address writer, bytes32 namespace) external view returns (bytes32) {
        return LibMigrationRegistry.head(writer, namespace);
    }

    /// External wrapper for `applyMigration` so that `vm.expectRevert` works at
    /// the correct call depth.
    /// @param namespace The line to apply in.
    /// @param migration The migration to apply.
    /// @param prerequisites This contract at its head, then the migrations
    /// that must already be applied.
    function externalApplyMigration(bytes32 namespace, bytes32 migration, Prerequisite[] memory prerequisites)
        external
    {
        LibMigrationRegistry.applyMigration(namespace, migration, prerequisites);
    }

    /// External wrapper for `applyMigrationHistory` so that `vm.expectRevert`
    /// works at the correct call depth.
    /// @param namespace The line to apply in.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment to record against it.
    /// @param prerequisites This contract at its head, then the migrations
    /// that must already be applied.
    function externalApplyMigrationHistory(
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] memory prerequisites
    ) external {
        LibMigrationRegistry.applyMigrationHistory(namespace, migration, appliedAt, prerequisites);
    }

    /// One entry, as a list. As the whole list it is a writer at its head in
    /// a namespace, waiting on nothing else.
    /// @param writer The entry's writer.
    /// @param namespace The entry's namespace.
    /// @param migration The entry's migration.
    /// @return prerequisites The one-entry list.
    function one(address writer, bytes32 namespace, bytes32 migration)
        internal
        pure
        returns (Prerequisite[] memory prerequisites)
    {
        prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: writer, namespace: namespace, migration: migration});
    }

    /// The list a write takes: `writer` in `namespace` at `head`, then
    /// `prerequisites`.
    /// @param writer The writer writing.
    /// @param namespace The line it is writing.
    /// @param head The head it believes it is at.
    /// @param prerequisites The migrations that must already be applied.
    /// @return list The list.
    function headThen(address writer, bytes32 namespace, bytes32 head, Prerequisite[] memory prerequisites)
        internal
        pure
        returns (Prerequisite[] memory list)
    {
        list = new Prerequisite[](prerequisites.length + 1);
        list[0] = Prerequisite({writer: writer, namespace: namespace, migration: head});
        for (uint256 i = 0; i < prerequisites.length; i++) {
            list[i + 1] = prerequisites[i];
        }
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

        assertEq(LibMigrationRegistry.applied(writer, namespace, migration), 0);
    }

    /// An applied migration answers the moment it was applied — read back
    /// through the library, so what `applyMigration` writes is what `applied`
    /// finds. The head alone is a migration that waits on nothing else, and
    /// reads back as given. The moment is a whole `uint256` timestamp, so a chain
    /// whose clock is past any narrower bound reads back exactly what it
    /// recorded.
    function testApplyMigrationThenApplied(bytes32 namespace, bytes32 migration, uint64 appliedAt) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(appliedAt != 0);
        deployRegistry();
        vm.warp(appliedAt);

        LibMigrationRegistry.applyMigration(namespace, migration, one(address(this), namespace, MIGRATION_HEAD_GENESIS));

        assertEq(LibMigrationRegistry.applied(address(this), namespace, migration), appliedAt);
        assertEq(
            abi.encode(LibMigrationRegistry.appliedAfter(address(this), namespace, migration)),
            abi.encode(one(address(this), namespace, MIGRATION_HEAD_GENESIS))
        );
    }

    /// A line that has applied nothing reads back as genesis, and each
    /// record moves the head to itself. This is the value the next migration
    /// has to name, so it is read through the library rather than assumed.
    function testHeadFollowsTheRecords(bytes32 namespace, bytes32 migrationA, bytes32 migrationB) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        deployRegistry();

        assertEq(LibMigrationRegistry.head(address(this), namespace), MIGRATION_HEAD_GENESIS);

        LibMigrationRegistry.applyMigration(
            namespace, migrationA, one(address(this), namespace, MIGRATION_HEAD_GENESIS)
        );
        assertEq(LibMigrationRegistry.head(address(this), namespace), migrationA);

        LibMigrationRegistry.applyMigration(namespace, migrationB, one(address(this), namespace, migrationA));
        assertEq(LibMigrationRegistry.head(address(this), namespace), migrationB);
    }

    /// Two lines under one writer have two heads: a record in one leaves the
    /// other at genesis, and each advances on its own records only.
    function testHeadIsPerNamespace(bytes32 namespace, bytes32 otherNamespace, bytes32 migrationA, bytes32 migrationB)
        external
    {
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        deployRegistry();

        LibMigrationRegistry.applyMigration(
            namespace, migrationA, one(address(this), namespace, MIGRATION_HEAD_GENESIS)
        );
        assertEq(LibMigrationRegistry.head(address(this), namespace), migrationA);
        assertEq(LibMigrationRegistry.head(address(this), otherNamespace), MIGRATION_HEAD_GENESIS);

        LibMigrationRegistry.applyMigration(
            otherNamespace, migrationB, one(address(this), otherNamespace, MIGRATION_HEAD_GENESIS)
        );
        assertEq(LibMigrationRegistry.head(address(this), namespace), migrationA);
        assertEq(LibMigrationRegistry.head(address(this), otherNamespace), migrationB);

        LibMigrationRegistry.applyMigration(namespace, migrationB, one(address(this), namespace, migrationA));
        assertEq(LibMigrationRegistry.head(address(this), namespace), migrationB);
        assertEq(LibMigrationRegistry.head(address(this), otherNamespace), migrationB);
        assertEq(LibMigrationRegistry.appliedOnto(address(this), namespace, migrationB), migrationA);
        assertEq(LibMigrationRegistry.appliedOnto(address(this), otherNamespace, migrationB), MIGRATION_HEAD_GENESIS);
    }

    /// A migration applied onto a head this line is not at is refused, and
    /// the registry's own revert arrives unmodified. This is a skipped step
    /// failing at the moment of applying rather than a chain quietly diverging.
    function testApplyMigrationSkippedPredecessorReverts(bytes32 namespace, bytes32 migration, bytes32 skipped)
        external
    {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, skipped);
        deployRegistry();

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                address(this),
                namespace,
                namespace,
                skipped,
                MIGRATION_HEAD_GENESIS
            )
        );
        this.externalApplyMigration(namespace, migration, one(address(this), namespace, skipped));

        assertEq(LibMigrationRegistry.applied(address(this), namespace, migration), 0);
    }

    /// The first entry is the caller's own head in the namespace the write
    /// names, so one naming another writer or another line is refused even
    /// when its migration is exactly the head both lines are at. The list is
    /// passed to the registry as the caller wrote it: nothing here repairs an
    /// entry that names the wrong line into one that names the right one.
    function testApplyMigrationHeadEntryIsTheCallerInTheNamespace(
        address other,
        bytes32 namespace,
        bytes32 otherNamespace,
        bytes32 migration
    ) external {
        vm.assume(other != address(0));
        vm.assume(other != address(this));
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                address(this),
                namespace,
                namespace,
                MIGRATION_HEAD_GENESIS,
                MIGRATION_HEAD_GENESIS
            )
        );
        this.externalApplyMigration(namespace, migration, one(other, namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                address(this),
                namespace,
                otherNamespace,
                MIGRATION_HEAD_GENESIS,
                MIGRATION_HEAD_GENESIS
            )
        );
        this.externalApplyMigration(namespace, migration, one(address(this), otherNamespace, MIGRATION_HEAD_GENESIS));

        assertEq(LibMigrationRegistry.applied(address(this), namespace, migration), 0);
        assertEq(LibMigrationRegistry.head(address(this), namespace), MIGRATION_HEAD_GENESIS);
        assertEq(LibMigrationRegistry.head(other, namespace), MIGRATION_HEAD_GENESIS);
        assertEq(LibMigrationRegistry.head(address(this), otherNamespace), MIGRATION_HEAD_GENESIS);
    }

    /// The writer is the CONTRACT that executes the library call. The
    /// library's functions are `internal`, so they inline into their caller and
    /// the registry sees that caller as `msg.sender` — which means a consumer
    /// chooses its writer by choosing what sends the transaction, and cannot
    /// write anybody else's. The prerequisite is read from whichever line it
    /// names — here another consumer's — and that line is untouched.
    function testApplyMigrationLandsUnderTheCallingContract(bytes32 namespace, bytes32 migration, bytes32 prerequisite)
        external
    {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        // The upstream assertion asks whether `migration` reached its
        // line, which is only a question when it is not the
        // prerequisite that was put there.
        vm.assume(migration != prerequisite);
        deployRegistry();
        MockMigrationApplier upstream = new MockMigrationApplier();
        MockMigrationApplier applier = new MockMigrationApplier();
        upstream.applyMigration(namespace, prerequisite, one(address(upstream), namespace, MIGRATION_HEAD_GENESIS));

        applier.applyMigration(
            namespace,
            migration,
            headThen(
                address(applier), namespace, MIGRATION_HEAD_GENESIS, one(address(upstream), namespace, prerequisite)
            )
        );

        assertEq(LibMigrationRegistry.applied(address(applier), namespace, migration), block.timestamp);
        assertEq(LibMigrationRegistry.appliedOnto(address(applier), namespace, migration), MIGRATION_HEAD_GENESIS);
        assertEq(LibMigrationRegistry.applied(address(upstream), namespace, migration), 0);
        assertEq(LibMigrationRegistry.applied(address(this), namespace, migration), 0);
        assertEq(LibMigrationRegistry.head(address(upstream), namespace), prerequisite);
    }

    /// One caller's record reaches no other writer, and each answers only
    /// for itself — heads included, so one consumer's sequence neither blocks
    /// nor unblocks another's. This is the whole of the access control: a
    /// reader's choice of writer is the whole of who it trusts.
    function testApplyMigrationDoesNotReachAnotherWriter(bytes32 namespace, bytes32 migration) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();
        MockMigrationApplier applier = new MockMigrationApplier();
        MockMigrationApplier other = new MockMigrationApplier();

        applier.applyMigration(namespace, migration, one(address(applier), namespace, MIGRATION_HEAD_GENESIS));

        assertEq(other.applied(address(applier), namespace, migration), block.timestamp);
        assertEq(other.applied(address(other), namespace, migration), 0);
        assertEq(other.head(address(applier), namespace), migration);
        assertEq(other.head(address(other), namespace), MIGRATION_HEAD_GENESIS);
    }

    /// Applying the same migration twice, onto the head it became, is refused,
    /// and the registry's own revert arrives unmodified — the library adds no
    /// handling of its own, so the refusal names the writer, the namespace
    /// and the id.
    function testApplyMigrationTwiceReverts(bytes32 namespace, bytes32 migration) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        LibMigrationRegistry.applyMigration(namespace, migration, one(address(this), namespace, MIGRATION_HEAD_GENESIS));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.MigrationAlreadyApplied.selector, address(this), namespace, migration
            )
        );
        this.externalApplyMigration(namespace, migration, one(address(this), namespace, migration));
    }

    /// The registry's zero-id refusal arrives unmodified through
    /// `applyMigration`.
    function testApplyMigrationZeroMigrationReverts(bytes32 namespace) external {
        vm.assume(namespace != bytes32(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        this.externalApplyMigration(namespace, bytes32(0), one(address(this), namespace, MIGRATION_HEAD_GENESIS));
    }

    /// The registry's genesis-id refusal arrives unmodified through
    /// `applyMigration`.
    function testApplyMigrationGenesisMigrationReverts(bytes32 namespace) external {
        vm.assume(namespace != bytes32(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        this.externalApplyMigration(
            namespace, MIGRATION_HEAD_GENESIS, one(address(this), namespace, MIGRATION_HEAD_GENESIS)
        );
    }

    /// The registry's zero-namespace refusal arrives unmodified through
    /// `applyMigration`, and nothing is recorded in any line.
    function testApplyMigrationZeroNamespaceReverts(bytes32 namespace, bytes32 migration) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        this.externalApplyMigration(bytes32(0), migration, one(address(this), bytes32(0), MIGRATION_HEAD_GENESIS));

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        this.externalApplyMigration(bytes32(0), migration, one(address(this), namespace, MIGRATION_HEAD_GENESIS));

        assertEq(LibMigrationRegistry.applied(address(this), namespace, migration), 0);
        assertEq(LibMigrationRegistry.head(address(this), namespace), MIGRATION_HEAD_GENESIS);
    }

    /// The registry's zero-namespace refusal arrives unmodified through
    /// `applyMigrationHistory`, and nothing is recorded in any line.
    function testApplyMigrationHistoryZeroNamespaceReverts(bytes32 namespace, bytes32 migration, uint32 appliedAt)
        external
    {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(appliedAt != 0);
        deployRegistry();
        vm.warp(appliedAt);

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        this.externalApplyMigrationHistory(
            bytes32(0), migration, appliedAt, one(address(this), bytes32(0), MIGRATION_HEAD_GENESIS)
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        this.externalApplyMigrationHistory(
            bytes32(0), migration, appliedAt, one(address(this), namespace, MIGRATION_HEAD_GENESIS)
        );

        assertEq(LibMigrationRegistry.applied(address(this), namespace, migration), 0);
        assertEq(LibMigrationRegistry.head(address(this), namespace), MIGRATION_HEAD_GENESIS);
    }

    /// `applyMigration` through the library lands the record once its
    /// prerequisite is applied, `applied` reads it back as the block the write
    /// landed in, and `appliedAfter` reads the list back as given.
    function testApplyMigrationWithPrerequisiteThenApplied(
        address other,
        bytes32 namespace,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 now_
    ) external {
        vm.assume(other != address(0));
        vm.assume(other != address(this));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(now_ != 0);
        vm.warp(now_);
        IMigrationRegistryV2 registry = deployRegistry();
        vm.prank(other);
        registry.applyMigration(namespace, prerequisite, one(other, namespace, MIGRATION_HEAD_GENESIS));

        Prerequisite[] memory list =
            headThen(address(this), namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite));
        LibMigrationRegistry.applyMigration(namespace, migration, list);

        assertEq(LibMigrationRegistry.applied(address(this), namespace, migration), now_);
        assertEq(LibMigrationRegistry.appliedOnto(address(this), namespace, migration), MIGRATION_HEAD_GENESIS);
        assertEq(LibMigrationRegistry.head(address(this), namespace), migration);

        assertEq(abi.encode(LibMigrationRegistry.appliedAfter(address(this), namespace, migration)), abi.encode(list));
    }

    /// The calling contract's own other namespace is another line, so a record
    /// in it is a prerequisite like any other writer's: refused by name while
    /// unapplied, then landed and read back as given once applied.
    function testApplyMigrationOwnOtherNamespacePrerequisite(
        bytes32 namespace,
        bytes32 otherNamespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(namespace != bytes32(0));
        vm.assume(otherNamespace != bytes32(0));
        vm.assume(namespace != otherNamespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        deployRegistry();

        Prerequisite[] memory list =
            headThen(address(this), namespace, MIGRATION_HEAD_GENESIS, one(address(this), otherNamespace, migrationA));
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.PrerequisiteNotApplied.selector, address(this), otherNamespace, migrationA
            )
        );
        this.externalApplyMigration(namespace, migrationB, list);
        assertEq(LibMigrationRegistry.applied(address(this), namespace, migrationB), 0);

        LibMigrationRegistry.applyMigration(
            otherNamespace, migrationA, one(address(this), otherNamespace, MIGRATION_HEAD_GENESIS)
        );
        LibMigrationRegistry.applyMigration(namespace, migrationB, list);

        assertEq(LibMigrationRegistry.applied(address(this), namespace, migrationB), block.timestamp);
        assertEq(LibMigrationRegistry.head(address(this), namespace), migrationB);
        assertEq(LibMigrationRegistry.head(address(this), otherNamespace), migrationA);
        assertEq(abi.encode(LibMigrationRegistry.appliedAfter(address(this), namespace, migrationB)), abi.encode(list));
    }

    /// An entry after the head naming the calling contract in the SAME
    /// namespace is refused by the registry, and the refusal arrives
    /// unmodified through both writes.
    function testApplyMigrationOwnLinePrerequisiteReverts(bytes32 namespace, bytes32 migration, bytes32 own) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, own);
        deployRegistry();

        Prerequisite[] memory list =
            headThen(address(this), namespace, MIGRATION_HEAD_GENESIS, one(address(this), namespace, own));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.OwnPrerequisite.selector, own));
        this.externalApplyMigration(namespace, migration, list);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.OwnPrerequisite.selector, own));
        this.externalApplyMigrationHistory(namespace, migration, block.timestamp, list);

        assertEq(LibMigrationRegistry.applied(address(this), namespace, migration), 0);
        assertEq(LibMigrationRegistry.head(address(this), namespace), MIGRATION_HEAD_GENESIS);
    }

    /// The registry's `PrerequisiteNotApplied` reaches the caller unmodified
    /// through both writes, naming the prerequisite, and nothing is recorded.
    function testApplyMigrationPrerequisiteNotApplied(
        address other,
        bytes32 namespace,
        bytes32 migration,
        bytes32 prerequisite
    ) external {
        vm.assume(other != address(0));
        vm.assume(other != address(this));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(migration != prerequisite);
        deployRegistry();

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, namespace, prerequisite)
        );
        this.externalApplyMigration(
            namespace,
            migration,
            headThen(address(this), namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite))
        );

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.PrerequisiteNotApplied.selector, other, namespace, prerequisite)
        );
        this.externalApplyMigrationHistory(
            namespace,
            migration,
            block.timestamp,
            headThen(address(this), namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite))
        );

        assertEq(LibMigrationRegistry.applied(address(this), namespace, migration), 0);
        assertEq(LibMigrationRegistry.appliedAfter(address(this), namespace, migration).length, 0);
        assertEq(LibMigrationRegistry.head(address(this), namespace), MIGRATION_HEAD_GENESIS);
    }

    /// A prerequisite that is not a record key is refused by both writes
    /// exactly as `applied` refuses the same key, and nothing is recorded.
    function testApplyMigrationPrerequisiteNotARecordKeyReverts(address other, bytes32 namespace, bytes32 migration)
        external
    {
        vm.assume(other != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        Prerequisite[] memory zeroWriter =
            headThen(address(this), namespace, MIGRATION_HEAD_GENESIS, one(address(0), namespace, migration));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        this.externalApplyMigration(namespace, migration, zeroWriter);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        this.externalApplyMigrationHistory(namespace, migration, block.timestamp, zeroWriter);

        Prerequisite[] memory zeroNamespace =
            headThen(address(this), namespace, MIGRATION_HEAD_GENESIS, one(other, bytes32(0), migration));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        this.externalApplyMigration(namespace, migration, zeroNamespace);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        this.externalApplyMigrationHistory(namespace, migration, block.timestamp, zeroNamespace);

        Prerequisite[] memory zeroMigration =
            headThen(address(this), namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, bytes32(0)));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        this.externalApplyMigration(namespace, migration, zeroMigration);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        this.externalApplyMigrationHistory(namespace, migration, block.timestamp, zeroMigration);

        Prerequisite[] memory genesis =
            headThen(address(this), namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, MIGRATION_HEAD_GENESIS));
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        this.externalApplyMigration(namespace, migration, genesis);
        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        this.externalApplyMigrationHistory(namespace, migration, block.timestamp, genesis);

        assertEq(LibMigrationRegistry.applied(address(this), namespace, migration), 0);
        assertEq(LibMigrationRegistry.head(address(this), namespace), MIGRATION_HEAD_GENESIS);
    }

    /// The registry's zero-writer refusal arrives unmodified through `applied`.
    function testAppliedZeroWriterReverts(bytes32 namespace, bytes32 migration) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        this.externalApplied(address(0), namespace, migration);
    }

    /// The registry's zero-namespace refusal arrives unmodified through
    /// `applied`.
    function testAppliedZeroNamespaceReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        this.externalApplied(writer, bytes32(0), migration);
    }

    /// The registry's zero-id refusal arrives unmodified through `applied`.
    function testAppliedZeroMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        this.externalApplied(writer, namespace, bytes32(0));
    }

    /// The registry's genesis-id refusal arrives unmodified through `applied`.
    function testAppliedGenesisMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        this.externalApplied(writer, namespace, MIGRATION_HEAD_GENESIS);
    }

    /// The registry's zero-writer refusal arrives unmodified through `head`.
    function testHeadZeroWriterReverts(bytes32 namespace) external {
        vm.assume(namespace != bytes32(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        this.externalHead(address(0), namespace);
    }

    /// The registry's zero-namespace refusal arrives unmodified through
    /// `head`.
    function testHeadZeroNamespaceReverts(address writer) external {
        vm.assume(writer != address(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
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
    /// than by solc's own existence check, which an `applyMigration` into an
    /// empty account hits regardless — no return data is expected, so the
    /// callee is checked to exist and the write reverts unnamed. A migration
    /// that reports itself applied and is not is what a write into occupying
    /// code does, and `testApplyMigrationWrongCode` is where that is covered.
    function testApplyMigrationNoRegistry(bytes32 namespace, bytes32 migration, Prerequisite[] memory prerequisites)
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
        bytes32 namespace,
        bytes32 migration,
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
    /// `applied` with any timestamp it likes.
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
        bytes32 namespace,
        bytes32 migration,
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
    /// through the library, so what `applyMigrationHistory` writes is what
    /// `applied` finds — and it is not the block the write landed in.
    function testApplyMigrationHistoryThenApplied(
        bytes32 namespace,
        bytes32 migration,
        uint32 appliedAt,
        uint32 writtenAt
    ) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        vm.assume(appliedAt != 0);
        vm.assume(writtenAt > appliedAt);
        deployRegistry();
        vm.warp(writtenAt);

        LibMigrationRegistry.applyMigrationHistory(
            namespace, migration, appliedAt, one(address(this), namespace, MIGRATION_HEAD_GENESIS)
        );

        assertEq(LibMigrationRegistry.applied(address(this), namespace, migration), appliedAt);
        assertEq(
            abi.encode(LibMigrationRegistry.appliedAfter(address(this), namespace, migration)),
            abi.encode(one(address(this), namespace, MIGRATION_HEAD_GENESIS))
        );
    }

    /// `applyMigrationHistory` through the library records the supplied moment
    /// once its prerequisite is applied, and reads the list back as given.
    function testApplyMigrationHistoryWithPrerequisiteThenApplied(
        address other,
        bytes32 namespace,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 appliedAt,
        uint32 now_
    ) external {
        vm.assume(other != address(0));
        vm.assume(other != address(this));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(appliedAt != 0);
        vm.assume(now_ >= appliedAt);
        vm.warp(now_);
        IMigrationRegistryV2 registry = deployRegistry();
        vm.prank(other);
        registry.applyMigration(namespace, prerequisite, one(other, namespace, MIGRATION_HEAD_GENESIS));

        Prerequisite[] memory list =
            headThen(address(this), namespace, MIGRATION_HEAD_GENESIS, one(other, namespace, prerequisite));
        LibMigrationRegistry.applyMigrationHistory(namespace, migration, appliedAt, list);

        assertEq(LibMigrationRegistry.applied(address(this), namespace, migration), appliedAt);
        assertEq(LibMigrationRegistry.head(address(this), namespace), migration);
        assertEq(abi.encode(LibMigrationRegistry.appliedAfter(address(this), namespace, migration)), abi.encode(list));
    }

    /// A line backfilled in head order keeps every moment it was given, and
    /// the chain reads back as the order it was applied in. This is a consumer
    /// whose migrations ran before this registry reached the chain recording
    /// what actually happened rather than the day it got round to writing it
    /// down.
    function testApplyMigrationHistoryBackfillsASequence(
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32 migrationC
    ) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        LibMigrationFuzz.assumeMigration(vm, migrationC);
        vm.assume(migrationA != migrationB);
        vm.assume(migrationB != migrationC);
        vm.assume(migrationA != migrationC);
        deployRegistry();
        vm.warp(9000);

        LibMigrationRegistry.applyMigrationHistory(
            namespace, migrationA, 1000, one(address(this), namespace, MIGRATION_HEAD_GENESIS)
        );
        LibMigrationRegistry.applyMigrationHistory(
            namespace, migrationB, 2000, one(address(this), namespace, migrationA)
        );
        LibMigrationRegistry.applyMigrationHistory(
            namespace, migrationC, 3000, one(address(this), namespace, migrationB)
        );

        assertEq(LibMigrationRegistry.applied(address(this), namespace, migrationA), 1000);
        assertEq(LibMigrationRegistry.applied(address(this), namespace, migrationB), 2000);
        assertEq(LibMigrationRegistry.applied(address(this), namespace, migrationC), 3000);
        assertEq(LibMigrationRegistry.head(address(this), namespace), migrationC);

        bytes32 cursor = LibMigrationRegistry.head(address(this), namespace);
        cursor = LibMigrationRegistry.appliedOnto(address(this), namespace, cursor);
        assertEq(cursor, migrationB);
        cursor = LibMigrationRegistry.appliedOnto(address(this), namespace, cursor);
        assertEq(cursor, migrationA);
        cursor = LibMigrationRegistry.appliedOnto(address(this), namespace, cursor);
        assertEq(cursor, MIGRATION_HEAD_GENESIS);
    }

    /// The registry's zero-moment refusal arrives unmodified through
    /// `applyMigrationHistory`, so a consumer that left its `appliedAt`
    /// uninitialised is told so rather than writing a record that reads back as
    /// none.
    function testApplyMigrationHistoryZeroTimestampReverts(bytes32 namespace, bytes32 migration) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        this.externalApplyMigrationHistory(
            namespace, migration, 0, one(address(this), namespace, MIGRATION_HEAD_GENESIS)
        );
    }

    /// The registry's future-moment refusal arrives unmodified through
    /// `applyMigrationHistory`.
    function testApplyMigrationHistoryFutureTimestampReverts(bytes32 namespace, bytes32 migration, uint32 now_)
        external
    {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();
        vm.warp(now_);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, uint256(now_) + 1, uint256(now_))
        );
        this.externalApplyMigrationHistory(
            namespace, migration, uint256(now_) + 1, one(address(this), namespace, MIGRATION_HEAD_GENESIS)
        );
    }

    /// The registry's before-the-head refusal arrives unmodified through
    /// `applyMigrationHistory`, so a consumer backfilling its history out of
    /// order is told which moment it contradicted.
    function testApplyMigrationHistoryTimestampBeforeHeadReverts(
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB
    ) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        deployRegistry();
        vm.warp(9000);

        LibMigrationRegistry.applyMigrationHistory(
            namespace, migrationA, 2000, one(address(this), namespace, MIGRATION_HEAD_GENESIS)
        );

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.TimestampBeforeHead.selector, 1999, 2000));
        this.externalApplyMigrationHistory(namespace, migrationB, 1999, one(address(this), namespace, migrationA));
    }

    /// The writer of `applyMigrationHistory` is the calling CONTRACT too, so
    /// a consumer backfilling its history writes its own line and nobody
    /// else's, and the prerequisite is read from the line it names.
    function testApplyMigrationHistoryLandsUnderTheCallingContract(
        bytes32 namespace,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 appliedAt
    ) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        // The upstream assertion asks whether `migration` reached its
        // line, which is only a question when it is not the
        // prerequisite that was put there.
        vm.assume(migration != prerequisite);
        vm.assume(appliedAt != 0);
        deployRegistry();
        vm.warp(appliedAt);
        MockMigrationApplier upstream = new MockMigrationApplier();
        MockMigrationApplier applier = new MockMigrationApplier();
        upstream.applyMigration(namespace, prerequisite, one(address(upstream), namespace, MIGRATION_HEAD_GENESIS));

        Prerequisite[] memory prerequisites = headThen(
            address(applier), namespace, MIGRATION_HEAD_GENESIS, one(address(upstream), namespace, prerequisite)
        );
        applier.applyMigrationHistory(namespace, migration, appliedAt, prerequisites);

        assertEq(LibMigrationRegistry.applied(address(applier), namespace, migration), appliedAt);
        assertEq(LibMigrationRegistry.appliedOnto(address(applier), namespace, migration), MIGRATION_HEAD_GENESIS);
        assertEq(LibMigrationRegistry.applied(address(upstream), namespace, migration), 0);
        assertEq(LibMigrationRegistry.applied(address(this), namespace, migration), 0);
    }

    /// An unapplied migration answers a zero head, which is the same "no record"
    /// answer `applied` gives as a zero moment.
    function testAppliedOntoUnappliedIsZero(address writer, bytes32 namespace, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        assertEq(LibMigrationRegistry.appliedOnto(writer, namespace, migration), bytes32(0));
    }

    /// The registry's zero-writer refusal arrives unmodified through
    /// `appliedOnto`.
    function testAppliedOntoZeroWriterReverts(bytes32 namespace, bytes32 migration) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        this.externalAppliedOnto(address(0), namespace, migration);
    }

    /// The registry's zero-namespace refusal arrives unmodified through
    /// `appliedOnto`.
    function testAppliedOntoZeroNamespaceReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        this.externalAppliedOnto(writer, bytes32(0), migration);
    }

    /// The registry's zero-id refusal arrives unmodified through `appliedOnto`.
    function testAppliedOntoZeroMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        this.externalAppliedOnto(writer, namespace, bytes32(0));
    }

    /// The registry's genesis-id refusal arrives unmodified through
    /// `appliedOnto`.
    function testAppliedOntoGenesisMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
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
    /// record" answer `applied` gives as a zero moment: no record was applied
    /// after anything, and every record was applied after its head.
    function testAppliedAfterUnappliedIsEmpty(address writer, bytes32 namespace, bytes32 migration) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        assertEq(LibMigrationRegistry.appliedAfter(writer, namespace, migration).length, 0);
    }

    /// The registry's zero-writer refusal arrives unmodified through
    /// `appliedAfter`.
    function testAppliedAfterZeroWriterReverts(bytes32 namespace, bytes32 migration) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        this.externalAppliedAfter(address(0), namespace, migration);
    }

    /// The registry's zero-namespace refusal arrives unmodified through
    /// `appliedAfter`.
    function testAppliedAfterZeroNamespaceReverts(address writer, bytes32 migration) external {
        vm.assume(writer != address(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroNamespace.selector));
        this.externalAppliedAfter(writer, bytes32(0), migration);
    }

    /// The registry's zero-id refusal arrives unmodified through
    /// `appliedAfter`.
    function testAppliedAfterZeroMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        this.externalAppliedAfter(writer, namespace, bytes32(0));
    }

    /// The registry's genesis-id refusal arrives unmodified through
    /// `appliedAfter`.
    function testAppliedAfterGenesisMigrationReverts(address writer, bytes32 namespace) external {
        vm.assume(writer != address(0));
        vm.assume(namespace != bytes32(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
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

    /// `applyMigrationHistory` checks the code hash too, so a backfill is never
    /// written to a chain with no registry.
    function testApplyMigrationHistoryNoRegistry(
        bytes32 namespace,
        bytes32 migration,
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
        bytes32 namespace,
        bytes32 migration,
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
        bytes32 namespace,
        bytes32 migration,
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
    function testApplyMigrationEmptyListReverts(bytes32 namespace, bytes32 migration) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                address(this),
                namespace,
                bytes32(0),
                bytes32(0),
                MIGRATION_HEAD_GENESIS
            )
        );
        this.externalApplyMigration(namespace, migration, new Prerequisite[](0));
        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                address(this),
                namespace,
                bytes32(0),
                bytes32(0),
                MIGRATION_HEAD_GENESIS
            )
        );
        this.externalApplyMigrationHistory(namespace, migration, block.timestamp, new Prerequisite[](0));

        assertEq(LibMigrationRegistry.applied(address(this), namespace, migration), 0);
        assertEq(LibMigrationRegistry.head(address(this), namespace), MIGRATION_HEAD_GENESIS);
    }

    /// `appliedAfter` through the library is the list the write passed, entry
    /// for entry, on both writes and however long the list is.
    function testAppliedAfterIsTheListPassed(
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        bytes32[] memory seeds
    ) external {
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        IMigrationRegistryV2 registry = deployRegistry();

        Prerequisite[] memory prerequisites = new Prerequisite[](seeds.length);
        for (uint256 i = 0; i < seeds.length; i++) {
            address writer = address(uint160(uint256(keccak256(abi.encode(seeds[i], "writer")))));
            bytes32 seedNamespace = keccak256(abi.encode(seeds[i], "namespace"));
            bytes32 migration = keccak256(abi.encode(seeds[i], "migration"));
            vm.assume(writer != address(0));
            vm.assume(writer != address(this));
            vm.assume(seedNamespace != bytes32(0));
            LibMigrationFuzz.assumeMigration(vm, migration);
            prerequisites[i] = Prerequisite({writer: writer, namespace: seedNamespace, migration: migration});
            // Two seeds may derive one record; it is applied once and listed twice.
            if (registry.applied(writer, seedNamespace, migration) != 0) {
                continue;
            }
            bytes32 head = registry.head(writer, seedNamespace);
            vm.prank(writer);
            registry.applyMigration(seedNamespace, migration, one(writer, seedNamespace, head));
        }

        Prerequisite[] memory listA = headThen(address(this), namespace, MIGRATION_HEAD_GENESIS, prerequisites);
        LibMigrationRegistry.applyMigration(namespace, migrationA, listA);
        assertEq(abi.encode(LibMigrationRegistry.appliedAfter(address(this), namespace, migrationA)), abi.encode(listA));

        Prerequisite[] memory listB = headThen(address(this), namespace, migrationA, prerequisites);
        LibMigrationRegistry.applyMigrationHistory(namespace, migrationB, block.timestamp, listB);
        assertEq(abi.encode(LibMigrationRegistry.appliedAfter(address(this), namespace, migrationB)), abi.encode(listB));
    }
}
