// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IMigrationRegistryV3, Prerequisite} from "../interface/IMigrationRegistryV3.sol";
import {IRegistryDelegatesV1} from "../interface/IRegistryDelegatesV1.sol";
import {LibRegistryDelegates} from "./LibRegistryDelegates.sol";
import {LibMigrationRegistryDeploy} from "./LibMigrationRegistryDeploy.sol";

/// @title LibMigrationRegistry
/// @notice Reads and writes the `MigrationRegistry` deployed at a single
/// deterministic address on every network, verifying the registry's code hash
/// first, exactly as `LibConfigRegistry` does for the config registry and
/// `LibRainDeploy` does for the Zoltu factory. An address alone says nothing on
/// a chain the caller has not audited; the address plus the code hash says the
/// caller is talking to the registry it compiled against.
///
/// That is the whole library. It answers when a writer's line in a namespace
/// applied a migration, what it applied it onto and after, and where that line
/// has got to, and it applies one under a writer in a namespace it names, after
/// the head and the migrations in any other line the caller names, builds the
/// list for a write that waits on nothing but the head, or builds that write as
/// a call for another account to send. It approves and revokes delegates,
/// directly or as a call to send, reads an approval, and reads which account
/// wrote a record. Which writer a test trusts, which namespace a repo writes,
/// which invariant each answer selects, and how an id is derived are entirely
/// the consumer's business and none of this library's.
///
/// ## There is deliberately no broadcast runner here
///
/// `LibRainDeploy` wraps broadcasting because a deploy is always a broadcast.
/// A migration is not: the dominant real shape is a Safe executing a bundle,
/// where the script emits transactions for the multisig to sign and never
/// broadcasts anything itself. Such a script appends the registry write to the
/// bundle it is already emitting, which is what makes the record atomic with the
/// migration it describes — a property no runner in this library could offer,
/// and one a runner would quietly compete with.
///
/// So `applyMigrationV3` is an ordinary call. A broadcasting EOA script wraps it
/// in its own `vm.startBroadcast` and a test calls it directly. A Safe bundle
/// or a timelock batch appends the `(to, data)` pair `applyMigrationV3Call` or
/// `applyMigrationHistoryV3Call` builds instead, because the script building
/// the bundle is not the account that must make the write. None of those is
/// privileged over the others here.
///
/// ## Reading is what this is for
///
/// A test asserts EXACTLY the value implied by the migrations that have run:
///
/// ```solidity
/// if (LibMigrationRegistry.appliedV3(SAFE, NAMESPACE, MIGRATION_V2) != 0) {
///     assertEq(vault.owner(), NEW_OWNER);
/// } else {
///     assertEq(vault.owner(), OLD_OWNER);
/// }
/// ```
///
/// Both branches assert. Neither reads the clock, neither skips, and the branch
/// is selected by what happened on chain rather than by a deadline somebody
/// guessed. `appliedV3` answering zero is an ordinary, expected answer — it is
/// the state of every migration before it runs and of every migration on a
/// chain that never got it — which is why the registry answers it rather than
/// reverting.
///
/// The nonzero answer is WHEN, which is what a test whose invariant is itself
/// time-shaped needs: a cliff that starts at the migration, a rate that changes
/// a week after it. That is still the clock being read, but it is the chain's
/// record of the migration being read, not a date somebody guessed in advance.
///
/// ## Writing names what it is applied after, the head first
///
/// `applyMigrationV3` and `applyMigrationHistoryV3` both take a writer, a
/// namespace and one list, whose first entry is that writer in that namespace
/// at the migration the caller believes ran last in that line, so a chain that
/// never got that predecessor refuses the write instead of silently skipping a
/// step, and two migrations dispatched at once cannot land in the wrong
/// order. They differ only in where the recorded moment comes from: the block
/// this lands in, or the moment the caller supplies for a migration that
/// already ran. The first migration in a line names `MIGRATION_HEAD_GENESIS`,
/// imported from the interface — never a zero, which is what an uninitialised
/// constant would be and is refused everywhere.
///
/// Every later entry is a prerequisite: a migration in any other line, another
/// writer's or the writer's own in another namespace, that must already be
/// applied. The registry refuses the write, naming the first that has not
/// been, so a script whose migration depends on another Safe's, another
/// deployer's or another repo's states that dependency as a fact for the
/// registry to check instead of re-reading the other migration's post-state.
/// A migration that waits on nothing else passes the head alone, which is
/// the list `onto` builds.
///
/// `headV3` reads that value back, which is how an author finds what a new
/// script must name and how an operator sees which migration a chain is at. It
/// is not how a script tests that its predecessor ran: a head says what was
/// LAST, and `appliedV3` is what says whether a particular migration ever ran
/// at all.
///
/// `appliedOntoV3` reads back the head a record was applied onto, so a line
/// walked from `headV3` back is the order its migrations ran in — which is a
/// stronger statement than the moments make, because a moment is whatever the
/// writer supplied and the chain is what the registry enforced. `appliedAfterV3`
/// reads back the list the write gave, exactly as given, so the same walk
/// crosses lines.
///
/// The registry is an INDEX, not proof. It says which invariant applies; it does
/// not say the invariant holds. A multisig can act out of band and nothing here
/// moves. Codehash and bytecode pins are what verify the state itself, and this
/// library is not a substitute for them.
library LibMigrationRegistry {
    /// Thrown when the code at the registry address is not the registry this
    /// library was compiled against. An address with no code hits this too: a
    /// codeless account hashes to zero while it does not exist, and to the hash
    /// of the empty string once a single wei brings it into existence. Neither
    /// is the expected value.
    /// @param expectedCodeHash The code hash of the pinned registry.
    /// @param actualCodeHash The code hash actually found at the address.
    error UnexpectedMigrationRegistryCodeHash(bytes32 expectedCodeHash, bytes32 actualCodeHash);

    /// Reverts unless the pinned registry address holds the pinned code.
    ///
    /// Every entry point checks, and they check the same way, because each is
    /// worse than useless against unknown code: a reader would hand back values
    /// that are not records or approvals, a write, approve or revoke would land
    /// somewhere nothing reads, and a call builder would hand a signer a call
    /// that goes the same way. The check is one function so they cannot drift
    /// into checking different things, and an entry point added later has one
    /// place to call rather than a rule to remember.
    function checkCodeHash() internal view {
        bytes32 actualCodeHash = LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.codehash;
        if (actualCodeHash != LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH) {
            revert UnexpectedMigrationRegistryCodeHash(
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH, actualCodeHash
            );
        }
    }

    /// When `writer`'s line in `namespace` applied `migration`, or zero if it
    /// never did.
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
    /// The registry itself refuses the zero writer and the zero namespace, and
    /// refuses the two ids a migration can never be, so those arrive as
    /// reverts from it rather than as zero.
    /// @param writer The writer to read — the authority whose record the
    /// caller trusts. Never the zero address.
    /// @param namespace The line under `writer` to read. Never zero.
    /// @param migration The migration to ask about. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    /// @return The moment recorded against `migration` in `writer`'s line in
    /// `namespace`, or zero if it has not been applied there.
    function appliedV3(address writer, bytes32 namespace, bytes32 migration) internal view returns (uint256) {
        checkCodeHash();
        return IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .appliedV3(writer, namespace, migration);
    }

    /// What `writer`'s line in `namespace` applied `migration` onto, or zero if
    /// it never applied it.
    ///
    /// Verifies the registry's code hash before reading, for the same reason
    /// `appliedV3` does: occupying code is free to answer zero to every migration,
    /// which here reads as "never applied" exactly as a zero moment does.
    ///
    /// This is the step that walks a line. From `headV3`, each answer names
    /// the record before it, ending at `MIGRATION_HEAD_GENESIS`.
    /// @param writer The writer to read. Never the zero address.
    /// @param namespace The line under `writer` to read. Never zero.
    /// @param migration The migration to ask about. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    /// @return The head `writer`'s line in `namespace` applied `migration`
    /// onto, or zero if it has not applied it.
    function appliedOntoV3(address writer, bytes32 namespace, bytes32 migration) internal view returns (bytes32) {
        checkCodeHash();
        return IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .appliedOntoV3(writer, namespace, migration);
    }

    /// What `writer`'s line in `namespace` applied `migration` after: the list
    /// the write gave, as given — `writer` in `namespace` at the head it
    /// applied onto, then the prerequisites. Empty if the line never applied
    /// `migration`.
    ///
    /// Verifies the registry's code hash before reading, for the same reason
    /// `appliedV3` does: occupying code is free to answer an empty list for
    /// every record, which reads as "never applied".
    ///
    /// This is the step that walks from a record to everything it waited on,
    /// within its line and across them. Each entry after the first names a
    /// record that existed when this one was written, in whichever line it
    /// named; the first names the head, which is `MIGRATION_HEAD_GENESIS` for
    /// a line's first migration.
    /// @param writer The writer to read. Never the zero address.
    /// @param namespace The line under `writer` to read. Never zero.
    /// @param migration The migration to ask about. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    /// @return The list `writer`'s line in `namespace` applied `migration`
    /// after, as the write gave it.
    function appliedAfterV3(address writer, bytes32 namespace, bytes32 migration)
        internal
        view
        returns (Prerequisite[] memory)
    {
        checkCodeHash();
        return IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .appliedAfterV3(writer, namespace, migration);
    }

    /// The migration `writer`'s line in `namespace` applied most recently, or
    /// `MIGRATION_HEAD_GENESIS` if it has never applied one.
    ///
    /// Verifies the registry's code hash first for the same reason `appliedV3`
    /// does, and more sharply: occupying code is free to answer any head it
    /// likes, including the zero no head can ever hold, so an unverified read
    /// can hand back something that is not a head at all. An empty address is
    /// not that case — there is no returndata for a `bytes32` to decode from,
    /// so it reverts unguarded — and the check is what gives it a name.
    /// @param writer The writer to read. Never the zero address.
    /// @param namespace The line under `writer` to read. Never zero.
    /// @return The head of `writer`'s line in `namespace`. Never zero.
    function headV3(address writer, bytes32 namespace) internal view returns (bytes32) {
        checkCodeHash();
        return
            IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
                .headV3(writer, namespace);
    }

    /// The list a write applied onto `headMigration` in `writer`'s line in
    /// `namespace` passes when it waits on nothing else: that head alone, as
    /// the first and only entry.
    ///
    /// Pure, so it reads nothing and checks nothing. The registry checks the
    /// entry when the write lands — that `writer` names the write's writer, that
    /// `namespace` is the one the write names, that `headMigration` is the
    /// line's actual head — and refuses it if any is not.
    ///
    /// `headMigration` is the migration the script believes the line is at,
    /// fixed when the script is written. Passing what `headV3` answers in the
    /// same transaction instead names whatever the line is at when the write
    /// lands, so a chain that never got the predecessor, or a sibling that
    /// landed first, is applied onto rather than refused.
    /// @param writer The writer the write lands under: the account that calls
    /// the registry, or a writer that approved it for `namespace`. Never the
    /// zero address.
    /// @param namespace The line under `writer` the write names. Never zero.
    /// @param headMigration The migration `writer`'s line in `namespace`
    /// applied last, or `MIGRATION_HEAD_GENESIS` for the first in the line.
    /// @return The one-entry list, in the shape `applyMigrationV3`
    /// and `applyMigrationHistoryV3` take and `appliedAfterV3` answers.
    function onto(address writer, bytes32 namespace, bytes32 headMigration)
        internal
        pure
        returns (Prerequisite[] memory)
    {
        Prerequisite[] memory prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: writer, namespace: namespace, migration: headMigration});
        return prerequisites;
    }

    /// Applies `migration` under `writer` in `namespace`, after
    /// `prerequisites`.
    ///
    /// The caller is the account executing this code — the contract running
    /// it, or the broadcaster under `vm.broadcast`; a Safe or timelock bundle
    /// uses `applyMigrationV3Call` — and the registry refuses it unless it is
    /// `writer` or approved by `writer` for `namespace`. A reader asks about
    /// `writer`, whichever account sent it, so which writer a migration is
    /// applied under is a decision with a consequence rather than an
    /// implementation detail. The namespace is the line under `writer` this
    /// moves the head of: one key writing for several repos names one
    /// namespace per repo, and a reader asks about the one it means.
    ///
    /// Verifies the registry's code hash before writing, so a migration is
    /// never "applied" into unknown code. A write into an EMPTY address fails
    /// unguarded — solc checks the callee exists when no return data is
    /// expected — so what this stops is the write that SUCCEEDS into something
    /// that is not the registry: a record that went nowhere is worse than no
    /// record at all, because the migration ran and every reader goes on
    /// asserting the pre-migration state. Occupying code is equally free to
    /// answer "applied" to every prerequisite, so the check matters more for a
    /// write that names some, not less.
    ///
    /// The registry's refusals and their order are
    /// `IMigrationRegistryV3.applyMigrationHistoryV3`'s, with the block this lands
    /// in as the moment.
    /// @param writer The line's writer: the caller, or one that approved it.
    /// @param namespace The line under `writer` to apply in. Never zero.
    /// @param migration The migration to apply. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    /// @param prerequisites What `migration` is applied after, as
    /// `appliedAfterV3` will answer it: first `writer` in `namespace` at the
    /// migration the caller believes it applied last there, or
    /// `MIGRATION_HEAD_GENESIS` for the first in the line; then the
    /// migrations, each under its writer in its namespace, that must already
    /// be applied, every one a record key in another line. The head alone for
    /// a migration that waits on nothing else.
    function applyMigrationV3(address writer, bytes32 namespace, bytes32 migration, Prerequisite[] memory prerequisites)
        internal
    {
        checkCodeHash();
        IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigrationV3(writer, namespace, migration, prerequisites);
    }

    /// Applies `migration` under `writer` in `namespace`, after
    /// `prerequisites`, as having been applied at `appliedAt`.
    ///
    /// This is for a migration that already ran — one that ran before this
    /// registry reached the chain, or before its writer started recording at
    /// all — so the record carries the moment it ran rather than the moment it
    /// was written down.
    ///
    /// Everything `applyMigrationV3` says about the writer, the namespace, the
    /// code-hash check, the list and the registry's refusals holds here
    /// unchanged. The registry refuses the three moments a record cannot carry
    /// as well: zero, one after the block this lands in, and one before the
    /// record at the head it is applied onto. No prerequisite's moment bounds
    /// it: what is checked is that each prerequisite's record exists when this
    /// lands.
    /// @param writer The line's writer: the caller, or one that approved it.
    /// @param namespace The line under `writer` to apply in. Never zero.
    /// @param migration The migration to apply. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    /// @param appliedAt The moment `migration` was applied. Never zero, never
    /// after the block this lands in.
    /// @param prerequisites What `migration` is applied after, in the shape
    /// `applyMigrationV3` takes.
    function applyMigrationHistoryV3(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] memory prerequisites
    ) internal {
        checkCodeHash();
        IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigrationHistoryV3(writer, namespace, migration, appliedAt, prerequisites);
    }

    /// The call that applies `migration` under `writer` in `namespace`, after
    /// `prerequisites`, for another account to SEND: the `to` and `data`
    /// of one entry in a Safe bundle or one call in a timelock `scheduleBatch`.
    ///
    /// `applyMigrationV3` cannot serve those. It calls the registry from the code
    /// running it, and the script building a bundle is not the account that
    /// must make the write. This returns the write instead of making it, so it
    /// is made by the account that executes it: the Safe, for an entry in its
    /// MultiSend; the timelock, for a call in its batch, which the Safe only
    /// scheduled. That account is `writer` or approved by it for `namespace`,
    /// or the registry refuses the write.
    ///
    /// Appended as the LAST call of a batch, the write lands only if every call
    /// before it succeeded, in the same transaction, which is what makes the
    /// record a record of that batch rather than a claim about it.
    ///
    /// Verifies the registry's code hash on the chain this runs against before
    /// building, for the reason `applyMigrationV3` does and more sharply. A Safe
    /// or a timelock executes a call as a low-level call, which SUCCEEDS into
    /// an empty account where solc's high-level call reverts, so on a chain
    /// with no registry the bundle would execute, record nothing and say
    /// nothing. Building refuses that chain, and refuses occupying code, before
    /// anyone signs. The check is of the chain as it is when this runs; a batch
    /// executed later executes against whatever is at the address then.
    ///
    /// Everything `applyMigrationV3` says about the writer, the namespace, the
    /// list and the registry's refusals holds for the write this builds,
    /// checked when the write lands rather than here.
    /// @param writer The line's writer.
    /// @param namespace The line under `writer` to apply in. Never zero.
    /// @param migration The migration to apply. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    /// @param prerequisites What `migration` is applied after, in the shape
    /// `applyMigrationV3` takes, its head entry naming `writer`.
    /// @return The registry address.
    /// @return The `IMigrationRegistryV3.applyMigrationV3` calldata.
    function applyMigrationV3Call(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        Prerequisite[] memory prerequisites
    ) internal view returns (address, bytes memory) {
        checkCodeHash();
        address to = LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS;
        bytes memory data =
            abi.encodeCall(IMigrationRegistryV3.applyMigrationV3, (writer, namespace, migration, prerequisites));
        return (to, data);
    }

    /// The call that applies `migration` under `writer` in `namespace`, after
    /// `prerequisites`, as having been applied at `appliedAt`, for another
    /// account to send.
    ///
    /// This is `applyMigrationHistoryV3` built for another account to send,
    /// exactly as `applyMigrationV3Call` is `applyMigrationV3`: what
    /// `applyMigrationV3Call` says about the writer, the last call of a
    /// batch and the code-hash check holds here unchanged, and what
    /// `applyMigrationHistoryV3` says about the moment holds for the write this
    /// builds. The registry bounds the moment by the block the write LANDS in,
    /// not the block this ran in.
    /// @param writer The line's writer.
    /// @param namespace The line under `writer` to apply in. Never zero.
    /// @param migration The migration to apply. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    /// @param appliedAt The moment `migration` was applied. Never zero, never
    /// after the block the write lands in.
    /// @param prerequisites What `migration` is applied after, in the shape
    /// `applyMigrationV3` takes, its head entry naming `writer`.
    /// @return The registry address.
    /// @return The `IMigrationRegistryV3.applyMigrationHistoryV3` calldata.
    function applyMigrationHistoryV3Call(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] memory prerequisites
    ) internal view returns (address, bytes memory) {
        checkCodeHash();
        address to = LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS;
        bytes memory data = abi.encodeCall(
            IMigrationRegistryV3.applyMigrationHistoryV3, (writer, namespace, migration, appliedAt, prerequisites)
        );
        return (to, data);
    }

    /// Whether `writer` has approved `delegate` to write its line in
    /// `namespace`. Verifies the registry's code hash first, for the reason
    /// `appliedV3` does: occupying code could answer anything.
    /// @param writer The line's writer. Never the zero address.
    /// @param namespace The line under `writer`. Never zero.
    /// @param delegate The account asked about. Never the zero address.
    /// @return True when approved.
    function approvedV3(address writer, bytes32 namespace, address delegate) internal view returns (bool) {
        checkCodeHash();
        return IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .approvedV3(writer, namespace, delegate);
    }

    /// Which account wrote `writer`'s record of `migration` in `namespace`:
    /// `writer`, a delegate it approved, or zero if never applied. Verifies
    /// the registry's code hash first, for the reason `appliedV3` does.
    /// @param writer The line's writer. Never the zero address.
    /// @param namespace The line under `writer`. Never zero.
    /// @param migration The migration asked about. Never zero, never
    /// `MIGRATION_HEAD_GENESIS`.
    /// @return The account that wrote the record, or zero.
    function appliedByV3(address writer, bytes32 namespace, bytes32 migration) internal view returns (address) {
        checkCodeHash();
        return IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .appliedByV3(writer, namespace, migration);
    }

    /// Approves `delegate` to write the calling account's line in `namespace`.
    /// Verifies the registry's code hash first, for the reason
    /// `applyMigrationV3` does: an approval into other code appears to succeed
    /// and goes nowhere.
    /// @param namespace The line under the calling account. Never zero.
    /// @param delegate The account to approve. Never the zero address.
    function approveV3(bytes32 namespace, address delegate) internal {
        checkCodeHash();
        IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .approveV3(namespace, delegate);
    }

    /// Revokes `delegate`'s approval for the calling account's line in
    /// `namespace`. Verifies the registry's code hash first, for the reason
    /// `approveV3` does.
    /// @param namespace The line under the calling account. Never zero.
    /// @param delegate The account to revoke. Never the zero address.
    function revokeV3(bytes32 namespace, address delegate) internal {
        checkCodeHash();
        IMigrationRegistryV3(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .revokeV3(namespace, delegate);
    }

    /// The call that approves `delegate` to write the sending account's line
    /// in `namespace`, for another account to send. Verifies the registry's
    /// code hash first, for the reason `applyMigrationV3Call` does.
    /// @param namespace The line under the sending account. Never zero.
    /// @param delegate The account to approve. Never the zero address.
    /// @return The registry address.
    /// @return The `IRegistryDelegatesV1.approveV3` calldata.
    function approveV3Call(bytes32 namespace, address delegate) internal view returns (address, bytes memory) {
        checkCodeHash();
        return (
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            LibRegistryDelegates.approveCalldata(namespace, delegate, true)
        );
    }

    /// The call that revokes `delegate`'s approval for the sending account's
    /// line in `namespace`, for another account to send. Verifies the
    /// registry's code hash first, for the reason `applyMigrationV3Call` does.
    /// @param namespace The line under the sending account. Never zero.
    /// @param delegate The account to revoke. Never the zero address.
    /// @return The registry address.
    /// @return The `IRegistryDelegatesV1.revokeV3` calldata.
    function revokeV3Call(bytes32 namespace, address delegate) internal view returns (address, bytes memory) {
        checkCodeHash();
        return (
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            LibRegistryDelegates.approveCalldata(namespace, delegate, false)
        );
    }
}
