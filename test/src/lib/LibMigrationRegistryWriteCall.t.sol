// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    IMigrationRegistryV2,
    MIGRATION_HEAD_GENESIS,
    Prerequisite
} from "../../../src/interface/IMigrationRegistryV2.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibAccountCode} from "../../lib/LibAccountCode.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

/// @title LibMigrationRegistryWriteCallTest
/// Tests for `LibMigrationRegistry.applyMigrationCall` and
/// `applyMigrationHistoryCall`: the `(to, data)` a Safe bundle or a timelock
/// batch sends to write a record under the account that executes it.
///
/// The oracle is the real `MigrationRegistry`, deployed through the Zoltu
/// factory at its pinned address. A built call is sent from a pranked account
/// as the low-level call a Safe or a timelock makes, and the record the
/// registry answers afterwards is what the call is judged by, not a re-encoding
/// of it.
contract LibMigrationRegistryWriteCallTest is Test {
    /// Deploys `MigrationRegistry` through the Zoltu factory, which lands it at
    /// the pinned address.
    function deployRegistry() internal {
        LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
    }

    /// An account a Safe or a timelock could be: not zero, and not one of the
    /// accounts this test or the registry occupies.
    /// @param sender The fuzzed candidate.
    function assumeSender(address sender) internal view {
        vm.assume(sender != address(0));
        vm.assume(sender != address(this));
        vm.assume(sender != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        vm.assume(sender != address(vm));
    }

    /// One entry, as a list.
    /// @param writer The entry's writer.
    /// @param namespace The entry's namespace.
    /// @param migration The entry's migration.
    /// @return The one-entry list.
    function one(address writer, bytes32 namespace, bytes32 migration) internal pure returns (Prerequisite[] memory) {
        Prerequisite[] memory prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: writer, namespace: namespace, migration: migration});
        return prerequisites;
    }

    /// Sends `data` to `to` from `sender` as a low-level call, which is how a
    /// Safe executes a bundle entry and a timelock a batch call, and requires
    /// it to succeed.
    /// @param sender The executing account.
    /// @param to The call's target.
    /// @param data The call's data.
    function send(address sender, address to, bytes memory data) internal {
        vm.prank(sender);
        (bool success,) = to.call(data);
        assertTrue(success);
    }

    /// External wrapper for `applyMigrationCall` so that `vm.expectRevert`
    /// works at the correct call depth.
    /// @param namespace The line to apply in.
    /// @param migration The migration to apply.
    /// @param prerequisites The list.
    /// @return The call's target.
    /// @return The call's data.
    function externalApplyMigrationCall(bytes32 namespace, bytes32 migration, Prerequisite[] memory prerequisites)
        external
        view
        returns (address, bytes memory)
    {
        return LibMigrationRegistry.applyMigrationCall(namespace, migration, prerequisites);
    }

    /// External wrapper for `applyMigrationHistoryCall` so that
    /// `vm.expectRevert` works at the correct call depth.
    /// @param namespace The line to apply in.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment to record.
    /// @param prerequisites The list.
    /// @return The call's target.
    /// @return The call's data.
    function externalApplyMigrationHistoryCall(
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] memory prerequisites
    ) external view returns (address, bytes memory) {
        return LibMigrationRegistry.applyMigrationHistoryCall(namespace, migration, appliedAt, prerequisites);
    }

    /// The built call, sent by another account, records the migration under
    /// THAT account, in the namespace named, after the exact list given — a
    /// head entry and a prerequisite in another writer's line — stamped with
    /// the block it lands in. The script that built it is nobody's writer.
    function testApplyMigrationCallLandsUnderTheSender(
        address sender,
        address upstream,
        bytes32 namespace,
        bytes32 upstreamNamespace,
        bytes32 migration,
        bytes32 prerequisite,
        uint32 landedAt
    ) external {
        assumeSender(sender);
        assumeSender(upstream);
        vm.assume(upstream != sender);
        vm.assume(namespace != bytes32(0));
        vm.assume(upstreamNamespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(landedAt != 0);
        deployRegistry();
        vm.warp(landedAt);
        vm.prank(upstream);
        IMigrationRegistryV2(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigration(upstreamNamespace, prerequisite, one(upstream, upstreamNamespace, MIGRATION_HEAD_GENESIS));

        Prerequisite[] memory prerequisites = new Prerequisite[](2);
        prerequisites[0] = Prerequisite({writer: sender, namespace: namespace, migration: MIGRATION_HEAD_GENESIS});
        prerequisites[1] = Prerequisite({writer: upstream, namespace: upstreamNamespace, migration: prerequisite});

        (address to, bytes memory data) = LibMigrationRegistry.applyMigrationCall(namespace, migration, prerequisites);
        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        // Building writes nothing.
        assertEq(LibMigrationRegistry.applied(sender, namespace, migration), 0);

        send(sender, to, data);

        assertEq(LibMigrationRegistry.applied(sender, namespace, migration), landedAt);
        assertEq(LibMigrationRegistry.head(sender, namespace), migration);
        assertEq(LibMigrationRegistry.appliedOnto(sender, namespace, migration), MIGRATION_HEAD_GENESIS);
        assertEq(abi.encode(LibMigrationRegistry.appliedAfter(sender, namespace, migration)), abi.encode(prerequisites));
        assertEq(LibMigrationRegistry.applied(address(this), namespace, migration), 0);
    }

    /// The history call records the moment it was GIVEN, not the block it
    /// landed in, under the account that sent it. The moment is bounded by the
    /// block the write lands in, so a call built before that moment still
    /// lands.
    function testApplyMigrationHistoryCallLandsUnderTheSender(
        address sender,
        bytes32 namespace,
        bytes32 migrationA,
        bytes32 migrationB,
        uint32 builtAt,
        uint32 appliedAt,
        uint32 landedAt
    ) external {
        assumeSender(sender);
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationA != migrationB);
        vm.assume(builtAt != 0);
        vm.assume(appliedAt != 0);
        vm.assume(appliedAt <= landedAt);
        vm.assume(builtAt <= landedAt);
        deployRegistry();
        vm.warp(builtAt);

        (address toA, bytes memory dataA) = LibMigrationRegistry.applyMigrationHistoryCall(
            namespace, migrationA, appliedAt, one(sender, namespace, MIGRATION_HEAD_GENESIS)
        );
        (address toB, bytes memory dataB) = LibMigrationRegistry.applyMigrationHistoryCall(
            namespace, migrationB, appliedAt, one(sender, namespace, migrationA)
        );
        assertEq(toA, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(toB, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);

        vm.warp(landedAt);
        send(sender, toA, dataA);
        send(sender, toB, dataB);

        assertEq(LibMigrationRegistry.applied(sender, namespace, migrationA), appliedAt);
        assertEq(LibMigrationRegistry.applied(sender, namespace, migrationB), appliedAt);
        assertEq(LibMigrationRegistry.head(sender, namespace), migrationB);
        assertEq(LibMigrationRegistry.appliedOnto(sender, namespace, migrationB), migrationA);
        assertEq(
            abi.encode(LibMigrationRegistry.appliedAfter(sender, namespace, migrationB)),
            abi.encode(one(sender, namespace, migrationA))
        );
        assertEq(LibMigrationRegistry.applied(address(this), namespace, migrationA), 0);
    }

    /// A call whose head entry names the account that BUILT it, sent by
    /// another, is refused: the writer is the sender, so the head entry has to
    /// name the Safe or the timelock that will execute it, never the script.
    function testApplyMigrationCallHeadEntryMustNameTheSender(address sender, bytes32 namespace, bytes32 migration)
        external
    {
        assumeSender(sender);
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        (address to, bytes memory data) = LibMigrationRegistry.applyMigrationCall(
            namespace, migration, one(address(this), namespace, MIGRATION_HEAD_GENESIS)
        );

        vm.prank(sender);
        (bool success, bytes memory returnData) = to.call(data);
        assertFalse(success);
        assertEq(
            returnData,
            abi.encodeWithSelector(
                IMigrationRegistryV2.UnexpectedMigrationHead.selector,
                sender,
                namespace,
                namespace,
                MIGRATION_HEAD_GENESIS,
                MIGRATION_HEAD_GENESIS
            )
        );
        assertEq(LibMigrationRegistry.applied(sender, namespace, migration), 0);
        assertEq(LibMigrationRegistry.applied(address(this), namespace, migration), 0);
    }

    /// The hazard the build-time check exists for: a low-level call into an
    /// empty registry address SUCCEEDS, so a bundle executed there records
    /// nothing and reports nothing. Building the call refuses that chain,
    /// naming the empty account's code hash.
    function testApplyMigrationCallNoRegistry(address sender, bytes32 namespace, bytes32 migration) external {
        assumeSender(sender);
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);
        bytes memory data = abi.encodeCall(
            IMigrationRegistryV2.applyMigration, (namespace, migration, one(sender, namespace, MIGRATION_HEAD_GENESIS))
        );
        send(sender, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, data);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalApplyMigrationCall(namespace, migration, one(sender, namespace, MIGRATION_HEAD_GENESIS));
    }

    /// Nor is the history call built for a chain with no registry.
    function testApplyMigrationHistoryCallNoRegistry(
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
        this.externalApplyMigrationHistoryCall(namespace, migration, appliedAt, prerequisites);
    }

    /// Neither call is built for ordinary code other than the pinned registry
    /// at its address, which is free to accept the write and record nothing.
    function testWriteCallsWrongCode(
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] memory prerequisites,
        bytes memory code
    ) external {
        vm.assume(code.length > 0);
        vm.assume(!LibAccountCode.hasDelegationPrefix(code));
        vm.assume(keccak256(code) != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH);
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, code);
        bytes memory expected = abi.encodeWithSelector(
            LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
            keccak256(code)
        );

        vm.expectRevert(expected);
        this.externalApplyMigrationCall(namespace, migration, prerequisites);
        vm.expectRevert(expected);
        this.externalApplyMigrationHistoryCall(namespace, migration, appliedAt, prerequisites);
    }

    /// Nor for an address delegated under EIP-7702, which hashes its designator
    /// and executes whatever the delegate holds.
    function testWriteCallsDelegatedCode(
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] memory prerequisites,
        address delegate
    ) external {
        vm.assume(delegate != address(0));
        bytes memory designator = LibAccountCode.delegationDesignator(delegate);
        vm.etch(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, designator);
        bytes memory expected = abi.encodeWithSelector(
            LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
            keccak256(designator)
        );

        vm.expectRevert(expected);
        this.externalApplyMigrationCall(namespace, migration, prerequisites);
        vm.expectRevert(expected);
        this.externalApplyMigrationHistoryCall(namespace, migration, appliedAt, prerequisites);
    }
}
