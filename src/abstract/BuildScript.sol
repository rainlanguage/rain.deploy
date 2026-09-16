// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Script} from "forge-std-1.16.2/src/Script.sol";
import {LibRainDeploy} from "../lib/LibRainDeploy.sol";
import {LibRainDeployConfig} from "../lib/LibRainDeployConfig.sol";
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
///
/// The network config is generated here rather than through a hook a repo
/// implements: it comes out of `LibRainDeploy.supportedNetworkConfigs()`, this
/// package's own constant, so a version bump is how a network arrives in a
/// consumer's `foundry.toml` and `.env.example`. A repo able to narrow that
/// list would deploy to and verify fewer chains with nothing red.
///
/// `run()` stages those two files rather than writing them, because foundry
/// refuses a cheatcode write to the project root's own `foundry.toml`. A repo
/// inheriting this needs `script/build.sh` to install what was staged — see
/// `LibRainDeployConfig`.
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

    /// The root holding the `foundry.toml` and `.env.example` whose network
    /// blocks are generated, and the parent of the staging directory they are
    /// written to.
    ///
    /// Overridable for the same reason `recordRoot` is: a writer that can only
    /// be pointed at the committed tree can only be exercised against it. The
    /// hazard is the same too — a repo pointing this anywhere but its own root
    /// generates config nothing reads, and `Git is clean` then sees a tree that
    /// never drifts because nothing regenerates it.
    /// @return The config root.
    function configRoot() internal view virtual returns (string memory) {
        return LibRainDeployConfig.CONFIG_ROOT;
    }

    /// Rewrite the delimited network config blocks from this package's roster.
    ///
    /// Run by `run()` and not by `cutRelease()`: the config is not part of a
    /// release record, and `run()` is what `Git is clean` calls on every push,
    /// so a tree whose config has drifted from the roster it pins fails there.
    ///
    /// This STAGES the files; `script/build.sh` installs them. See
    /// `LibRainDeployConfig` for why a script cannot write `foundry.toml`
    /// itself.
    function regenerateConfig() internal {
        LibRainDeployConfig.writeStagedConfig(
            vm, configRoot(), LibRainDeployConfig.BUILD_HOOK_PATH, LibRainDeploy.supportedNetworkConfigs()
        );
    }

    /// @notice Regenerate everything this repo generates. Freezes nothing.
    function run() external {
        regenerateConfig();
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
