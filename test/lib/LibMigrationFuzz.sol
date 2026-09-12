// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.16.2/src/Vm.sol";

import {Prerequisite} from "../../src/interface/IMigrationRegistryV2.sol";

/// @title LibMigrationFuzz
/// @notice The fuzz domain of a record key, declared once so every migration
/// test in the repo fuzzes the same domain and a change to it is one edit.
library LibMigrationFuzz {
    /// A migration id that is not the one value a migration may never be.
    /// @param vm The `Vm` instance to assume through. Passed rather than
    /// declared here so this library never carries a second definition of the
    /// cheatcode address alongside the one `Test` already gives every caller.
    /// @param migration The fuzzed candidate.
    function assumeMigration(Vm vm, bytes32 migration) internal pure {
        vm.assume(migration != bytes32(0));
    }

    /// A record key: a nonzero writer and a nonzero migration.
    /// @param vm The `Vm` instance to assume through.
    /// @param writer The fuzzed writer.
    /// @param migration The fuzzed migration.
    function assumeKey(Vm vm, address writer, bytes32 migration) internal pure {
        vm.assume(writer != address(0));
        assumeMigration(vm, migration);
    }

    /// One prerequisite, as the list the writes take.
    /// @param writer The prerequisite's namespace.
    /// @param migration The prerequisite's migration.
    /// @return prerequisites The one-entry list.
    function one(address writer, bytes32 migration) internal pure returns (Prerequisite[] memory prerequisites) {
        prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: writer, migration: migration});
    }

    /// Two prerequisites, as a list, in the order given.
    /// @param writerA The first prerequisite's namespace.
    /// @param migrationA The first prerequisite's migration.
    /// @param writerB The second prerequisite's namespace.
    /// @param migrationB The second prerequisite's migration.
    /// @return prerequisites The two-entry list.
    function two(address writerA, bytes32 migrationA, address writerB, bytes32 migrationB)
        internal
        pure
        returns (Prerequisite[] memory prerequisites)
    {
        prerequisites = new Prerequisite[](2);
        prerequisites[0] = Prerequisite({writer: writerA, migration: migrationA});
        prerequisites[1] = Prerequisite({writer: writerB, migration: migrationB});
    }

    /// A list of record keys derived from fuzzed seeds, one key per seed.
    ///
    /// Derived by hashing rather than fuzzed directly because a fuzzed
    /// `Prerequisite[]` of any length carries a zero writer or a zero id in
    /// some entry almost every run, and a list is only usable as applied
    /// prerequisites if every entry is a key. Zero is still refused rather
    /// than mapped around.
    /// @param vm The `Vm` instance to assume through.
    /// @param seeds The fuzzed seeds.
    /// @return prerequisites One key per seed, in seed order.
    function keysFromSeeds(Vm vm, bytes32[] memory seeds) internal pure returns (Prerequisite[] memory prerequisites) {
        prerequisites = new Prerequisite[](seeds.length);
        for (uint256 i = 0; i < seeds.length; i++) {
            prerequisites[i] = Prerequisite({
                writer: address(uint160(uint256(keccak256(abi.encode(seeds[i], "writer"))))),
                migration: keccak256(abi.encode(seeds[i], "migration"))
            });
            assumeKey(vm, prerequisites[i].writer, prerequisites[i].migration);
        }
    }
}
