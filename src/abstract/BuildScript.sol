// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Script} from "forge-std-1.16.2/src/Script.sol";
import {LibRainDeploySnapshot} from "../lib/LibRainDeploySnapshot.sol";

/// @title BuildScript
/// @notice The two entry points of a deploy repo's `script/Build.sol`, concrete
/// here:
///
/// - `run()` regenerates and freezes nothing. This is the one CI runs.
/// - `cutRelease()` regenerates, freezes the rolling snapshots as
///   `<recordRoot()>/<tag>/`, then regenerates the libs from the record that
///   now holds the release being cut.
///
/// Neither is `virtual`, so a repo inheriting this implements the hooks below
/// and has no entry point to cut a release from other than `cutRelease()`.
abstract contract BuildScript is Script {
    /// Rewrite the rolling `candidate/` snapshots from what this repo currently
    /// compiles. Run by `cutRelease()` inside `freeze`, after its guards and
    /// before it copies anything.
    function regenerateSnapshots() internal virtual;

    /// Rewrite every file generated from the snapshots and from the frozen
    /// record. Run last, after a `cutRelease()` freeze has written the record,
    /// so a file emitted from that record holds the release just cut.
    function regenerateLibs() internal virtual;

    /// The contracts whose rolling snapshots a release freezes.
    /// @return The contract names.
    function snapshotContractNames() internal view virtual returns (string[] memory);

    /// The record root a release is frozen into, and the one the rolling
    /// snapshots are read from.
    ///
    /// Overridable so a `cutRelease()` can be exercised against a record other
    /// than the repo's own, which is append-only and cannot hold a test's
    /// release.
    /// @return The record root.
    function recordRoot() internal view virtual returns (string memory) {
        return LibRainDeploySnapshot.LIB_FS_ROOT;
    }

    /// @notice Regenerate everything this repo generates. Freezes nothing.
    function run() external {
        regenerateSnapshots();
        regenerateLibs();
    }

    /// @notice Regenerate the rolling snapshots, freeze them as this release's
    /// record, then regenerate the libs from the record.
    function cutRelease() external {
        LibRainDeploySnapshot.freeze(vm, recordRoot(), regenerateSnapshots, snapshotContractNames());
        regenerateLibs();
    }
}
