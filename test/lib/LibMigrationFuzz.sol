// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.16.2/src/Vm.sol";

import {MIGRATION_HEAD_GENESIS} from "../../src/interface/IMigrationRegistryV1.sol";

/// @title LibMigrationFuzz
/// @notice The fuzz domain of a migration id: every `bytes32` except the two
/// the head space reserves.
///
/// The head space is not a second space that happens to overlap this one. A
/// head holds either `MIGRATION_HEAD_GENESIS` or a migration id, and zero is
/// what an uninitialised slot holds, so those two values are the ones a
/// migration id may never be — which makes them the domain boundary of every
/// migration test in the repo rather than a per-test convenience.
///
/// Declared once, so a change to what a head may hold changes what every
/// migration test fuzzes in one edit rather than four.
library LibMigrationFuzz {
    /// A migration id that is neither of the two values the head space reserves,
    /// which is what every test that is not about those values wants.
    /// @param vm The `Vm` instance to assume through. Passed rather than
    /// declared here so this library never carries a second definition of the
    /// cheatcode address alongside the one `Test` already gives every caller.
    /// @param migration The fuzzed candidate.
    function assumeMigration(Vm vm, bytes32 migration) internal pure {
        vm.assume(migration != bytes32(0));
        vm.assume(migration != MIGRATION_HEAD_GENESIS);
    }
}
