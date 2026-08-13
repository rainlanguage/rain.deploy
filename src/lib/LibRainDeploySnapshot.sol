// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.16.1/src/Vm.sol";
import {LibCodeGen} from "rain-sol-codegen-0.1.4/src/lib/LibCodeGen.sol";
import {LibFs} from "rain-sol-codegen-0.1.4/src/lib/LibFs.sol";
import {LibRainDeploy} from "./LibRainDeploy.sol";

/// Thrown when `[package].version` is not strict `X.Y.Z`. A version like
/// `0.1.7-rc1` maps to the directory `0_1_7-rc1`, which the append-only gate's
/// tag predicate ignores forever — an orphan snapshot nothing protects. Refused
/// rather than frozen.
/// @param version The version read from `foundry.toml`.
error UnreleasableVersion(string version);

/// Thrown when there is no rolling snapshot to freeze. The property is "there
/// is something to freeze", so this fires on a missing directory and on a
/// missing file within it alike.
/// @param path The rolling path that was expected to exist.
error NothingToFreeze(string path);

/// Thrown when a release tag already has a frozen snapshot. Frozen snapshots
/// are append-only: a release is cut once, and re-cutting one would replace the
/// record consumers of that release pin against.
/// @param tag The release tag.
/// @param dir The frozen directory that already exists.
error SnapshotAlreadyFrozen(string tag, string dir);

