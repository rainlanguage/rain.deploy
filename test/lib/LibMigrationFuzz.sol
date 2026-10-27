// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

import {MIGRATION_HEAD_GENESIS} from "../../src/interface/IMigrationRegistryV4.sol";

/// @title LibMigrationFuzz
/// @notice The fuzz domain of a migration: every `bytes32` hash except the two
/// the head space reserves, and every string a write accepts.
///
/// The head space is not a second space that happens to overlap this one. A
/// head holds either `MIGRATION_HEAD_GENESIS` or a migration hash, and zero is
/// what an uninitialised slot holds, so those two values are the ones a
/// migration hash may never be — which makes them the domain boundary of every
/// migration test in the repo rather than a per-test convenience.
///
/// Declared once, so a change to what a head may hold changes what every
/// migration test fuzzes in one edit rather than four.
library LibMigrationFuzz {
    /// A migration hash that is neither of the two values the head space
    /// reserves, which is what every test that is not about those values wants.
    /// @param vm The `Vm` instance to assume through. Passed rather than
    /// declared here so this library never carries a second definition of the
    /// cheatcode address alongside the one `Test` already gives every caller.
    /// @param migrationHash The fuzzed candidate.
    function assumeMigration(Vm vm, bytes32 migrationHash) internal pure {
        vm.assume(migrationHash != bytes32(0));
        vm.assume(migrationHash != MIGRATION_HEAD_GENESIS);
    }

    /// A migration string a write accepts: not empty, and not hashing to either
    /// value the head space reserves.
    /// @param vm The `Vm` instance to assume through.
    /// @param migration The fuzzed candidate.
    function assumeMigration(Vm vm, string memory migration) internal pure {
        vm.assume(bytes(migration).length != 0);
        assumeMigration(vm, keccak256(bytes(migration)));
    }

    /// A namespace string a write accepts: not empty.
    /// @param vm The `Vm` instance to assume through.
    /// @param namespace The fuzzed candidate.
    function assumeNamespace(Vm vm, string memory namespace) internal pure {
        vm.assume(bytes(namespace).length != 0);
    }
}
