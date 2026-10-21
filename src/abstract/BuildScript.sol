// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {RAIN_COPYRIGHT_TEXT, RAIN_SPDX_LICENSE_IDENTIFIER} from "rain-sol-codegen-0.1.39/src/lib/LibCodeGen.sol";
import {DeploySuite, RainDeploySuitesBase} from "./RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../lib/LibRainDeploy.sol";
import {LibRainDeployConfig} from "../lib/LibRainDeployConfig.sol";
import {CloneNetwork} from "../lib/LibRainDeployClone.sol";
import {LibRainDeployExtendedNetworks} from "../lib/LibRainDeployExtendedNetworks.sol";
import {LibRainDeployMechanism} from "../lib/LibRainDeployMechanism.sol";
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
/// implements: the facts come out of `LibRainDeploy.supportedNetworkConfigs()`,
/// this package's own catalogue, and which of them are emitted comes out of
/// `supportedNetworks()` — the one hook on the declaration this inherits, which
/// `RainDeployBroadcast` deploys to and the chain group forks. So a network
/// arrives in a consumer's `foundry.toml` and `.env.example` by a version bump,
/// a repo narrowing the set narrows what it deploys to and what it is verified
/// on by the same answer, and there is no second place to spell either.
///
/// Inheriting the declaration is what makes that one answer: a hook of its own
/// here would be a second statement of the repo's network set, and the config
/// generated from it could cover networks nothing verifies with nothing red.
///
/// `run()` stages those two files rather than writing them, because foundry
/// refuses a cheatcode write to the project root's own `foundry.toml`.
/// `rainix-copy-artifacts` installs what was staged — see `LibRainDeployConfig`.
abstract contract BuildScript is RainDeploySuitesBase, Script {
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

    /// Every rolling snapshot a release freezes into its record: the
    /// `snapshotContractNames()` deploy suites and any other snapshot the repo
    /// regenerates into the candidate, so the frozen record holds the WHOLE
    /// candidate the release guard compares it against. Defaults to
    /// `snapshotContractNames()` for a repo whose candidate holds nothing else.
    /// @return The snapshot names.
    function releaseRecordNames() internal view virtual returns (string[] memory) {
        return snapshotContractNames();
    }

    /// The record root a release is frozen into, and the one the rolling
    /// snapshots are read from.
    ///
    /// Overridable so a `cutRelease()` can be exercised against a record other
    /// than the repo's own, which is append-only and cannot hold a test's
    /// release. Independent of `extendedNetworksRoot()`, which such a build
    /// overrides too.
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

    /// Rewrite the delimited network config blocks from the declared networks'
    /// catalogue entries.
    ///
    /// Run by `run()` and not by `cutRelease()`: the config is not part of a
    /// release record, and `run()` is what `Git is clean` calls on every push,
    /// so a tree whose config has drifted from the declaration it pins fails
    /// there.
    ///
    /// This STAGES the files; `rainix-copy-artifacts` installs them. See
    /// `LibRainDeployConfig` for why a script cannot write `foundry.toml`
    /// itself.
    function regenerateConfig() internal {
        LibRainDeployConfig.writeStagedConfig(
            vm, configRoot(), LibRainDeploy.declaredNetworkConfigs(supportedNetworks())
        );
    }

    /// The SPDX licence identifier the generated extended networks records declare. Defaults to
    /// `RAIN_SPDX_LICENSE_IDENTIFIER`, for a repo this org owns.
    /// @return The SPDX licence identifier.
    function extendedNetworksSpdxLicenseIdentifier() internal view virtual returns (string memory) {
        return RAIN_SPDX_LICENSE_IDENTIFIER;
    }

    /// The copyright text the generated extended networks records declare. Defaults to `RAIN_COPYRIGHT_TEXT`, for a
    /// repo this org owns.
    /// @return The copyright text.
    function extendedNetworksCopyrightText() internal view virtual returns (string memory) {
        return RAIN_COPYRIGHT_TEXT;
    }

    /// Writes each release's extended networks record from `extendedNetworks`, under `extendedNetworksRoot()`.
    /// Append-only against the record in the checkout: reverts with `ExtendedNetworksRewritten` on a declaration
    /// that drops, changes or reorders a network that record holds. Before writing, refuses a declaration the
    /// broadcast and the chain group would refuse, as `LibRainDeployMechanism.withExtendedNetworks` does.
    /// Run by `run()`, which `Git is clean` calls, so an entry appended to a committed record fails there. A record
    /// never committed is an untracked file, which `git diff` does not see.
    function regenerateExtendedNetworks() internal {
        DeploySuite[] memory released = releasedSuites();
        string memory root = extendedNetworksRoot();
        string memory spdxLicenseIdentifier = extendedNetworksSpdxLicenseIdentifier();
        string memory copyrightText = extendedNetworksCopyrightText();
        for (uint256 i = 0; i < released.length; i++) {
            CloneNetwork[] memory declared = extendedNetworks(released[i].suite);
            LibRainDeployMechanism.withExtendedNetworks(released[i], declared);
            LibRainDeployExtendedNetworks.writeExtendedNetworks(
                vm, root, released[i].suite, declared, spdxLicenseIdentifier, copyrightText
            );
        }
    }

    /// Every extended networks record `regenerateExtendedNetworks` writes.
    /// @return The paths.
    function extendedNetworksPaths() internal view returns (string[] memory) {
        DeploySuite[] memory released = releasedSuites();
        string memory root = extendedNetworksRoot();
        string[] memory written = new string[](released.length);
        uint256 count = 0;
        for (uint256 i = 0; i < released.length; i++) {
            (, string memory path) = LibRainDeployExtendedNetworks.writtenExtendedNetworksPath(
                root, released[i].suite, extendedNetworks(released[i].suite)
            );
            if (bytes(path).length > 0) {
                written[count++] = path;
            }
        }
        string[] memory paths = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            paths[i] = written[i];
        }
        return paths;
    }

    /// The directory `regenerateLibs` writes every generated lib into, and the
    /// one `generatedPaths()` declares them under.
    ///
    /// Overridable for the reason `recordRoot` is: a hook that can only be
    /// pointed at the committed tree can only be RUN by overwriting files the
    /// rest of the suite compiles and reads, and forge runs test contracts in
    /// parallel. Only the per-contract libs and the aggregate go here —
    /// `regenerateSnapshots` has no equivalent, because `LibFs` confines every
    /// snapshot it writes to `src/generated/`.
    /// @return The lib directory.
    function libDir() internal view virtual returns (string memory) {
        return LibRainDeploySnapshot.LIB_DIR;
    }

    /// Every path the repo's own hooks write that `generatedPaths()` does not
    /// already name, e.g. alias libs or retired contracts' released-suites libs.
    /// Defaults to none.
    /// @return The paths.
    function buildGeneratedPaths() internal view virtual returns (string[] memory) {
        return new string[](0);
    }

    /// Every path `run()` must rewrite, the installs of the staged config and the extended networks records included.
    /// @return The paths.
    function generatedPaths() internal view returns (string[] memory) {
        string[] memory base =
            LibRainDeploySnapshot.generatedPaths(libDir(), recordRoot(), releaseRecordNames(), snapshotContractNames());
        string[] memory own = buildGeneratedPaths();
        string[] memory extended = extendedNetworksPaths();
        string[] memory paths = new string[](base.length + 2 + own.length + extended.length);
        for (uint256 i = 0; i < base.length; i++) {
            paths[i] = base[i];
        }
        paths[base.length] = LibRainDeployConfig.CONFIG_NAME;
        paths[base.length + 1] = LibRainDeployConfig.ENV_EXAMPLE_NAME;
        for (uint256 i = 0; i < own.length; i++) {
            paths[base.length + 2 + i] = own[i];
        }
        for (uint256 i = 0; i < extended.length; i++) {
            paths[base.length + 2 + own.length + i] = extended[i];
        }
        return paths;
    }

    /// Prints `generatedPaths()` for `rainix-copy-artifacts` to fail a run that
    /// leaves one unwritten.
    function declareGeneratedPaths() internal view {
        LibRainDeploySnapshot.declareGenerated(generatedPaths());
    }

    /// @notice Regenerate everything this repo generates. Freezes nothing.
    function run() external {
        declareGeneratedPaths();
        regenerateConfig();
        regenerateSnapshots();
        regenerateLibs();
        regenerateExtendedNetworks();
    }

    /// @notice Regenerate the rolling snapshots, freeze them as this release's
    /// record, then regenerate the libs from the record.
    function cutRelease() external {
        LibRainDeploySnapshot.freeze(vm, recordRoot(), regenerateSnapshots, releaseRecordNames());
        regenerateLibs();
    }
}
