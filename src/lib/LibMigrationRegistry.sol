// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IMigrationRegistryV1, Prerequisite} from "../interface/IMigrationRegistryV1.sol";
import {LibMigrationRegistryDeploy} from "./LibMigrationRegistryDeploy.sol";

/// @title LibMigrationRegistry
/// @notice Reads and writes the `MigrationRegistry` deployed at a single
/// deterministic address on every network, verifying the registry's code hash
/// first, exactly as `LibAddressRegistry` does for the address registry. An
/// address alone says nothing on a chain the caller has not audited; the
/// address plus the code hash says the caller is talking to the registry it
/// compiled against.
///
/// ## There is deliberately no broadcast runner here
///
/// A deploy is always a broadcast; a migration is not. The dominant real shape
/// is a Safe executing a bundle, where the script emits transactions for the
/// multisig to sign and never broadcasts itself. Such a script appends
/// `applyMigration` to the bundle it is already emitting, which is what makes
/// the record atomic with the migration it describes — a property no runner
/// here could offer, and one a runner would quietly compete with.
///
/// ## Reading is what this is for
///
/// A test asserts EXACTLY the value implied by the migrations that have run:
///
/// ```solidity
/// if (LibMigrationRegistry.applied(SAFE, MIGRATION_V2) != 0) {
///     assertEq(vault.owner(), NEW_OWNER);
/// } else {
///     assertEq(vault.owner(), OLD_OWNER);
/// }
/// ```
///
/// Both branches assert. Neither reads the clock, and the branch is selected
/// by what happened on chain rather than by a deadline somebody guessed.
///
/// The registry is an INDEX, not proof. It says which invariant applies; it
/// does not say the invariant holds. Codehash and bytecode pins are what verify
/// the state itself, and this library is not a substitute for them.
library LibMigrationRegistry {
    /// Thrown when the code at the registry address is not the registry this
    /// library was compiled against. An address with no code hits this too: an
    /// empty account's code hash is zero, never the expected value.
    /// @param expectedCodeHash The code hash of the pinned registry.
    /// @param actualCodeHash The code hash actually found at the address.
    error UnexpectedMigrationRegistryCodeHash(bytes32 expectedCodeHash, bytes32 actualCodeHash);

    /// Reverts unless the pinned registry address holds the pinned code.
    ///
    /// Every entry point checks, and they check the same way, because each is
    /// worse than useless against unknown code: `applied` would branch a test
    /// on whatever timestamp that code returned, and a write would record a
    /// migration somewhere nothing will ever read it — or be told every
    /// prerequisite is applied and record nothing.
    function checkCodeHash() internal view {
        bytes32 actualCodeHash = LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.codehash;
        if (actualCodeHash != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH) {
            revert UnexpectedMigrationRegistryCodeHash(
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH, actualCodeHash
            );
        }
    }

    /// When `writer` applied `migration`, or zero if it never did.
    ///
    /// An absent registry reverts unguarded too — solc reverts a high-level
    /// call whose returndata is too short to decode — but anonymously. What
    /// the check actually forbids is the case that does NOT revert: code at
    /// the address that is not this registry, an EIP-7702 delegation included,
    /// is free to answer zero to every migration and send every caller down
    /// its pre-migration branch.
    /// @param writer The namespace to read — the authority whose record the
    /// caller trusts. Never the zero address.
    /// @param migration The migration to ask about. Never zero.
    /// @return The moment `writer` applied `migration` at, or zero.
    function applied(address writer, bytes32 migration) internal view returns (uint256) {
        checkCodeHash();
        return
            IMigrationRegistryV1(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
                .applied(writer, migration);
    }

    /// Applies `migration` under the CALLER's namespace, after `prerequisites`,
    /// as having been applied in the block this lands in.
    ///
    /// The caller is whoever the resulting transaction is sent from — a Safe
    /// executing a bundle, a broadcasting EOA, a timelock — and that account is
    /// the namespace the record lands in. A reader has to ask about that same
    /// account, so which account a migration is applied from is a decision
    /// with a consequence.
    ///
    /// A write into an EMPTY address fails unguarded — solc checks the callee
    /// exists when no return data is expected — so what the code-hash check
    /// stops is the write that SUCCEEDS into something that is not the
    /// registry: a record that went nowhere, after which the migration ran and
    /// every reader goes on asserting the pre-migration state.
    /// @param migration The migration to apply. Never zero.
    /// @param prerequisites The migrations, each under its writer, that must
    /// already be applied; the caller's own predecessor among them. Empty for
    /// a root.
    function applyMigration(bytes32 migration, Prerequisite[] memory prerequisites) internal {
        checkCodeHash();
        IMigrationRegistryV1(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigration(migration, prerequisites);
    }

    /// Applies `migration` under the CALLER's namespace, after `prerequisites`,
    /// as having been applied at `appliedAt`: for a migration that already ran,
    /// so the record carries the moment it ran rather than the moment it was
    /// written down. Everything `applyMigration` says holds here unchanged.
    /// @param migration The migration to apply. Never zero.
    /// @param appliedAt The moment `migration` was applied. Never zero, never
    /// after the block this lands in.
    /// @param prerequisites The migrations, each under its writer, that must
    /// already be applied. Empty for a root.
    function applyMigrationHistory(bytes32 migration, uint256 appliedAt, Prerequisite[] memory prerequisites) internal {
        checkCodeHash();
        IMigrationRegistryV1(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigrationHistory(migration, appliedAt, prerequisites);
    }
}
