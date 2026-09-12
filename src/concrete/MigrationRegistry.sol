// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IMigrationRegistryV2, Prerequisite} from "../interface/IMigrationRegistryV2.sol";

/// @title MigrationRegistry
/// @notice The whole of `IMigrationRegistryV2`: a writer applies one of its own
/// migrations after the migrations it names, at the moment it says the
/// migration ran, and anyone reads when a given writer applied a given
/// migration.
///
/// There is deliberately nothing else and nothing configured. `AddressRegistry`
/// has a root welded into its creation code; the account that applies a
/// migration is a different Safe, deployer or timelock for every consumer and
/// every chain, so keying by `msg.sender` removes the authority instead of
/// choosing one and keeps one address for one shared registry.
///
/// The storage mapping is not `public`: `applied` refuses the zero writer and
/// the zero migration, and a generated getter would answer both with zero,
/// which is the silent wrong-branch this contract reverts to prevent.
contract MigrationRegistry is IMigrationRegistryV2 {
    /// Every record, namespaced by writer. Zero means never applied, which no
    /// write records.
    mapping(address writer => mapping(bytes32 migration => uint256 appliedAt)) internal sApplied;

    /// @inheritdoc IMigrationRegistryV2
    // slither-disable-next-line timestamp
    // forge-lint: disable-next-line(block-timestamp)
    function applyMigration(bytes32 migration, Prerequisite[] calldata prerequisites) external {
        writeMigrationRecord(migration, block.timestamp, prerequisites);
    }

    /// @inheritdoc IMigrationRegistryV2
    function applyMigrationHistory(bytes32 migration, uint256 appliedAt, Prerequisite[] calldata prerequisites)
        external
    {
        writeMigrationRecord(migration, appliedAt, prerequisites);
    }

    /// Both writes, so there is one order of refusals and one record whichever
    /// supplied the moment: the arguments that describe the call alone, then
    /// every prerequisite in list order, then the namespace, then the record,
    /// then `Migrated`.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment to record against it.
    /// @param prerequisites The records that must exist for it to be written.
    function writeMigrationRecord(bytes32 migration, uint256 appliedAt, Prerequisite[] calldata prerequisites)
        internal
    {
        if (migration == bytes32(0)) {
            revert ZeroMigration();
        }
        // Reached with a zero `block.timestamp` too: a test can warp to zero
        // and a chain can be configured from a zero genesis. Slither flags a
        // strict equality on anything reaching it from `block.timestamp`, and
        // its timestamp detector attaches to the same line; only one comment
        // fits above the `if`, hence the start/end pair.
        // slither-disable-start timestamp
        // slither-disable-next-line incorrect-equality
        if (appliedAt == 0) {
            revert ZeroTimestamp();
        }
        // slither-disable-end timestamp
        // Vacuous from `applyMigration`. A validator nudging the clock forward
        // admits a record a second earlier, of a migration that has run either
        // way, so the analysers are suppressed on this comparison rather than
        // for the repo; forge-lint has no pair form.
        // slither-disable-start timestamp
        // forge-lint: disable-next-line(block-timestamp)
        if (appliedAt > block.timestamp) {
            revert FutureTimestamp(appliedAt, block.timestamp);
        }
        // slither-disable-end timestamp
        for (uint256 i = 0; i < prerequisites.length; i++) {
            checkRecordKey(prerequisites[i].writer, prerequisites[i].migration);
            if (sApplied[prerequisites[i].writer][prerequisites[i].migration] == 0) {
                revert PrerequisiteNotApplied(prerequisites[i].writer, prerequisites[i].migration);
            }
        }
        if (sApplied[msg.sender][migration] != 0) {
            revert MigrationAlreadyApplied(msg.sender, migration);
        }
        sApplied[msg.sender][migration] = appliedAt;
        emit Migrated(msg.sender, migration, appliedAt, prerequisites);
    }

    /// @inheritdoc IMigrationRegistryV2
    function applied(address writer, bytes32 migration) external view returns (uint256) {
        checkRecordKey(writer, migration);
        return sApplied[writer][migration];
    }

    /// One function, so the reader and the prerequisite check cannot drift
    /// into refusing different keys.
    /// @param writer The namespace being read.
    /// @param migration The migration being asked about.
    function checkRecordKey(address writer, bytes32 migration) internal pure {
        if (writer == address(0)) {
            revert ZeroWriter();
        }
        if (migration == bytes32(0)) {
            revert ZeroMigration();
        }
    }
}
