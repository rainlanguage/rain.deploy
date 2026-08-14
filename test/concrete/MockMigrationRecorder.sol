// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibMigrationRegistry} from "../../src/lib/LibMigrationRegistry.sol";

/// @title MockMigrationRecorder
/// @notice A consumer in the shape `LibMigrationRegistry.record` is designed
/// for: it calls the library and nothing else, so the record lands under THIS
/// contract's address.
///
/// It exists so the namespace can be exercised as the property it is. The
/// library's functions are `internal` and inline into whatever executes them,
/// so `msg.sender` at the registry is the calling CONTRACT, not whoever
/// `vm.prank` last named — a test contract calling the library directly can
/// therefore only ever write one namespace. Two of these are two namespaces,
/// which is what makes "a record reaches nobody else" checkable rather than
/// asserted about a single account.
contract MockMigrationRecorder {
    /// Records `migration` under this contract.
    /// @param migration The migration to record.
    function record(bytes32 migration) external {
        LibMigrationRegistry.record(migration);
    }

    /// Whether `writer` has recorded `migration`.
    /// @param writer The namespace to read.
    /// @param migration The migration to ask about.
    /// @return Whether it is recorded.
    function applied(address writer, bytes32 migration) external view returns (bool) {
        return LibMigrationRegistry.applied(writer, migration);
    }
}
