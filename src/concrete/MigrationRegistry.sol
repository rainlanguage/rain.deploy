// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IMigrationRegistryV1} from "../interface/IMigrationRegistryV1.sol";

/// @title MigrationRegistry
/// @notice The whole of `IMigrationRegistryV1`: a writer records one of its own
/// migrations, and anyone reads whether a given writer has recorded a given
/// migration.
///
/// There is deliberately nothing else. No removal, no upgrade, no pause, and no
/// authority at all — which is the difference from `AddressRegistry`, and the
/// reason this contract has no compile-time constant of any kind.
///
/// `AddressRegistry` has a root, and a root has to be welded into the creation
/// code so it cannot be rotated, which puts it in the deterministic address.
/// That is workable there because there is one registry of names for the whole
/// organisation. It is not workable here: the account that applies a migration
/// is a different Safe, deployer or timelock for every consumer and every
/// chain, so a root would have to be all of them at once, and baking each
/// consumer's authority into creation code would give each of them a different
/// address for what is meant to be one shared registry.
///
/// Keying by `msg.sender` removes the authority instead of choosing one. Anyone
/// may write, but only under themselves, so a reader asking about the namespace
/// of an authority it already trusts is reading something only that authority
/// could have written. Every other namespace holds unforgeable claims that no
/// reader asks about. With nothing to configure there is also no rollout state
/// in which this contract is inert: it does its whole job the moment it exists
/// on a chain.
///
/// A record is append-only per writer. `record` refuses a migration the caller
/// has already recorded, which is what makes re-running a migration fail rather
/// than repeat, and there is no way to unrecord one — a record describes
/// something that happened, and nothing that happened stops having happened.
///
/// The storage mapping is `internal` rather than `public`: `applied` refuses
/// the zero writer and the zero migration, and a public mapping's generated
/// getter would answer both with `false`, which is exactly the silent
/// wrong-branch this contract reverts to prevent.
contract MigrationRegistry is IMigrationRegistryV1 {
    /// The records, namespaced by writer. Not `public`: the only reader is
    /// `applied`, which refuses the two inputs that can only be mistakes.
    mapping(address writer => mapping(bytes32 migration => bool recorded)) internal sApplied;

    /// @inheritdoc IMigrationRegistryV1
    function record(bytes32 migration) external {
        // Checked before the already-recorded read, so an uninitialised id is
        // reported as the mistake it is rather than as a first record of zero.
        if (migration == bytes32(0)) {
            revert ZeroMigration();
        }
        // There is deliberately no zero-writer case here. `msg.sender` cannot
        // be the zero address, so the zero namespace is unreachable for writes
        // and a guard on it would be unreachable code pretending to be a check.
        if (sApplied[msg.sender][migration]) {
            revert MigrationAlreadyRecorded(msg.sender, migration);
        }
        sApplied[msg.sender][migration] = true;
        emit Migrated(msg.sender, migration);
    }

    /// @inheritdoc IMigrationRegistryV1
    /// @dev Both refusals are about a caller that has not supplied what it
    /// thinks it has. Neither can ever be a real record: nothing originates
    /// from the zero address, and `record` will not write the zero id — so
    /// answering `false` for either would be answering a question the caller
    /// did not mean to ask, and answering it with the value that sends it down
    /// its pre-migration branch.
    function applied(address writer, bytes32 migration) external view returns (bool) {
        if (writer == address(0)) {
            revert ZeroWriter();
        }
        if (migration == bytes32(0)) {
            revert ZeroMigration();
        }
        return sApplied[writer][migration];
    }
}
