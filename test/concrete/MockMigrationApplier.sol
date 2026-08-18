// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibMigrationRegistry} from "../../src/lib/LibMigrationRegistry.sol";

/// @title MockMigrationApplier
/// @notice A consumer in the shape `LibMigrationRegistry.applyMigration` is
/// designed for: it calls the library and nothing else, so the record lands
/// under THIS contract's address.
///
/// It exists so the namespace can be exercised as the property it is. The
/// library's functions are `internal` and inline into whatever executes them,
/// so `msg.sender` at the registry is the calling CONTRACT, not whoever
/// `vm.prank` last named — a test contract calling the library directly can
/// therefore only ever write one namespace. Two of these are two namespaces,
/// which is what makes "a record reaches nobody else" checkable rather than
/// asserted about a single account.
///
/// Two of them are also two heads, which is what makes "one namespace is one
/// sequence" checkable at all: nothing about one applier's head can be shown
/// to leave the other's alone from inside a single namespace.
contract MockMigrationApplier {
    /// Applies `migration` under this contract, onto `expectedHead`.
    /// @param expectedHead The head this contract believes it is at.
    /// @param migration The migration to apply.
    function applyMigration(bytes32 expectedHead, bytes32 migration) external {
        LibMigrationRegistry.applyMigration(expectedHead, migration);
    }

    /// Applies `migration` under this contract, onto `expectedHead`, at
    /// `appliedAt`.
    /// @param expectedHead The head this contract believes it is at.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment the migration was applied.
    function applyMigration(bytes32 expectedHead, bytes32 migration, uint256 appliedAt) external {
        LibMigrationRegistry.applyMigration(expectedHead, migration, appliedAt);
    }

    /// When `writer` applied `migration`.
    /// @param writer The namespace to read.
    /// @param migration The migration to ask about.
    /// @return The moment it was applied at, or zero.
    function applied(address writer, bytes32 migration) external view returns (uint256) {
        return LibMigrationRegistry.applied(writer, migration);
    }

    /// What `writer` applied `migration` onto.
    /// @param writer The namespace to read.
    /// @param migration The migration to ask about.
    /// @return The head it was applied onto, or zero.
    function appliedOnto(address writer, bytes32 migration) external view returns (bytes32) {
        return LibMigrationRegistry.appliedOnto(writer, migration);
    }

    /// The head of `writer`'s namespace.
    /// @param writer The namespace to read.
    /// @return The head.
    function head(address writer) external view returns (bytes32) {
        return LibMigrationRegistry.head(writer);
    }
}
