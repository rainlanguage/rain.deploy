// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibMigrationRegistry} from "../../src/lib/LibMigrationRegistry.sol";
import {Prerequisite} from "../../src/interface/IMigrationRegistryV5.sol";

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
    /// @param meta Rain metadata the registry emits with the record.
    function applyMigrationV5(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        Prerequisite[] calldata prerequisites,
        bytes calldata meta
    ) external {
        LibMigrationRegistry.applyMigrationV5(writer, namespace, migration, prerequisites, meta);
    }

    /// Applies `migration` in `writer`'s line in `namespace`, at `appliedAt`,
    /// after `prerequisites`.
    /// @param writer The line's writer: this contract or one that approved it.
    /// @param namespace The line to apply in.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment the migration was applied.
    /// @param prerequisites `writer` in `namespace` at the head it is believed
    /// to be at, then the migrations that must already be applied.
    /// @param meta Rain metadata the registry emits with the record.
    function applyMigrationHistoryV5(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] calldata prerequisites,
        bytes calldata meta
    ) external {
        LibMigrationRegistry.applyMigrationHistoryV5(writer, namespace, migration, appliedAt, prerequisites, meta);
    }

    /// Approves `delegate` for this contract's line in `namespace`.
    /// @param namespace The line under this contract.
    /// @param delegate The account to approve.
    function approveV5(bytes32 namespace, address delegate) external {
        LibMigrationRegistry.approveV5(namespace, delegate);
    }

    /// Revokes `delegate` for this contract's line in `namespace`.
    /// @param namespace The line under this contract.
    /// @param delegate The account to revoke.
    function revokeV5(bytes32 namespace, address delegate) external {
        LibMigrationRegistry.revokeV5(namespace, delegate);
    }

    /// When `writer` applied `migration` in `namespace`.
    /// @param writer The writer to read.
    /// @param namespace The line under `writer` to read.
    /// @param migration The migration to ask about.
    /// @return The moment it was applied at, or zero.
    function appliedV5(address writer, bytes32 namespace, bytes32 migration) external view returns (uint256) {
        return LibMigrationRegistry.appliedV5(writer, namespace, migration);
    }

    /// What `writer` applied `migration` onto in `namespace`.
    /// @param writer The writer to read.
    /// @param namespace The line under `writer` to read.
    /// @param migration The migration to ask about.
    /// @return The head it was applied onto, or zero.
    function appliedOntoV5(address writer, bytes32 namespace, bytes32 migration) external view returns (bytes32) {
        return LibMigrationRegistry.appliedOntoV5(writer, namespace, migration);
    }

    /// What `writer` applied `migration` after in `namespace`.
    /// @param writer The writer to read.
    /// @param namespace The line under `writer` to read.
    /// @param migration The migration to ask about.
    /// @return The list the write gave, or empty.
    function appliedAfterV5(address writer, bytes32 namespace, bytes32 migration)
        external
        view
        returns (Prerequisite[] memory)
    {
        return LibMigrationRegistry.appliedAfterV5(writer, namespace, migration);
    }

    /// The head of `writer`'s line in `namespace`.
    /// @param writer The writer to read.
    /// @param namespace The line under `writer` to read.
    /// @return The head.
    function headV5(address writer, bytes32 namespace) external view returns (bytes32) {
        return LibMigrationRegistry.headV5(writer, namespace);
    }
}
