// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IMigrationRegistryV1} from "../interface/IMigrationRegistryV1.sol";
import {LibMigrationRegistryDeploy} from "./LibMigrationRegistryDeploy.sol";

/// @title LibMigrationRegistry
/// @notice Reads and writes the `MigrationRegistry` deployed at a single
/// deterministic address on every network, verifying the registry's code hash
/// first, exactly as `LibAddressRegistry` does for the address registry and
/// `LibRainDeploy` does for the Zoltu factory. An address alone says nothing on
/// a chain the caller has not audited; the address plus the code hash says the
/// caller is talking to the registry it compiled against.
///
/// That is the whole library. It answers whether a writer has recorded a
/// migration, and it records one under the caller. Which writer a test trusts,
/// which invariant each answer selects, and how an id is derived are entirely
/// the consumer's business and none of this library's.
///
/// ## There is deliberately no broadcast runner here
///
/// `LibRainDeploy` wraps broadcasting because a deploy is always a broadcast.
/// A migration is not: the dominant real shape is a Safe executing a bundle,
/// where the script emits transactions for the multisig to sign and never
/// broadcasts anything itself. Such a script appends `record` to the bundle it
/// is already emitting, which is what makes the record atomic with the
/// migration it describes — a property no runner in this library could offer,
/// and one a runner would quietly compete with.
///
/// So `record` is an ordinary call. A broadcasting EOA script wraps it in its
/// own `vm.startBroadcast`, a Safe bundle appends it, and a test calls it
/// directly; none of those is privileged over the others here.
///
/// ## Reading is what this is for
///
/// A test asserts EXACTLY the value implied by the migrations that have run:
///
/// ```solidity
/// if (LibMigrationRegistry.applied(SAFE, MIGRATION_V2)) {
///     assertEq(vault.owner(), NEW_OWNER);
/// } else {
///     assertEq(vault.owner(), OLD_OWNER);
/// }
/// ```
///
/// Both branches assert. Neither reads the clock, neither skips, and the branch
/// is selected by what happened on chain rather than by a deadline somebody
/// guessed. `applied` answering `false` is an ordinary, expected answer — it is
/// the state of every migration before it runs and of every migration on a
/// chain that never got it — which is why the registry answers it rather than
/// reverting.
///
/// The registry is an INDEX, not proof. It says which invariant applies; it does
/// not say the invariant holds. A multisig can act out of band and nothing here
/// moves. Codehash and bytecode pins are what verify the state itself, and this
/// library is not a substitute for them.
library LibMigrationRegistry {
    /// Thrown when the code at the registry address is not the registry this
    /// library was compiled against. An address with no code hits this too: an
    /// empty account's code hash is zero, never the expected value.
    /// @param expectedCodeHash The code hash of the pinned registry.
    /// @param actualCodeHash The code hash actually found at the address.
    error UnexpectedMigrationRegistryCodeHash(bytes32 expectedCodeHash, bytes32 actualCodeHash);

    /// Reverts unless the pinned registry address holds the pinned code.
    ///
    /// Both entry points check, and they check the same way, because both are
    /// worse than useless against unknown code: a read would branch a test on
    /// whatever that code returned, and a write would record a migration
    /// somewhere nothing will ever read it. The check is one function so the
    /// two cannot drift into checking different things.
    function checkCodeHash() internal view {
        bytes32 actualCodeHash = LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.codehash;
        if (actualCodeHash != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH) {
            revert UnexpectedMigrationRegistryCodeHash(
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH, actualCodeHash
            );
        }
    }

    /// Whether `writer` has recorded `migration`.
    ///
    /// Verifies the registry's code hash before reading, so a chain where the
    /// registry is absent, or where something else occupies its address, is a
    /// loud revert rather than a call into unknown code. That distinction is
    /// the whole point here: "no registry on this chain" and "this migration
    /// has not been applied" are different facts, and silently collapsing the
    /// first into the second would send a caller down its pre-migration branch
    /// on every chain the registry was never deployed to.
    ///
    /// The registry itself refuses the zero writer and the zero migration, so
    /// those arrive as reverts from it rather than as `false`.
    /// @param writer The namespace to read — the authority whose record the
    /// caller trusts. Never the zero address.
    /// @param migration The migration to ask about. Never zero.
    /// @return Whether `writer` has recorded `migration`.
    function applied(address writer, bytes32 migration) internal view returns (bool) {
        checkCodeHash();
        return
            IMigrationRegistryV1(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
                .applied(writer, migration);
    }

    /// Records `migration` under the CALLER's namespace.
    ///
    /// The caller is whoever the resulting transaction is sent from — a Safe
    /// executing a bundle, a broadcasting EOA, a timelock — and that account is
    /// the namespace the record lands in. A reader has to ask about that same
    /// account, so which account a migration is recorded from is a decision
    /// with a consequence rather than an implementation detail.
    ///
    /// Verifies the registry's code hash before writing, so a migration is
    /// never "recorded" into an empty address or into unknown code. A record
    /// that went nowhere is worse than no record at all: the migration would
    /// have run, and every reader would go on asserting the pre-migration
    /// state.
    ///
    /// The registry refuses the zero id and refuses a migration this caller has
    /// already recorded, which is what makes a re-dispatched migration fail
    /// rather than repeat.
    /// @param migration The migration to record. Never zero.
    function record(bytes32 migration) internal {
        checkCodeHash();
        IMigrationRegistryV1(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS).record(migration);
    }
}
