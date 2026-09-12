// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibMigrationRegistry} from "../../src/lib/LibMigrationRegistry.sol";
import {Prerequisite} from "../../src/interface/IMigrationRegistryV1.sol";

/// @title MockMigrationApplier
/// @notice A consumer in the shape `LibMigrationRegistry`'s writes are designed
/// for: it calls the library and nothing else, so the record lands under THIS
/// contract's address.
///
/// The library's functions are `internal` and inline into whatever executes
/// them, so `msg.sender` at the registry is the calling CONTRACT, not whoever
/// `vm.prank` last named — a test contract calling the library directly can
/// only ever write one namespace. Two of these are two namespaces, which is
/// what makes "a record reaches nobody else" checkable.
contract MockMigrationApplier {
    /// Applies `migration` under this contract, after `prerequisites`.
    /// @param migration The migration to apply.
    /// @param prerequisites The migrations that must already be applied.
    function applyMigration(bytes32 migration, Prerequisite[] calldata prerequisites) external {
        LibMigrationRegistry.applyMigration(migration, prerequisites);
    }

    /// Applies `migration` under this contract, after `prerequisites`, at
    /// `appliedAt`.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment the migration was applied.
    /// @param prerequisites The migrations that must already be applied.
    function applyMigrationHistory(bytes32 migration, uint256 appliedAt, Prerequisite[] calldata prerequisites)
        external
    {
        LibMigrationRegistry.applyMigrationHistory(migration, appliedAt, prerequisites);
    }

    /// When `writer` applied `migration`.
    /// @param writer The namespace to read.
    /// @param migration The migration to ask about.
    /// @return The moment it was applied at, or zero.
    function applied(address writer, bytes32 migration) external view returns (uint256) {
        return LibMigrationRegistry.applied(writer, migration);
    }

    /// The prerequisites `writer` named for `migration`.
    /// @param writer The namespace to read.
    /// @param migration The migration to ask about.
    /// @return The list as written.
    function prerequisites(address writer, bytes32 migration) external view returns (Prerequisite[] memory) {
        return LibMigrationRegistry.prerequisites(writer, migration);
    }
}
