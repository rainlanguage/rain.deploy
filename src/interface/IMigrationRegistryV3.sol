// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Prerequisite} from "./IMigrationRegistryV2.sol";

/// @title IMigrationRegistryV3
/// `IMigrationRegistryV2` with the writer as a parameter of every write, so a
/// line's writer can approve other accounts to write it. Every error, event,
/// reader and refusal means what `IMigrationRegistryV2` says it means, with
/// `writer` in place of the caller.
///
/// ## Delegation is per writer and per namespace
///
/// A line is keyed by `(writer, namespace)`, and only `writer` decides who
/// writes it. An approval names one namespace under the approving writer and
/// nothing else, so approving a delegate for one line never lets it write
/// another, and anyone may own a namespace of the same name under their own
/// address.
///
/// This decouples a line from whichever account executes a migration. A Safe
/// that changes contracts directly and a timelock that executes scheduled
/// changes can both write one line, approved by whoever owns it, so moving a
/// role between them never moves where its records go.
///
/// The writer can always write its own line, approved or not. Revoking stops
/// later writes and nothing else: records a delegate wrote while approved
/// stay, as every record does.
interface IMigrationRegistryV3 {
    /// As `IMigrationRegistryV2.ZeroMigration`.
    error ZeroMigration();

    /// As `IMigrationRegistryV2.GenesisMigration`.
    error GenesisMigration();

    /// As `IMigrationRegistryV2.ZeroWriter`, and thrown by a write naming the
    /// zero writer and by `approved` when asked about it.
    error ZeroWriter();

    /// As `IMigrationRegistryV2.ZeroNamespace`, and thrown by `approve`,
    /// `revoke` and `approved` when given it.
    error ZeroNamespace();

    /// As `IMigrationRegistryV2.MigrationAlreadyApplied`.
    error MigrationAlreadyApplied(address writer, bytes32 namespace, bytes32 migration);

    /// As `IMigrationRegistryV2.UnexpectedMigrationHead`.
    error UnexpectedMigrationHead(
        address writer, bytes32 namespace, bytes32 expectedNamespace, bytes32 expectedHead, bytes32 actualHead
    );

    /// As `IMigrationRegistryV2.ZeroTimestamp`.
    error ZeroTimestamp();

    /// As `IMigrationRegistryV2.FutureTimestamp`.
    error FutureTimestamp(uint256 appliedAt, uint256 blockTimestamp);

    /// As `IMigrationRegistryV2.TimestampBeforeHead`.
    error TimestampBeforeHead(uint256 appliedAt, uint256 headAppliedAt);

    /// As `IMigrationRegistryV2.PrerequisiteNotApplied`.
    error PrerequisiteNotApplied(address writer, bytes32 namespace, bytes32 migration);

    /// As `IMigrationRegistryV2.OwnPrerequisite`, the own line being
    /// `writer`'s.
    error OwnPrerequisite(bytes32 migration);

    /// Thrown when `approve`, `revoke` or `approved` is given the zero
    /// delegate, which nothing can call from and which is what an
    /// uninitialised `address` reads as.
    error ZeroDelegate();

    /// Thrown when a write's caller is neither `writer` nor approved by it for
    /// `namespace`.
    /// @param writer The line's writer.
    /// @param namespace The line under the writer.
    /// @param caller The account that called.
    error NotApproved(address writer, bytes32 namespace, address caller);

    /// As `IMigrationRegistryV2.Migrated`, `writer` being the line's writer,
    /// whoever called.
    event Migrated(address indexed writer, bytes32 indexed namespace, bytes32 indexed migration, uint256 appliedAt);

    /// Emitted when `writer` approves `delegate` to write its line in
    /// `namespace`.
    /// @param writer The approving writer.
    /// @param namespace The line under the writer.
    /// @param delegate The approved account.
    event Approved(address indexed writer, bytes32 indexed namespace, address indexed delegate);

    /// Emitted when `writer` revokes `delegate`'s approval for its line in
    /// `namespace`.
    /// @param writer The revoking writer.
    /// @param namespace The line under the writer.
    /// @param delegate The revoked account.
    event Revoked(address indexed writer, bytes32 indexed namespace, address indexed delegate);

    /// `IMigrationRegistryV2.applyMigration` into `writer`'s line, by `writer`
    /// or a delegate it has approved for `namespace`. Refuses the zero writer,
    /// then an unapproved caller, before anything else.
    /// @param writer The line's writer. Never zero.
    /// @param namespace The line under the writer.
    /// @param migration The migration to apply.
    /// @param prerequisites `writer`'s head in `namespace`, then the records
    /// that must exist.
    function applyMigration(address writer, bytes32 namespace, bytes32 migration, Prerequisite[] calldata prerequisites)
        external;

    /// `IMigrationRegistryV2.applyMigrationHistory` into `writer`'s line, by
    /// `writer` or a delegate it has approved for `namespace`, with the
    /// refusals `applyMigration` makes first.
    /// @param writer The line's writer. Never zero.
    /// @param namespace The line under the writer.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment it was applied.
    /// @param prerequisites `writer`'s head in `namespace`, then the records
    /// that must exist.
    function applyMigrationHistory(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] calldata prerequisites
    ) external;

    /// Approves `delegate` to write the caller's line in `namespace`.
    /// Approving an approved delegate leaves it approved.
    /// @param namespace The line under the caller. MUST NOT be zero.
    /// @param delegate The account to approve. MUST NOT be zero.
    function approve(bytes32 namespace, address delegate) external;

    /// Revokes `delegate`'s approval for the caller's line in `namespace`.
    /// Revoking an unapproved delegate leaves it unapproved.
    /// @param namespace The line under the caller. MUST NOT be zero.
    /// @param delegate The account to revoke. MUST NOT be zero.
    function revoke(bytes32 namespace, address delegate) external;

    /// Whether `writer` has approved `delegate` for its line in `namespace`.
    /// Refuses the zero writer, namespace and delegate rather than answering
    /// false about a question the caller did not mean to ask.
    /// @param writer The line's writer.
    /// @param namespace The line under the writer.
    /// @param delegate The account asked about.
    /// @return True when approved.
    function approved(address writer, bytes32 namespace, address delegate) external view returns (bool);

    /// As `IMigrationRegistryV2.applied`.
    /// @param writer The line's writer.
    /// @param namespace The line under the writer.
    /// @param migration The migration asked about.
    /// @return The moment it was applied, zero if never.
    function applied(address writer, bytes32 namespace, bytes32 migration) external view returns (uint256);

    /// As `IMigrationRegistryV2.appliedOnto`.
    /// @param writer The line's writer.
    /// @param namespace The line under the writer.
    /// @param migration The migration asked about.
    /// @return The head it was applied onto.
    function appliedOnto(address writer, bytes32 namespace, bytes32 migration) external view returns (bytes32);

    /// As `IMigrationRegistryV2.appliedAfter`.
    /// @param writer The line's writer.
    /// @param namespace The line under the writer.
    /// @param migration The migration asked about.
    /// @return The prerequisites it was applied after.
    function appliedAfter(address writer, bytes32 namespace, bytes32 migration)
        external
        view
        returns (Prerequisite[] memory);

    /// As `IMigrationRegistryV2.head`.
    /// @param writer The line's writer.
    /// @param namespace The line under the writer.
    /// @return The line's head.
    function head(address writer, bytes32 namespace) external view returns (bytes32);
}
