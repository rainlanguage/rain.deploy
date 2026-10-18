// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IMigrationRegistryV2, Prerequisite} from "./IMigrationRegistryV2.sol";

/// @title IMigrationRegistryV3
/// `IMigrationRegistryV2`, plus delegated writes: a writer approves other
/// accounts to write its line in one namespace, and an approved delegate
/// writes that line with `applyMigrationFor` or `applyMigrationHistoryFor`.
///
/// ## Delegation is per writer and per namespace
///
/// A line is still keyed by `(writer, namespace)`, and still only `writer` can
/// decide who writes it. An approval names one namespace under the approving
/// writer and nothing else, so approving a delegate for one line never lets it
/// write another, and anyone may own a namespace of the same name under their
/// own address.
///
/// This decouples a line from whichever account executes a migration. A Safe
/// that changes contracts directly and a timelock that executes scheduled
/// changes can both write one line, approved by whoever owns it, so moving a
/// role between them never moves where its records go.
///
/// A delegated write makes exactly the same refusals as the writer's own, with
/// `writer` in place of `msg.sender`: `prerequisites[0]` names `writer`'s head,
/// a later entry in `writer`'s own line is `OwnPrerequisite`, and the record and
/// the head are `writer`'s. The writer can always write its own line, approved
/// or not.
///
/// Revoking stops later writes and nothing else. Records a delegate wrote while
/// approved stay, as every record does.
interface IMigrationRegistryV3 is IMigrationRegistryV2 {
    /// Thrown when `approve`, `revoke` or `approved` is given the zero
    /// delegate, which nothing can call from and which is what an
    /// uninitialised `address` reads as.
    error ZeroDelegate();

    /// Thrown when a delegated write's caller is neither `writer` nor approved
    /// by it for `namespace`.
    /// @param writer The line's writer.
    /// @param namespace The line under the writer.
    /// @param caller The account that called.
    error NotApproved(address writer, bytes32 namespace, address caller);

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

    /// `applyMigration` into `writer`'s line, by `writer` or a delegate it has
    /// approved for `namespace`. Stamps the block the record lands in.
    /// @param writer The line's writer. MUST NOT be zero.
    /// @param namespace The line under the writer.
    /// @param migration The migration to apply.
    /// @param prerequisites `writer`'s head in `namespace`, then the records
    /// that must exist.
    function applyMigrationFor(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        Prerequisite[] calldata prerequisites
    ) external;

    /// `applyMigrationHistory` into `writer`'s line, by `writer` or a delegate
    /// it has approved for `namespace`.
    /// @param writer The line's writer. MUST NOT be zero.
    /// @param namespace The line under the writer.
    /// @param migration The migration to apply.
    /// @param appliedAt The moment it was applied.
    /// @param prerequisites `writer`'s head in `namespace`, then the records
    /// that must exist.
    function applyMigrationHistoryFor(
        address writer,
        bytes32 namespace,
        bytes32 migration,
        uint256 appliedAt,
        Prerequisite[] calldata prerequisites
    ) external;
}