/// @title LibRainDeploySnapshot
/// @notice Which release is being built, where its record lives, and how it is
/// frozen. Release machinery, not code generation.
///
/// It lives here rather than in `rain-sol-codegen` deliberately. Emitting a
/// Solidity constant is codegen; reading `[package].version`, deciding a
/// release directory and making that directory immutable is the deploy
/// lifecycle, which is this repo's subject. `LibCodeGen` still emits every
/// constant — that split is the point, not an oversight.
///
/// ## Two facts, two homes
///
/// - `src/generated/candidate/` is the ROLLING snapshot: what the current
///   source compiles to, regenerated on every build, always describing HEAD.
/// - `src/generated/<tag>/` is a FROZEN snapshot: what a release deployed,
///   written once and never again.
///
/// Conflating them is how a repo ends up unable to say what a published version
/// actually deployed. Consumers pin releases; the candidate is what the next
/// release will be.
///
/// ## The ordering is structural
///
/// The freeze reads whatever is on disk, so freezing a stale candidate is
/// silent — the immutability check only fires when a tag is re-cut, which is
/// too late and too rare to rely on. `freeze` therefore takes the regeneration
/// as an argument and runs it FIRST, in the same call. There is no entry point
/// that freezes without regenerating, so "freeze, then regenerate" has nowhere
/// to be written.
///
/// @dev The consuming repo's `foundry.toml` must grant read access to itself so
/// `deployTag` can read the release version from it:
/// `fs_permissions = [{ access = "read", path = "./foundry.toml" }, ...]`
/// alongside read-write access to `./src`.
library LibRainDeploySnapshot {
    /// The rolling snapshot's directory name. A sibling of the frozen tag
    /// directories rather than a file beside them, so `src/generated/` reads as
    /// `candidate/ 0_1_5/ 0_1_6/` and "which one is current" is answered by
    /// looking.
    string constant CANDIDATE = "candidate";

    /// The canonical release tag: `foundry.toml` `[package].version` with dots
    /// converted to underscores (`0.1.7` -> `0_1_7`) for the Solidity directory
    /// form. The single definition of the tag form — the version in
    /// `foundry.toml` is the one source of truth for which release is being
    /// built, so every path derives from it rather than restating it.
    ///
    /// Refuses anything that is not strict `X.Y.Z`.
    /// @param vm The Vm instance for file operations.
    /// @return The tag.
    function deployTag(Vm vm) internal view returns (string memory) {
        string memory version = vm.parseTomlString(vm.readFile("foundry.toml"), ".package.version");
        bytes memory versionBytes = bytes(version);

        // Strict X.Y.Z: digits and exactly two dots, no leading or trailing
        // dot, no empty component. Checked here rather than by the caller
        // because every path below derives from the result.
        uint256 dots = 0;
        uint256 digitsInComponent = 0;
        for (uint256 i = 0; i < versionBytes.length; i++) {
            bytes1 char = versionBytes[i];
            if (char == ".") {
                if (digitsInComponent == 0) {
                    revert UnreleasableVersion(version);
                }
                dots++;
                digitsInComponent = 0;
            } else if (char >= "0" && char <= "9") {
                digitsInComponent++;
            } else {
                revert UnreleasableVersion(version);
            }
        }
        if (dots != 2 || digitsInComponent == 0) {
            revert UnreleasableVersion(version);
        }

        bytes memory tagBytes = new bytes(versionBytes.length);
        for (uint256 i = 0; i < versionBytes.length; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            tagBytes[i] = versionBytes[i] == "." ? bytes1("_") : versionBytes[i];
        }
        return string(tagBytes);
    }

    /// The directory holding a snapshot, rolling or frozen.
    /// @param dir The snapshot directory name — a release tag, or `CANDIDATE`.
    /// @return The directory path.
    function dirForSnapshot(string memory dir) internal pure returns (string memory) {
        return string.concat("src/generated/", dir);
    }

    /// The contract name that places a generated file inside a snapshot
    /// directory. `LibFs` derives its own path from a contract name and takes
    /// no path, so the snapshot directory is folded into the name it is given.
    /// @param dir The snapshot directory name — a release tag, or `CANDIDATE`.
    /// @param contractName The name of the contract.
    /// @return The name to pass to `LibFs.buildFileForContract`.
    function snapshotName(string memory dir, string memory contractName) internal pure returns (string memory) {
        return string.concat(dir, "/", contractName);
    }

    /// The path of a contract's generated file within a snapshot.
    ///
    /// Delegated to `LibFs` rather than concatenated here, so the path this
    /// library freezes FROM is the same definition `LibFs` writes TO. Two
    /// spellings of one path is how a freeze silently reads nothing.
    /// @param dir The snapshot directory name — a release tag, or `CANDIDATE`.
    /// @param contractName The name of the contract.
    /// @return The file path.
    function pathForSnapshot(string memory dir, string memory contractName) internal pure returns (string memory) {
        return LibFs.pathForContract(snapshotName(dir, contractName));
    }

    /// The output root `LibFs` writes to, and the only one it can write to:
    /// `LibFs.pathForContract` hardcodes it.
    string constant LIB_FS_ROOT = "src/generated";

    /// Generate one snapshot for one contract, under an arbitrary output root.
    ///
    /// The root is a parameter because a repo generates real deploy records
    /// under `src/generated/` and test records under `test/generated/`, and
    /// both must come from THIS code path — a second emitter would make the
    /// shape assertions a statement about the wrong generator.
    ///
    /// `LibFs` hardcodes `src/generated/` and takes a contract name rather than
    /// a path, so a non-default root is reached by generating there and moving
    /// the result. That is the one awkward step here, and it is upstream's to
    /// remove: `pathForContract` would need to take a root.
    /// @param vm The Vm instance for file operations.
    /// @param outputRoot Where the snapshot should end up.
    /// @param dir The snapshot directory name — a release tag, or `CANDIDATE`.
    /// @param contractName The contract the snapshot describes.
    /// @param creationCode That contract's creation code.
    /// @return The path written.
    function writeSnapshot(
        Vm vm,
        string memory outputRoot,
        string memory dir,
        string memory contractName,
        bytes memory creationCode
    ) internal returns (string memory) {
        LibRainDeploy.etchZoltuFactory(vm);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(dirForSnapshot(dir), true);

        address deployed = LibRainDeploy.deployZoltu(creationCode);

        LibFs.buildFileForContract(
            vm,
            deployed,
            snapshotName(dir, contractName),
            string.concat(
                LibCodeGen.addressConstantString(
                    vm,
                    "/// @dev The deterministic deploy address of the contract when deployed via\n/// the Zoltu factory.",
                    "DEPLOYED_ADDRESS",
                    deployed
                ),
                LibCodeGen.bytesConstantString(
                    vm, "/// @dev The creation bytecode of the contract.", "CREATION_CODE", creationCode
                ),
                LibCodeGen.bytesConstantString(
                    vm, "/// @dev The runtime bytecode of the contract.", "RUNTIME_CODE", deployed.code
                )
            )
        );

        string memory written = pathForSnapshot(dir, contractName);
        if (keccak256(bytes(outputRoot)) == keccak256(bytes(LIB_FS_ROOT))) {
            return written;
        }

        string memory destDir = string.concat(outputRoot, "/", dir);
        string memory dest = string.concat(destDir, "/", contractName, ".sol");
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(destDir, true);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(dest, vm.readFile(written));
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(dirForSnapshot(dir), true);
        return dest;
    }

    /// Regenerate the rolling snapshot and freeze it as this release's record,
    /// in that order, in one call.
    ///
    /// Every guard runs before anything is written:
    ///
    /// - the version must be strict `X.Y.Z` (`deployTag`)
    /// - this release must not already be frozen — a release is cut once
    /// - there must be something to freeze after regenerating
    ///
    /// The frozen copy is the bytes just regenerated, read back from disk, so
    /// "the record matches the candidate" is true by construction rather than
    /// by a comparison afterwards.
    /// @param vm The Vm instance for file operations.
    /// @param regenerate Rewrites the rolling snapshot. Run first, always.
    /// @param contractNames The contracts whose generated files form this
    /// release's record.
    function freeze(Vm vm, function() internal regenerate, string[] memory contractNames) internal {
        string memory tag = deployTag(vm);
        string memory frozenDir = dirForSnapshot(tag);
        if (vm.exists(frozenDir)) {
            revert SnapshotAlreadyFrozen(tag, frozenDir);
        }

        regenerate();

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(frozenDir, true);
        for (uint256 i = 0; i < contractNames.length; i++) {
            string memory rollingPath = pathForSnapshot(CANDIDATE, contractNames[i]);
            if (!vm.exists(rollingPath)) {
                revert NothingToFreeze(rollingPath);
            }
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.writeFile(pathForSnapshot(tag, contractNames[i]), vm.readFile(rollingPath));
        }
    }
}
