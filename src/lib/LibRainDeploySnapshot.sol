// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.16.1/src/Vm.sol";
import {LibCodeGen} from "rain-sol-codegen-0.1.6/src/lib/LibCodeGen.sol";
import {LibFs} from "rain-sol-codegen-0.1.6/src/lib/LibFs.sol";
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

/// Thrown when generating to a non-default output root would have to stage
/// through a `src/generated/` directory that already exists. Staging removes
/// that directory afterwards, so proceeding would recursively delete content
/// this call did not create — a real frozen release, if the name collided.
/// @param dir The colliding directory.
/// @param path The staging path under `src/generated/`.
error SnapshotScratchDirCollision(string dir, string path);

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
    /// @param vm The Vm instance for file operations.
    /// @return The tag.
    function deployTag(Vm vm) internal view returns (string memory) {
        return tagForVersion(vm.parseTomlString(vm.readFile("foundry.toml"), ".package.version"));
    }

    /// Whether `subject` is three non-empty runs of digits joined by exactly
    /// two `separator`s.
    ///
    /// The ONE definition of the release-version shape. It is asked with `.`
    /// for a version out of `foundry.toml` and with `_` for the directory that
    /// version freezes to, so what `tagForVersion` accepts and what
    /// `frozenSnapshotPaths` recognises as a release cannot drift apart. Two
    /// spellings of one rule is how a version becomes freezable to a directory
    /// the record then ignores.
    /// @param subject The string to test.
    /// @param separator The component separator: `.` for a version, `_` for a
    /// tag.
    /// @return Whether it has the shape.
    function isStrictTriple(string memory subject, bytes1 separator) internal pure returns (bool) {
        bytes memory subjectBytes = bytes(subject);

        uint256 separators = 0;
        uint256 digitsInComponent = 0;
        for (uint256 i = 0; i < subjectBytes.length; i++) {
            bytes1 char = subjectBytes[i];
            if (char == separator) {
                // No leading separator, and no empty component.
                if (digitsInComponent == 0) {
                    return false;
                }
                separators++;
                digitsInComponent = 0;
            } else if (char >= "0" && char <= "9") {
                digitsInComponent++;
            } else {
                return false;
            }
        }
        // Exactly two separators, and no trailing one.
        return separators == 2 && digitsInComponent > 0;
    }

    /// Whether a directory under a record root is a frozen release.
    ///
    /// A release directory is named by `tagForVersion`, so being tag shaped is
    /// what makes a directory a release. The rolling `candidate/` is not a
    /// release and is excluded by the same rule that admits every real one,
    /// rather than by a name this would have to remember to exclude.
    /// @param dir The directory name, e.g. `0_1_7`.
    /// @return Whether it is a release tag.
    function isTag(string memory dir) internal pure returns (bool) {
        return isStrictTriple(dir, "_");
    }

    /// The directory form of a release version, refusing anything that is not
    /// strict `X.Y.Z`.
    ///
    /// Split from `deployTag` so the refusal is reachable without writing a
    /// `foundry.toml`: a guard that cannot be exercised is a guard nobody knows
    /// works. `0.1.7-rc1` maps to `0_1_7-rc1`, a directory `isTag` does not
    /// recognise and the record therefore ignores forever — an orphan snapshot
    /// nothing protects — so it is refused rather than frozen.
    /// @param version The version string, e.g. `0.1.7`.
    /// @return The tag, e.g. `0_1_7`.
    function tagForVersion(string memory version) internal pure returns (string memory) {
        if (!isStrictTriple(version, ".")) {
            revert UnreleasableVersion(version);
        }

        bytes memory versionBytes = bytes(version);
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

    /// Every file in the FROZEN record: everything inside a release-tag
    /// directory under `root`.
    ///
    /// The record is the directory tree, not a list. `freeze` writes one
    /// directory per release and removes none, so the tree is the complete
    /// history of what a repo has released and is the only description of it
    /// that cannot fall behind. Anything that reads a repo's own declaration of
    /// what it has released has to be checkable against this, or a release
    /// nobody declared is a release nothing verifies.
    ///
    /// Two rules, and both are the shape `freeze` writes:
    ///
    /// - the directory is tag shaped (`isTag`), which is what a release
    ///   directory is named by. `candidate/` is not a release and falls out
    ///   here, as does a scratch directory a test or a human left behind.
    /// - the entry is a file directly inside it. Everything in a release
    ///   directory belongs to that release's record — there is no extension to
    ///   filter on, because nothing else has any business being in there.
    /// @param vm The Vm instance for file operations.
    /// @param root The record root — `LIB_FS_ROOT` for a repo's real record.
    /// @return paths Every frozen record file.
    function frozenSnapshotPaths(Vm vm, string memory root) internal view returns (string[] memory paths) {
        // A repo with no generated directory at all has released nothing. That
        // is a real state — it is this repo's own, before its first release —
        // rather than a missing file to fail on.
        if (!vm.exists(root)) {
            return new string[](0);
        }

        Vm.DirEntry[] memory entries = vm.readDir(root, 2);

        string[] memory found = new string[](entries.length);
        uint256 count = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].isDir || entries[i].depth != 2) {
                continue;
            }
            string[] memory components = vm.split(entries[i].path, "/");
            string memory tag = components[components.length - 2];
            if (!isTag(tag)) {
                continue;
            }
            // Rebuilt from `root` rather than taken from the entry, which
            // `readDir` spells absolutely. A record path is compared against a
            // repo's own paths and named in a failure, so it has to be the
            // repo-relative one every other path here is — and at depth 2 the
            // last two components are the whole of what is below `root`.
            found[count] = string.concat(root, "/", tag, "/", components[components.length - 1]);
            count++;
        }

        paths = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            paths[i] = found[i];
        }
    }

    /// Generate one snapshot for one contract, under an arbitrary output root.
    ///
    /// The root is a parameter because a repo generates real deploy records
    /// under `src/generated/` and test records under `test/generated/`, and
    /// both must come from THIS code path — a second emitter would make the
    /// shape assertions a statement about the wrong generator.
    ///
    /// `LibFs` hardcodes `src/generated/` and takes a contract name rather than
    /// a path, so a non-default root is reached by STAGING there and moving the
    /// result, then removing the staging directory. That recursive removal is
    /// the sharp edge: it is under `src/generated/`, where real frozen releases
    /// live. It is guarded by refusing to stage through a directory that
    /// already exists, so a name collision fails loudly instead of deleting a
    /// release.
    ///
    /// The guard exists because the clean fix is upstream and not ours:
    /// `LibFs.pathForContract` needs to take an output root
    /// (`pathForContract(string root, string contractName)`), with
    /// `buildFileForContract` passing it through. Then a caller writes directly
    /// to `test/generated/` and there is no staging, no copy and no removal at
    /// all.
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
        bool staging = keccak256(bytes(outputRoot)) != keccak256(bytes(LIB_FS_ROOT));
        // Staging ends by removing the directory, so it must not begin with one
        // that already exists. A test snapshot whose `dir` collided with a real
        // frozen tag would otherwise destroy it.
        if (staging && vm.exists(dirForSnapshot(dir))) {
            revert SnapshotScratchDirCollision(dir, dirForSnapshot(dir));
        }

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
        if (!staging) {
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

    /// The import block of a generated alias lib.
    /// @param contractName The contract the snapshot describes.
    /// @param constantPrefix The prefix for the emitted constants.
    /// @param dir The snapshot directory to alias.
    /// @return The import block.
    function aliasImportBlock(string memory contractName, string memory constantPrefix, string memory dir)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "import {\n    DEPLOYED_ADDRESS as ",
            constantPrefix,
            "_ADDR,\n    BYTECODE_HASH as ",
            constantPrefix,
            "_HASH\n} from \"../generated/",
            dir,
            "/",
            contractName,
            ".sol\";\n\n"
        );
    }

    /// The library block of a generated alias lib.
    /// @param contractName The contract the snapshot describes.
    /// @param constantPrefix The prefix for the emitted constants.
    /// @param libraryName The generated library's name.
    /// @return The library block.
    function aliasLibraryBlock(string memory contractName, string memory constantPrefix, string memory libraryName)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "/// @title ",
            libraryName,
            "\n/// @notice The deterministic Zoltu deploy address and code hash of\n/// `",
            contractName,
            "`, aliased from its generated snapshot so that snapshot stays the\n",
            "/// single source of truth. The import path never moves, so consumers are\n",
            "/// unaffected by which snapshot it names.\nlibrary ",
            libraryName,
            " {\n    address constant ",
            constantPrefix,
            "_DEPLOYED_ADDRESS = ",
            constantPrefix,
            "_ADDR;\n    bytes32 constant ",
            constantPrefix,
            "_DEPLOYED_CODEHASH = ",
            constantPrefix,
            "_HASH;\n}\n"
        );
    }

    /// Generate the alias lib for a snapshot: the stable, consumer-facing
    /// import path that re-exports one snapshot's address and code hash.
    ///
    /// Every deploy repo needs exactly this file and only four things differ,
    /// three of which follow from the first — `rain.factory.deploy`'s
    /// `LibCloneFactoryDeploy` is this shape to the character. Emitted here so
    /// that ~20 lines of `vm.writeLine` are not copied into every repo and then
    /// drifted.
    ///
    /// The constant prefix is passed rather than derived. Deriving
    /// `ADDRESS_REGISTRY` from `AddressRegistry` means camelCase to
    /// SCREAMING_SNAKE in Solidity, which is a byte loop with an acronym
    /// problem, to save a caller one short string. The library name and output
    /// path ARE derived, because `Lib<Contract>Deploy` at `src/lib/` is
    /// mechanical.
    ///
    /// The header comes from `LibCodeGen.filePrefix`, the same one `LibFs`
    /// gives a snapshot, so an alias lib and a snapshot say they are generated
    /// in identical words and neither restates the other.
    /// @param vm The Vm instance for file operations.
    /// @param contractName The contract the snapshot describes.
    /// @param constantPrefix The prefix for the emitted constants, e.g.
    /// `ADDRESS_REGISTRY`.
    /// @param dir The snapshot directory to alias — ordinarily `CANDIDATE`.
    /// @return The path written.
    function writeAliasLib(Vm vm, string memory contractName, string memory constantPrefix, string memory dir)
        internal
        returns (string memory)
    {
        string memory libraryName = string.concat("Lib", contractName, "Deploy");
        string memory path = string.concat("src/lib/", libraryName, ".sol");

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(
            path,
            string.concat(
                LibCodeGen.filePrefix(),
                "\n",
                aliasImportBlock(contractName, constantPrefix, dir),
                aliasLibraryBlock(contractName, constantPrefix, libraryName)
            )
        );
        return path;
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
