// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IMigrationRegistryV2} from "../interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistryV2Deploy} from "./LibMigrationRegistryV2Deploy.sol";

/// @title LibMigrationRegistryV2
/// @notice Reads and writes the `MigrationRegistryV2` deployed at a single
/// deterministic address on every network, verifying the registry's code hash
/// first, exactly as `LibAddressRegistry` does for the address registry and
/// `LibRainDeploy` does for the Zoltu factory. An address alone says nothing on
/// a chain the caller has not audited; the address plus the code hash says the
/// caller is talking to the registry it compiled against.
///
/// That is the whole library. It answers when a writer applied a migration and
/// where that writer's namespace has got to, and it applies one under the
/// caller. Which writer a test trusts, which invariant each answer selects, and
/// how an id is derived are entirely the consumer's business and none of this
/// library's.
///
/// ## There is deliberately no broadcast runner here
///
/// `LibRainDeploy` wraps broadcasting because a deploy is always a broadcast.
/// A migration is not: the dominant real shape is a Safe executing a bundle,
/// where the script emits transactions for the multisig to sign and never
/// broadcasts anything itself. Such a script appends `applyMigration` to the
/// bundle it is already emitting, which is what makes the record atomic with the
/// migration it describes — a property no runner in this library could offer,
/// and one a runner would quietly compete with.
///
/// So `applyMigration` is an ordinary call. A broadcasting EOA script wraps it
/// in its own `vm.startBroadcast`, a Safe bundle appends it, and a test calls it
/// directly; none of those is privileged over the others here.
///
/// ## Reading is what this is for
///
/// A test asserts EXACTLY the value implied by the migrations that have run:
///
/// ```solidity
/// if (LibMigrationRegistryV2.applied(SAFE, MIGRATION_V2) != 0) {
///     assertEq(vault.owner(), NEW_OWNER);
/// } else {
///     assertEq(vault.owner(), OLD_OWNER);
/// }
/// ```
///
/// Both branches assert. Neither reads the clock, neither skips, and the branch
/// is selected by what happened on chain rather than by a deadline somebody
/// guessed. `applied` answering zero is an ordinary, expected answer — it is
/// the state of every migration before it runs and of every migration on a
/// chain that never got it — which is why the registry answers it rather than
/// reverting.
///
/// The nonzero answer is WHEN, which is what a test whose invariant is itself
/// time-shaped needs: a cliff that starts at the migration, a rate that changes
/// a week after it. That is still the clock being read, but it is the chain's
/// record of the migration being read, not a date somebody guessed in advance.
///
/// ## Writing names the head it is applying onto, and the moment it ran
///
/// `applyMigration` takes the migration the caller believes ran last in its
/// namespace, so a chain that never got that predecessor refuses the write
/// instead of silently skipping a step, and two migrations dispatched at once
/// cannot land in the wrong order. The first migration in a namespace names
/// `MIGRATION_HEAD_GENESIS`, imported from the interface — never a zero, which
/// is what an uninitialised constant would be and is refused everywhere.
///
/// It also takes the moment the migration ran, which is what lets a script
/// record a migration that already happened with the time it happened rather
/// than the time it was written down. A script recording a migration it is
/// running right now passes `block.timestamp`; one backfilling a migration that
/// ran before the registry reached this chain passes the moment it ran. The
/// registry refuses a zero, one after the current block, and one before the
/// record of the head being applied onto.
///
/// `head` reads the head back, which is how an author finds what a new script
/// must name and how an operator sees which migration a chain is at. It is not
/// how a script tests that its predecessor ran: a head says what was LAST, and
/// `applied` is what says whether a particular migration ever ran at all.
///
/// The registry is an INDEX, not proof. It says which invariant applies; it does
/// not say the invariant holds. A multisig can act out of band and nothing here
/// moves. Codehash and bytecode pins are what verify the state itself, and this
/// library is not a substitute for them.
library LibMigrationRegistryV2 {
    /// Thrown when the code at the registry address is not the registry this
    /// library was compiled against. An address with no code hits this too: an
    /// empty account's code hash is zero, never the expected value.
    /// @param expectedCodeHash The code hash of the pinned registry.
    /// @param actualCodeHash The code hash actually found at the address.
    error UnexpectedMigrationRegistryV2CodeHash(bytes32 expectedCodeHash, bytes32 actualCodeHash);

    /// Reverts unless the pinned registry address holds the pinned code.
    ///
    /// All three entry points check, and they check the same way, because each
    /// is worse than useless against unknown code: `applied` would branch a
    /// test on whatever timestamp that code returned, `head` would hand back a
    /// value that is not a head, and `applyMigration` would record a migration
    /// somewhere nothing will ever read it. The check is one function so the
    /// three cannot drift into checking different things, and an entry point
    /// added later has one place to call rather than a rule to remember.
    function checkCodeHash() internal view {
        bytes32 actualCodeHash = LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_ADDRESS.codehash;
        if (actualCodeHash != LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_CODEHASH) {
            revert UnexpectedMigrationRegistryV2CodeHash(
                LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_CODEHASH, actualCodeHash
            );
        }
    }

    /// When `writer` applied `migration`, or zero if it never did.
    ///
    /// Verifies the registry's code hash before reading, so a chain where the
    /// registry is absent, or where something else occupies its address, is a
    /// NAMED revert rather than a call into unknown code. An absent registry
    /// reverts either way — solc reverts a high-level call whose returndata is
    /// too short to decode — but anonymously, saying nothing about which of the
    /// two it was. What the check actually forbids is the case that does NOT
    /// revert: code at the address that is not this registry, an EIP-7702
    /// delegation included, is free to answer zero to every migration and send
    /// every caller down its pre-migration branch.
    ///
    /// The registry itself refuses the zero writer, and refuses the two ids a
    /// migration can never be, so those arrive as reverts from it rather than
    /// as zero.
    /// @param writer The namespace to read — the authority whose record the
    /// caller trusts. Never the zero address.
    /// @param migration The migration to ask about. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    /// @return The moment `writer` applied `migration` at, or zero if it has
    /// not.
    function applied(address writer, bytes32 migration) internal view returns (uint256) {
        checkCodeHash();
        return IMigrationRegistryV2(LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_ADDRESS)
            .applied(writer, migration);
    }

    /// The migration `writer` applied most recently, or `MIGRATION_HEAD_GENESIS`
    /// if it has never applied one.
    ///
    /// Verifies the registry's code hash first for the same reason `applied`
    /// does, and more sharply: occupying code is free to answer any head it
    /// likes, including the zero no head can ever hold, so an unverified read
    /// can hand back something that is not a head at all. An empty address is
    /// not that case — there is no returndata for a `bytes32` to decode from,
    /// so it reverts unguarded — and the check is what gives it a name.
    /// @param writer The namespace to read. Never the zero address.
    /// @return The head of `writer`'s namespace. Never zero.
    function head(address writer) internal view returns (bytes32) {
        checkCodeHash();
        return IMigrationRegistryV2(LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_ADDRESS).head(writer);
    }

    /// Applies `migration` under the CALLER's namespace, onto `expectedHead`, as
    /// having been applied at `appliedAt`.
    ///
    /// The caller is whoever the resulting transaction is sent from — a Safe
    /// executing a bundle, a broadcasting EOA, a timelock — and that account is
    /// the namespace the record lands in. A reader has to ask about that same
    /// account, so which account a migration is applied from is a decision
    /// with a consequence rather than an implementation detail. It is also the
    /// account whose head this moves, so two unrelated sequences applied from
    /// one account interleave into one chain.
    ///
    /// Verifies the registry's code hash before writing, so a migration is
    /// never "applied" into unknown code. A write into an EMPTY address fails
    /// unguarded — solc checks the callee exists when no return data is
    /// expected — so what this stops is the write that SUCCEEDS into something
    /// that is not the registry: a record that went nowhere is worse than no
    /// record at all, because the migration ran and every reader goes on
    /// asserting the pre-migration state.
    ///
    /// The registry refuses the zero id, refuses a migration this caller has
    /// already applied, and refuses one applied onto anything but the
    /// namespace's actual head — which between them make a re-dispatched, a
    /// skipped and an out-of-order migration all fail rather than land. It
    /// refuses the three moments a record cannot carry as well: zero, one after
    /// the current block, and one before the record of `expectedHead`.
    /// @param expectedHead The migration the caller believes it applied last,
    /// or `MIGRATION_HEAD_GENESIS` for the first in this namespace.
    /// @param migration The migration to apply. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    /// @param appliedAt The moment `migration` was applied — `block.timestamp`
    /// for a migration running now, the moment it ran for one being recorded
    /// after the fact.
    function applyMigration(bytes32 expectedHead, bytes32 migration, uint256 appliedAt) internal {
        checkCodeHash();
        IMigrationRegistryV2(LibMigrationRegistryV2Deploy.MIGRATION_REGISTRY_V2_DEPLOYED_ADDRESS)
            .applyMigration(expectedHead, migration, appliedAt);
    }
}
