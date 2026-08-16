// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibMigrationRegistryV2} from "../../../src/lib/LibMigrationRegistryV2.sol";
import {LibMigrationRegistryV2Deploy} from "../../../src/lib/LibMigrationRegistryV2Deploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {IMigrationRegistryV2, MIGRATION_HEAD_GENESIS} from "../../../src/interface/IMigrationRegistryV2.sol";
import {MigrationRegistryV2} from "../../../src/concrete/MigrationRegistryV2.sol";
import {MockMigrationApplierV2} from "../../concrete/MockMigrationApplierV2.sol";
import {DELEGATION_DESIGNATOR_LENGTH, LibAccountCode} from "../../lib/LibAccountCode.sol";

/// @title LibMigrationRegistryV2Test
/// Tests for `LibMigrationRegistryV2`. The registry is not mocked: the real
/// `MigrationRegistryV2` is deployed through the Zoltu factory, which is what
/// puts it at the pinned address with the pinned code hash, so every test runs
/// against the same bytecode a network would.
///
/// External wrappers are used for the library functions so `vm.expectRevert`
/// lands at the correct call depth.
contract LibMigrationRegistryV2Test is Test {
    /// Deploys `MigrationRegistryV2` through the Zoltu factory, which lands it
    /// at the pinned address.
    /// @return The deployed registry.
    function deployRegistry() internal returns (IMigrationRegistryV2) {
        LibRainDeploy.etchZoltuFactory(vm);
        return IMigrationRegistryV2(LibRainDeploy.deployZoltu(type(MigrationRegistryV2).creationCode));
    }

    /// A migration id that is neither of the two values the head space reserves.
    /// @param migration The fuzzed candidate.
    function assumeMigration(bytes32 migration) internal pure {
        vm.assume(migration != bytes32(0));
        vm.assume(migration != MIGRATION_HEAD_GENESIS);
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
        return LibMigrationRegistryV2.applied(writer, migration);
    }

    /// External wrapper for `head` so that `vm.expectRevert` works at the
    /// correct call depth.
    /// @param writer The namespace to read.
    /// @return The head of that namespace.
    function externalHead(address writer) external view returns (bytes32) {
        return LibMigrationRegistryV2.head(writer);
    }

    /// External wrapper for `applyMigration` so that `vm.expectRevert` works at
    /// the correct call depth.
    /// @param expectedHead The head this contract believes it is at.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment the migration was applied.
    function externalApplyMigration(bytes32 expectedHead, bytes32 migration, uint256 appliedAt) external {
        LibMigrationRegistryV2.applyMigration(expectedHead, migration, appliedAt);
    }

    /// The Zoltu deploy really does land the registry on its pinned address
    /// with its pinned code hash. Every other test here depends on that, and a
    /// pin that had gone stale would otherwise show up as an unrelated
    /// code-hash revert in all of them.
    function testDeployMatchesPins() external {
        deployRegistry();

        assertEq(
            LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_ADDRESS.codehash,
            LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_CODEHASH
        );
    }

    /// This registry is a separate deployment from the one `LibMigrationRegistry`
    /// reads, at its own address, so a consumer's namespace under one says
    /// nothing about its namespace under the other. Two creation codes are two
    /// addresses, which is what makes the two coexist on one chain.
    function testDeployAddressIsItsOwn() external pure {
        assertTrue(
            LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_ADDRESS
                != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS
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

        assertEq(LibMigrationRegistryV2.applied(writer, migration), 0);
    }

    /// An applied migration answers the moment it was given — read back through
    /// the library, so what `applyMigration` writes is what `applied` finds, and
    /// the moment survives the round trip rather than being replaced by the
    /// block the write landed in.
    function testApplyMigrationThenApplied(bytes32 migration, uint32 appliedAt, uint32 writtenAt) external {
        assumeMigration(migration);
        vm.assume(appliedAt != 0);
        vm.assume(writtenAt >= appliedAt);
        deployRegistry();
        vm.warp(writtenAt);

        LibMigrationRegistryV2.applyMigration(MIGRATION_HEAD_GENESIS, migration, appliedAt);

        assertEq(LibMigrationRegistryV2.applied(address(this), migration), appliedAt);
    }

    /// A namespace that has applied nothing reads back as genesis, and each
    /// record moves the head to itself. This is the value the next migration
    /// has to name, so it is read through the library rather than assumed.
    function testHeadFollowsTheRecords(bytes32 migrationA, bytes32 migrationB) external {
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);
        deployRegistry();

        assertEq(LibMigrationRegistryV2.head(address(this)), MIGRATION_HEAD_GENESIS);

        LibMigrationRegistryV2.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, block.timestamp);
        assertEq(LibMigrationRegistryV2.head(address(this)), migrationA);

        LibMigrationRegistryV2.applyMigration(migrationA, migrationB, block.timestamp);
        assertEq(LibMigrationRegistryV2.head(address(this)), migrationB);
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
                IMigrationRegistryV2.UnexpectedMigrationHead.selector, address(this), skipped, MIGRATION_HEAD_GENESIS
            )
        );
        this.externalApplyMigration(skipped, migration, block.timestamp);

        assertEq(LibMigrationRegistryV2.applied(address(this), migration), 0);
    }

    /// The namespace is the CONTRACT that executes the library call. The
    /// library's functions are `internal`, so they inline into their caller and
    /// the registry sees that caller as `msg.sender` — which means a consumer
    /// chooses its namespace by choosing what sends the transaction, and cannot
    /// write anybody else's.
    function testApplyMigrationLandsUnderTheCallingContract(bytes32 migration) external {
        assumeMigration(migration);
        deployRegistry();
        MockMigrationApplierV2 applier = new MockMigrationApplierV2();

        applier.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

        assertEq(LibMigrationRegistryV2.applied(address(applier), migration), block.timestamp);
        assertEq(LibMigrationRegistryV2.applied(address(this), migration), 0);
    }

    /// One caller's record reaches no other namespace, and each answers only
    /// for itself — heads included, so one consumer's sequence neither blocks
    /// nor unblocks another's. This is the whole of the access control: a
    /// reader's choice of writer is the whole of who it trusts.
    function testApplyMigrationDoesNotReachAnotherNamespace(bytes32 migration) external {
        assumeMigration(migration);
        deployRegistry();
        MockMigrationApplierV2 applier = new MockMigrationApplierV2();
        MockMigrationApplierV2 other = new MockMigrationApplierV2();

        applier.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

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

        LibMigrationRegistryV2.applyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.MigrationAlreadyApplied.selector, address(this), migration)
        );
        this.externalApplyMigration(MIGRATION_HEAD_GENESIS, migration, block.timestamp);
    }

    /// The registry's zero-id refusal arrives unmodified through
    /// `applyMigration`.
    function testApplyMigrationZeroMigrationReverts() external {
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        this.externalApplyMigration(MIGRATION_HEAD_GENESIS, bytes32(0), block.timestamp);
    }

    /// The registry's genesis-id refusal arrives unmodified through
    /// `applyMigration`.
    function testApplyMigrationGenesisMigrationReverts() external {
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        this.externalApplyMigration(MIGRATION_HEAD_GENESIS, MIGRATION_HEAD_GENESIS, block.timestamp);
    }

    /// The registry's zero-moment refusal arrives unmodified through
    /// `applyMigration`, so a consumer that left its `appliedAt` uninitialised
    /// is told so rather than writing a record that reads back as none.
    function testApplyMigrationZeroTimestampReverts(bytes32 migration) external {
        assumeMigration(migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroTimestamp.selector));
        this.externalApplyMigration(MIGRATION_HEAD_GENESIS, migration, 0);
    }

    /// The registry's future-moment refusal arrives unmodified through
    /// `applyMigration`.
    function testApplyMigrationFutureTimestampReverts(bytes32 migration, uint32 now_) external {
        assumeMigration(migration);
        deployRegistry();
        vm.warp(now_);

        vm.expectRevert(
            abi.encodeWithSelector(IMigrationRegistryV2.FutureTimestamp.selector, uint256(now_) + 1, uint256(now_))
        );
        this.externalApplyMigration(MIGRATION_HEAD_GENESIS, migration, uint256(now_) + 1);
    }

    /// The registry's before-the-head refusal arrives unmodified through
    /// `applyMigration`.
    function testApplyMigrationTimestampBeforeHeadReverts(bytes32 migrationA, bytes32 migrationB) external {
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        vm.assume(migrationA != migrationB);
        deployRegistry();
        vm.warp(9000);

        LibMigrationRegistryV2.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, 5000);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMigrationRegistryV2.TimestampBeforeHead.selector,
                address(this),
                migrationA,
                uint256(4999),
                uint256(5000)
            )
        );
        this.externalApplyMigration(migrationA, migrationB, 4999);
    }

    /// A namespace backfilled in head order keeps every moment it was given, so
    /// a consumer whose migrations ran before this registry reached the chain
    /// records what actually happened rather than the day it got round to
    /// writing it down.
    function testApplyMigrationBackfillsAHistoricalSequence(bytes32 migrationA, bytes32 migrationB, bytes32 migrationC)
        external
    {
        assumeMigration(migrationA);
        assumeMigration(migrationB);
        assumeMigration(migrationC);
        vm.assume(migrationA != migrationB);
        vm.assume(migrationB != migrationC);
        vm.assume(migrationA != migrationC);
        deployRegistry();
        vm.warp(9000);

        LibMigrationRegistryV2.applyMigration(MIGRATION_HEAD_GENESIS, migrationA, 1000);
        LibMigrationRegistryV2.applyMigration(migrationA, migrationB, 2000);
        LibMigrationRegistryV2.applyMigration(migrationB, migrationC, 3000);

        assertEq(LibMigrationRegistryV2.applied(address(this), migrationA), 1000);
        assertEq(LibMigrationRegistryV2.applied(address(this), migrationB), 2000);
        assertEq(LibMigrationRegistryV2.applied(address(this), migrationC), 3000);
        assertEq(LibMigrationRegistryV2.head(address(this)), migrationC);
    }

    /// The registry's zero-writer refusal arrives unmodified through `applied`.
    function testAppliedZeroWriterReverts(bytes32 migration) external {
        assumeMigration(migration);
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        this.externalApplied(address(0), migration);
    }

    /// The registry's zero-id refusal arrives unmodified through `applied`.
    function testAppliedZeroMigrationReverts(address writer) external {
        vm.assume(writer != address(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroMigration.selector));
        this.externalApplied(writer, bytes32(0));
    }

    /// The registry's genesis-id refusal arrives unmodified through `applied`.
    function testAppliedGenesisMigrationReverts(address writer) external {
        vm.assume(writer != address(0));
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.GenesisMigration.selector));
        this.externalApplied(writer, MIGRATION_HEAD_GENESIS);
    }

    /// The registry's zero-writer refusal arrives unmodified through `head`.
    function testHeadZeroWriterReverts() external {
        deployRegistry();

        vm.expectRevert(abi.encodeWithSelector(IMigrationRegistryV2.ZeroWriter.selector));
        this.externalHead(address(0));
    }

    /// A chain with no registry deployed reverts on the code hash rather than
    /// calling into an empty account. That call would succeed and return
    /// nothing, which `abi.decode` would read as zero — "this migration has
    /// not been applied", on every chain the registry was never deployed to,
    /// which is exactly the silent pre-migration branch this library exists to
    /// make impossible.
    function testAppliedNoRegistry(address writer, bytes32 migration) external {
        assertEq(LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistryV2.UnexpectedMigrationRegistryV2CodeHash.selector,
                LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_CODEHASH,
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
        assertEq(LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistryV2.UnexpectedMigrationRegistryV2CodeHash.selector,
                LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalHead(writer);
    }

    /// Writing to a chain with no registry is refused for the mirror reason: an
    /// `applyMigration` into an empty account is a migration that reports itself
    /// applied and is not, which leaves every reader asserting the
    /// pre-migration state forever.
    function testApplyMigrationNoRegistry(bytes32 expectedHead, bytes32 migration, uint256 appliedAt) external {
        assertEq(LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_ADDRESS.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistryV2.UnexpectedMigrationRegistryV2CodeHash.selector,
                LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalApplyMigration(expectedHead, migration, appliedAt);
    }

    /// A chain where ordinary code other than the pinned registry occupies the
    /// address reverts on the code hash, so a migration is never read from code
    /// the caller did not compile against.
    function testAppliedWrongCode(address writer, bytes32 migration, bytes memory code) external {
        assumeOrdinaryCode(code);
        vm.assume(keccak256(code) != LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_CODEHASH);
        vm.etch(LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_ADDRESS, code);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistryV2.UnexpectedMigrationRegistryV2CodeHash.selector,
                LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_CODEHASH,
                keccak256(code)
            )
        );
        this.externalApplied(writer, migration);
    }

    /// Nor is a head.
    function testHeadWrongCode(address writer, bytes memory code) external {
        assumeOrdinaryCode(code);
        vm.assume(keccak256(code) != LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_CODEHASH);
        vm.etch(LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_ADDRESS, code);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistryV2.UnexpectedMigrationRegistryV2CodeHash.selector,
                LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_CODEHASH,
                keccak256(code)
            )
        );
        this.externalHead(writer);
    }

    /// And never applied into it either.
    function testApplyMigrationWrongCode(bytes32 expectedHead, bytes32 migration, uint256 appliedAt, bytes memory code)
        external
    {
        assumeOrdinaryCode(code);
        vm.assume(keccak256(code) != LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_CODEHASH);
        vm.etch(LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_ADDRESS, code);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistryV2.UnexpectedMigrationRegistryV2CodeHash.selector,
                LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_CODEHASH,
                keccak256(code)
            )
        );
        this.externalApplyMigration(expectedHead, migration, appliedAt);
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

        vm.etch(LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_ADDRESS, designator);
        assertEq(LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_ADDRESS.codehash, keccak256(designator));

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistryV2.UnexpectedMigrationRegistryV2CodeHash.selector,
                LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_CODEHASH,
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

        vm.etch(LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_ADDRESS, designator);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistryV2.UnexpectedMigrationRegistryV2CodeHash.selector,
                LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_CODEHASH,
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
    /// @param appliedAt The moment being recorded.
    /// @param delegate The account the registry address is delegated to.
    function testApplyMigrationDelegatedCode(
        bytes32 expectedHead,
        bytes32 migration,
        uint256 appliedAt,
        address delegate
    ) external {
        bytes memory designator = assumedDesignator(delegate);

        vm.etch(LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_ADDRESS, designator);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistryV2.UnexpectedMigrationRegistryV2CodeHash.selector,
                LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_CODEHASH,
                keccak256(designator)
            )
        );
        this.externalApplyMigration(expectedHead, migration, appliedAt);
    }
}
