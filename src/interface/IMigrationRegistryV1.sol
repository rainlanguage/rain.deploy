// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title IMigrationRegistryV1
/// @notice A per-writer record of which migrations have been applied, with
/// exactly two operations: a writer records one of its own migrations
/// (`record`), and anyone reads whether a given writer has recorded a given
/// migration (`applied`). There is no removal, no upgrade and no authority
/// beyond the writer over its own namespace, and an implementation MUST NOT add
/// any.
///
/// It exists so that a test can decide what to assert by reading what happened
/// on chain rather than by reading the clock. Without it, a test that spans a
/// migration accepts EITHER the pre-migration or the post-migration value until
/// a hardcoded deadline, which asserts nothing at all during the one window
/// where it matters most, and red-lines on a date rather than on a fact once
/// the deadline passes. With it, a test asserts EXACTLY the value implied by
/// the migrations that have run, in both branches.
///
/// ## An index, not proof
///
/// This registry says which invariant applies. It does NOT say that the
/// invariant holds. A multisig can act out of band — a beacon is upgraded by
/// hand and nothing here moves — and then a reader would confidently assert the
/// wrong state.
///
/// So a consumer keeps both layers, with distinct jobs: this registry SELECTS
/// which invariant applies, and codehash or bytecode pins VERIFY that it
/// actually holds. Replacing the pins with this registry trades a clock-guess
/// for a bookkeeping-guess, which is not an improvement. An implementation MUST
/// NOT offer anything that invites it, and in particular MUST NOT record
/// anything about the state a migration produced — only that it was recorded.
///
/// ## The namespace is the writer, and that is the whole access control
///
/// A record is keyed by the account that wrote it. Anyone may write, but only
/// to their own namespace, so a reader that reads the namespace of an authority
/// it already trusts is reading something only that authority could have
/// written. Records under any other namespace are unforgeable garbage that no
/// reader asks for.
///
/// This is deliberately not a root authority. The account that applies a
/// migration differs per consumer, per chain and per migration — a Safe
/// executing a bundle, a deployer EOA broadcasting a script, a timelock — so a
/// single root would have to be all of them at once. It is also what lets the
/// implementation be identical for every consumer, and therefore live at one
/// deterministic address on every chain: an authority baked into creation code
/// would give every consumer a different address, which is the property this
/// registry exists inside a deterministic-deploy library to keep.
///
/// A compromised writer can therefore only lie about its own migrations, to
/// readers that have chosen to trust it. It cannot touch anybody else's record,
/// and it cannot unrecord its own.
///
/// ## Identity is opaque
///
/// A migration is an opaque 32-byte value. This interface says nothing about
/// how one is derived — hashed from a script path, a name, a counter — and an
/// implementation MUST NOT constrain it. Two callers agreeing on an id is
/// entirely their business.
///
/// The convention that suits scripts-as-migrations is the hash of the script's
/// identity, e.g. `keccak256("script/20260623-upgrade-receipt-vaults.s.sol")`.
/// A date alone is not enough: two migrations authored on one day collide, and
/// consumers do author two on one day. An id is fixed at the moment it is first
/// recorded, so a script renamed afterwards keeps the id it was recorded under
/// rather than acquiring a new one — which is why the id belongs in a named
/// constant beside the script, not derived from a path at the call site.
interface IMigrationRegistryV1 {
    /// Thrown when `record` is called with the zero migration id, and by
    /// `applied` when it is asked about one. The zero id is what an
    /// uninitialised `bytes32` constant reads as, and an uninitialised id is
    /// never a migration anybody meant to name. Rejected in both directions
    /// because the read is the dangerous one: answering `false` would silently
    /// send a caller down its pre-migration branch.
    error ZeroMigration();

    /// Thrown by `applied` when asked about the zero writer. No transaction can
    /// originate from the zero address, so the zero namespace is provably empty
    /// and the answer would always be `false` — an unresolved or unset writer
    /// constant would therefore read as "nothing has been applied" rather than
    /// as the mistake it is.
    ///
    /// There is no matching case on `record`: `msg.sender` is never zero, so
    /// the zero namespace cannot be written to in the first place.
    error ZeroWriter();

    /// Thrown when a writer records a migration it has already recorded. This
    /// is what makes running a migration twice structurally impossible rather
    /// than a warning in a workflow dropdown asking a human not to re-dispatch
    /// it: a script consults `applied` before it acts, and this is the backstop
    /// under that consultation.
    /// @param writer The namespace, which is the caller.
    /// @param migration The migration already recorded under it.
    error MigrationAlreadyRecorded(address writer, bytes32 migration);

    /// Emitted every time a migration is recorded. A migration is recorded at
    /// most once per writer, so the log is the complete history of the registry
    /// and the only way to discover a record without already knowing the id.
    /// @param writer The namespace, which is the caller.
    /// @param migration The migration recorded.
    event Migrated(address indexed writer, bytes32 indexed migration);

    /// Records `migration` as applied under the caller's namespace.
    ///
    /// The implementation MUST revert `ZeroMigration` if `migration` is zero,
    /// MUST revert `MigrationAlreadyRecorded` if the caller has already
    /// recorded it, and MUST NOT provide any way to unrecord one. On success it
    /// MUST emit `Migrated`.
    ///
    /// A caller SHOULD record the migration in the same atomic unit as the
    /// migration itself where it can — a Safe appends this call to the bundle
    /// it is already executing — so that the record and the change it describes
    /// cannot land apart. Where they cannot be atomic, record LAST: a record
    /// that never landed leaves a reader asserting the pre-migration state,
    /// which the verification layer then catches loudly, and leaves a re-run
    /// possible. A record that landed for a migration that did not is the
    /// harder state to get out of.
    /// @param migration The migration to record.
    function record(bytes32 migration) external;

    /// Whether `writer` has recorded `migration`.
    ///
    /// The implementation MUST revert `ZeroWriter` or `ZeroMigration` rather
    /// than answering about either, and MUST answer `false` — not revert — for
    /// a nonzero writer that has simply not recorded a nonzero migration.
    ///
    /// That `false` is the deliberate difference from a registry whose reads
    /// revert on an unknown key. "This migration has not been applied here" is
    /// a legitimate, expected answer that a caller branches on and asserts the
    /// pre-migration state for; it is the ordinary state of every migration
    /// before it runs, and of every migration on a chain that never got it. A
    /// revert there would leave a caller with nothing to say about the state it
    /// is actually looking at, which is the whole failure this registry
    /// removes.
    /// @param writer The namespace to read. Never the zero address.
    /// @param migration The migration to ask about. Never zero.
    /// @return Whether `writer` has recorded `migration`.
    function applied(address writer, bytes32 migration) external view returns (bool);
}
