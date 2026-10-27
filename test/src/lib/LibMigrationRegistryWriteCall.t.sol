// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IRegistryDelegatesV1} from "../../../src/interface/IRegistryDelegatesV1.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    IMigrationRegistryV4,
    MIGRATION_HEAD_GENESIS,
    Prerequisite
} from "../../../src/interface/IMigrationRegistryV4.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {LibAccountCode} from "../../lib/LibAccountCode.sol";
import {LibMigrationFuzz} from "../../lib/LibMigrationFuzz.sol";

/// @title LibMigrationRegistryWriteCallTest
/// Tests for `LibMigrationRegistry.applyMigrationV4Call` and
/// `applyMigrationHistoryV4Call`: the `(to, data)` a Safe bundle or a timelock
/// batch sends to write a record into the writer it names, by the account
/// that executes it.
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

    /// External wrapper for `applyMigrationV4Call` so that `vm.expectRevert`
    /// works at the correct call depth.
    /// @param namespace The line to apply in.
    /// @param migration The migration to apply.
    /// @param prerequisites The list.
    /// @return The call's target.
    /// @return The call's data.
    function externalApplyMigrationCall(string memory namespace, string memory migration, Prerequisite[] memory prerequisites)
        external
        view
        returns (address, bytes memory)
    {
        return LibMigrationRegistry.applyMigrationV4Call(address(this), namespace, migration, prerequisites);
    }

    /// External wrapper for `applyMigrationHistoryV4Call` so that
    /// `vm.expectRevert` works at the correct call depth.
    /// @param namespace The line to apply in.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment to record.
    /// @param prerequisites The list.
    /// @return The call's target.
    /// @return The call's data.
    function externalApplyMigrationHistoryCall(
        string memory namespace,
        string memory migration,
        uint256 appliedAt,
        Prerequisite[] memory prerequisites
    ) external view returns (address, bytes memory) {
        return LibMigrationRegistry.applyMigrationHistoryV4Call(
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
        string memory namespace,
        string memory upstreamNamespace,
        string memory migration,
        string memory prerequisite,
        uint32 landedAt
    ) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 upstreamNamespaceHash = keccak256(bytes(upstreamNamespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        bytes32 prerequisiteHash = keccak256(bytes(prerequisite));
        assumeSender(sender);
        assumeSender(upstream);
        vm.assume(upstream != sender);
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeNamespace(vm, upstreamNamespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        LibMigrationFuzz.assumeMigration(vm, prerequisite);
        vm.assume(landedAt != 0);
        deployRegistry();
        vm.warp(landedAt);
        vm.prank(upstream);
        IMigrationRegistryV4(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigrationV4(
                upstream,
                upstreamNamespace,
                prerequisite,
                LibMigrationRegistry.onto(upstream, upstreamNamespaceHash, MIGRATION_HEAD_GENESIS)
            );

        Prerequisite[] memory prerequisites = new Prerequisite[](2);
        prerequisites[0] = Prerequisite({writer: sender, namespace: namespaceHash, migration: MIGRATION_HEAD_GENESIS});
        prerequisites[1] = Prerequisite({writer: upstream, namespace: upstreamNamespaceHash, migration: prerequisiteHash});

        (address to, bytes memory data) =
            LibMigrationRegistry.applyMigrationV4Call(sender, namespace, migration, prerequisites);
        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        // Building writes nothing.
        assertEq(LibMigrationRegistry.appliedV4(sender, namespaceHash, migrationHash), 0);

        send(sender, to, data);

        assertEq(LibMigrationRegistry.appliedV4(sender, namespaceHash, migrationHash), landedAt);
        assertEq(LibMigrationRegistry.headV4(sender, namespaceHash), migrationHash);
        assertEq(LibMigrationRegistry.appliedOntoV4(sender, namespaceHash, migrationHash), MIGRATION_HEAD_GENESIS);
        assertEq(
            abi.encode(LibMigrationRegistry.appliedAfterV4(sender, namespaceHash, migrationHash)), abi.encode(prerequisites)
        );
        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationHash), 0);
    }

    /// The history call records the moment it was GIVEN, not the block it
    /// landed in, under the writer it names. The moment is bounded by the
    /// block the write lands in, so a call built before that moment still
    /// lands.
    function testApplyMigrationHistoryCallLandsUnderTheWriter(
        address sender,
        string memory namespace,
        string memory migrationA,
        string memory migrationB,
        uint32 builtAt,
        uint32 appliedAt,
        uint32 landedAt
    ) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationAHash = keccak256(bytes(migrationA));
        bytes32 migrationBHash = keccak256(bytes(migrationB));
        assumeSender(sender);
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migrationA);
        LibMigrationFuzz.assumeMigration(vm, migrationB);
        vm.assume(migrationAHash != migrationBHash);
        vm.assume(builtAt != 0);
        vm.assume(appliedAt != 0);
        vm.assume(appliedAt <= landedAt);
        vm.assume(builtAt <= landedAt);
        deployRegistry();
        vm.warp(builtAt);

        Prerequisite[] memory ontoGenesis = LibMigrationRegistry.onto(sender, namespaceHash, MIGRATION_HEAD_GENESIS);
        (address toA, bytes memory dataA) =
            LibMigrationRegistry.applyMigrationHistoryV4Call(sender, namespace, migrationA, appliedAt, ontoGenesis);
        Prerequisite[] memory ontoA = LibMigrationRegistry.onto(sender, namespaceHash, migrationAHash);
        (address toB, bytes memory dataB) =
            LibMigrationRegistry.applyMigrationHistoryV4Call(sender, namespace, migrationB, appliedAt, ontoA);
        assertEq(toA, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(toB, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);

        vm.warp(landedAt);
        send(sender, toA, dataA);
        send(sender, toB, dataB);

        assertEq(LibMigrationRegistry.appliedV4(sender, namespaceHash, migrationAHash), appliedAt);
        assertEq(LibMigrationRegistry.appliedV4(sender, namespaceHash, migrationBHash), appliedAt);
        assertEq(LibMigrationRegistry.headV4(sender, namespaceHash), migrationBHash);
        assertEq(LibMigrationRegistry.appliedOntoV4(sender, namespaceHash, migrationBHash), migrationAHash);
        assertEq(abi.encode(LibMigrationRegistry.appliedAfterV4(sender, namespaceHash, migrationBHash)), abi.encode(ontoA));
        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationAHash), 0);
    }

    /// A call that names the account that BUILT it as the writer, sent by
    /// another, is refused: the script is nobody's writer, and the sender has
    /// no approval for its line.
    function testApplyMigrationCallNamingTheBuilderIsRefused(address sender, string memory namespace, string memory migration)
        external
    {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        bytes32 migrationHash = keccak256(bytes(migration));
        assumeSender(sender);
        LibMigrationFuzz.assumeNamespace(vm, namespace);
        LibMigrationFuzz.assumeMigration(vm, migration);
        deployRegistry();

        (address to, bytes memory data) = LibMigrationRegistry.applyMigrationV4Call(
            address(this),
            namespace,
            migration,
            LibMigrationRegistry.onto(address(this), namespaceHash, MIGRATION_HEAD_GENESIS)
        );

        vm.prank(sender);
        (bool success, bytes memory returnData) = to.call(data);
        assertFalse(success);
        assertEq(
            returnData,
            abi.encodeWithSelector(IRegistryDelegatesV1.NotApproved.selector, address(this), namespaceHash, sender)
        );
        assertEq(LibMigrationRegistry.appliedV4(sender, namespaceHash, migrationHash), 0);
        assertEq(LibMigrationRegistry.appliedV4(address(this), namespaceHash, migrationHash), 0);
    }

    /// The hazard the build-time check exists for: a low-level call into an
    /// empty registry address SUCCEEDS, so a bundle executed there records
    /// nothing and reports nothing. Building the call refuses that chain,
    /// naming the empty account's code hash.
    function testApplyMigrationCallNoRegistry(address sender, string memory namespace, string memory migration) external {
        bytes32 namespaceHash = keccak256(bytes(namespace));
        assumeSender(sender);
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);
        bytes memory data = abi.encodeCall(
            IMigrationRegistryV4.applyMigrationV4,
            (sender, namespace, migration, LibMigrationRegistry.onto(sender, namespaceHash, MIGRATION_HEAD_GENESIS))
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
            namespace, migration, LibMigrationRegistry.onto(sender, namespaceHash, MIGRATION_HEAD_GENESIS)
        );
    }

    /// Nor is the history call built for a chain with no registry.
    function testApplyMigrationHistoryCallNoRegistry(
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
        this.externalApplyMigrationHistoryCall(namespace, migration, appliedAt, prerequisites);
    }

    /// Neither call is built for ordinary code other than the pinned registry
    /// at its address, which is free to accept the write and record nothing.
    function testWriteCallsWrongCode(
        string memory namespace,
        string memory migration,
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
        string memory namespace,
        string memory migration,
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
