// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibMigrationRegistry} from "../../src/lib/LibMigrationRegistry.sol";
import {Prerequisite} from "../../src/interface/IMigrationRegistryV4.sol";

/// @title MockMigrationApplier
/// @notice A consumer in the shape `LibMigrationRegistry`'s writes are designed
/// for: it calls the library and nothing else, so the call reaches the registry
/// from THIS contract, and the record lands under the `writer` it names,
/// written by this contract.
///
/// It exists so the writer can be exercised as the property it is. The
/// library's functions are `internal` and inline into whatever executes them,
/// so `msg.sender` at the registry is this CONTRACT, whoever called it. Two of
/// these, each naming itself, are two writers, which is what makes "a record
/// reaches nobody else" checkable rather than asserted about a single account.
///
/// Two of them are also two sets of heads, which is what makes "one line is
/// one sequence" checkable across writers at all: nothing about one applier's
/// heads can be shown to leave the other's alone from inside a single writer.
contract MockMigrationApplier {
    /// Applies `migration` in `writer`'s line in `namespace`, after
    /// `prerequisites`.
    /// @param writer The line's writer: this contract or one that approved it.
    /// @param namespace The line to apply in.
    /// @param migration The migration to apply.
    /// @param prerequisites `writer` in `namespace` at the head it is believed
    /// to be at, then the migrations that must already be applied.
    function applyMigrationV4(
        address writer,
        string calldata namespace,
        string calldata migration,
        Prerequisite[] calldata prerequisites
    ) external {
        LibMigrationRegistry.applyMigrationV4(writer, namespace, migration, prerequisites);
    }

    /// Applies `migration` in `writer`'s line in `namespace`, at `appliedAt`,
    /// after `prerequisites`.
    /// @param writer The line's writer: this contract or one that approved it.
    /// @param namespace The line to apply in.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment the migration was applied.
    /// @param prerequisites `writer` in `namespace` at the head it is believed
    /// to be at, then the migrations that must already be applied.
    function applyMigrationHistoryV4(
        address writer,
        string calldata namespace,
        string calldata migration,
        uint256 appliedAt,
        Prerequisite[] calldata prerequisites
    ) external {
        LibMigrationRegistry.applyMigrationHistoryV4(writer, namespace, migration, appliedAt, prerequisites);
    }

    /// Approves `delegate` for this contract's line in `namespaceHash`.
    /// @param namespaceHash The line under this contract.
    /// @param delegate The account to approve.
    function approveV3(bytes32 namespaceHash, address delegate) external {
        LibMigrationRegistry.approveV3(namespaceHash, delegate);
    }

    /// Revokes `delegate` for this contract's line in `namespaceHash`.
    /// @param namespaceHash The line under this contract.
    /// @param delegate The account to revoke.
    function revokeV3(bytes32 namespaceHash, address delegate) external {
        LibMigrationRegistry.revokeV3(namespaceHash, delegate);
    }

    /// When `writer` applied `migrationHash` in `namespaceHash`.
    /// @param writer The writer to read.
    /// @param namespaceHash The line under `writer` to read.
    /// @param migrationHash The migration to ask about.
    /// @return The moment it was applied at, or zero.
    function appliedV4(address writer, bytes32 namespaceHash, bytes32 migrationHash) external view returns (uint256) {
        return LibMigrationRegistry.appliedV4(writer, namespaceHash, migrationHash);
    }

    /// What `writer` applied `migrationHash` onto in `namespaceHash`.
    /// @param writer The writer to read.
    /// @param namespaceHash The line under `writer` to read.
    /// @param migrationHash The migration to ask about.
    /// @return The head it was applied onto, or zero.
    function appliedOntoV4(address writer, bytes32 namespaceHash, bytes32 migrationHash)
        external
        view
        returns (bytes32)
    {
        return LibMigrationRegistry.appliedOntoV4(writer, namespaceHash, migrationHash);
    }

    /// What `writer` applied `migrationHash` after in `namespaceHash`.
    /// @param writer The writer to read.
    /// @param namespaceHash The line under `writer` to read.
    /// @param migrationHash The migration to ask about.
    /// @return The list the write gave, or empty.
    function appliedAfterV4(address writer, bytes32 namespaceHash, bytes32 migrationHash)
        external
        view
        returns (Prerequisite[] memory)
    {
        return LibMigrationRegistry.appliedAfterV4(writer, namespaceHash, migrationHash);
    }

    /// The head of `writer`'s line in `namespaceHash`.
    /// @param writer The writer to read.
    /// @param namespaceHash The line under `writer` to read.
    /// @return The head.
    function headV4(address writer, bytes32 namespaceHash) external view returns (bytes32) {
        return LibMigrationRegistry.headV4(writer, namespaceHash);
    }
}
