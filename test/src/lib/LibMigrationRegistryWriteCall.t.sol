// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {MIGRATION_HEAD_GENESIS, Prerequisite} from "../../../src/interface/IMigrationRegistryV2.sol";
import {IMigrationRegistryV3} from "../../../src/interface/IMigrationRegistryV3.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibAccountCode} from "../../lib/LibAccountCode.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

/// @title LibMigrationRegistryWriteCallTest
/// Tests for `LibMigrationRegistry.applyMigrationV3Call` and
/// `applyMigrationHistoryV3Call`: the `(to, data)` a Safe bundle or a timelock
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

    /// External wrapper for `applyMigrationV3Call` so that `vm.expectRevert`
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
        return LibMigrationRegistry.applyMigrationV3Call(address(this), namespace, migration, prerequisites);
    }

    /// External wrapper for `applyMigrationHistoryV3Call` so that
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
        return LibMigrationRegistry.applyMigrationHistoryV3Call(
            address(this), namespace, migration, appliedAt, prerequisites
        );
    }

    /// The built call, sent by the writer it names, records the migration
    /// under that writer, in the namespace named, after the exact list given —
    /// a head entry and a prerequisite in another writer's line — stamped with
    /// the block it lands in. The script that built it is nobody's writer.
    function testApplyMigrationCallLandsUnderTheWriter(
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
        IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigrationV3(
                upstream,
                upstreamNamespace,
                prerequisite,
                LibMigrationRegistry.onto(upstream, upstreamNamespace, MIGRATION_HEAD_GENESIS)
            );

        Prerequisite[] memory prerequisites = new Prerequisite[](2);
        prerequisites[0] = Prerequisite({writer: sender, namespace: namespace, migration: MIGRATION_HEAD_GENESIS});
        prerequisites[1] = Prerequisite({writer: upstream, namespace: upstreamNamespace, migration: prerequisite});

        (address to, bytes memory data) =
            LibMigrationRegistry.applyMigrationV3Call(sender, namespace, migration, prerequisites);
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
    /// landed in, under the writer it names. The moment is bounded by the
    /// block the write lands in, so a call built before that moment still
    /// lands.
    function testApplyMigrationHistoryCallLandsUnderTheWriter(
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

        Prerequisite[] memory ontoGenesis = LibMigrationRegistry.onto(sender, namespace, MIGRATION_HEAD_GENESIS);
        (address toA, bytes memory dataA) =
            LibMigrationRegistry.applyMigrationHistoryV3Call(sender, namespace, migrationA, appliedAt, ontoGenesis);
        Prerequisite[] memory ontoA = LibMigrationRegistry.onto(sender, namespace, migrationA);
        (address toB, bytes memory dataB) =
            LibMigrationRegistry.applyMigrationHistoryV3Call(sender, namespace, migrationB, appliedAt, ontoA);
        assertEq(toA, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(toB, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);

        vm.warp(landedAt);
        send(sender, toA, dataA);
        send(sender, toB, dataB);

        assertEq(LibMigrationRegistry.applied(sender, namespace, migrationA), appliedAt);
        assertEq(LibMigrationRegistry.applied(sender, namespace, migrationB), appliedAt);
        assertEq(LibMigrationRegistry.head(sender, namespace), migrationB);
        assertEq(LibMigrationRegistry.appliedOnto(sender, namespace, migrationB), migrationA);
        assertEq(abi.encode(LibMigrationRegistry.appliedAfter(sender, namespace, migrationB)), abi.encode(ontoA));
        assertEq(LibMigrationRegistry.applied(address(this), namespace, migrationA), 0);
    }

    /// A call that names the account that BUILT it as the writer, sent by
    /// another, is refused: the script is nobody's writer, and the sender has
    /// no approval for its line.
    function testApplyMigrationCallNamingTheBuilderIsRefused(address sender, bytes32 namespace, bytes32 migration)
        external
    {
        assumeSender(sender);
        vm.assume(namespace != bytes32(0));
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        (address to, bytes memory data) = LibMigrationRegistry.applyMigrationV3Call(
            address(this),
            namespace,
            migration,
            LibMigrationRegistry.onto(address(this), namespace, MIGRATION_HEAD_GENESIS)
        );

        vm.prank(sender);
        (bool success, bytes memory returnData) = to.call(data);
        assertFalse(success);
        assertEq(
            returnData,
            abi.encodeWithSelector(IMigrationRegistryV3.NotApproved.selector, address(this), namespace, sender)
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
            IMigrationRegistryV3.applyMigrationV3,
            (sender, namespace, migration, LibMigrationRegistry.onto(sender, namespace, MIGRATION_HEAD_GENESIS))
        );
        send(sender, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS, data);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalApplyMigrationCall(
            namespace, migration, LibMigrationRegistry.onto(sender, namespace, MIGRATION_HEAD_GENESIS)
        );
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
