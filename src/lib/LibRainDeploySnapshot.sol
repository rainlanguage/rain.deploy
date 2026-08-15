// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.16.1/src/Vm.sol";
import {LibCodeGen} from "rain-sol-codegen-0.1.6/src/lib/LibCodeGen.sol";
import {LibFs} from "rain-sol-codegen-0.1.6/src/lib/LibFs.sol";
import {DeploySuite} from "../abstract/RainDeploySuitesBase.sol";
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

/// Thrown when a freeze names no contracts. There would be nothing to write, so
/// it would leave `<tag>/` empty and report success — and an empty `<tag>/` is
/// still a frozen tag, which `SnapshotAlreadyFrozen` then refuses the real cut
/// of forever. A release lost to a directory with nothing in it.
/// @param tag The release tag that was being cut.
error EmptyRelease(string tag);

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

    /// Where every generated non-snapshot lib is written — the alias libs, the
    /// per-contract released libs and the aggregate over them.
    ///
    /// ONE constant rather than one per writer, because the aggregate imports
    /// the per-contract libs as `./Lib<Contract>Released.sol` — a sibling path,
    /// which is only a sibling path while both writers agree on this directory.
    /// Two spellings of it is a generated file that stops compiling the moment
    /// one of them moves.
    string constant LIB_DIR = "src/lib";

    /// The generated aggregate's library name, and the file it is written to.
    ///
    /// Named rather than derived from a contract, because it is the ONE lib per
    /// repo that is about no single contract: it is the whole released
    /// declaration. Spelled once here because the emitted source, the path and
    /// the tests that check the committed file against the emitter all have to
    /// mean the same file.
    string constant RELEASED_SUITES_LIBRARY = "LibReleasedSuites";

    /// The path of a generated lib, from the directory it goes in and its
    /// library name.
    /// @param libDir The directory the generated libs go in.
    /// @param libraryName The generated library's name.
    /// @return The path.
    function pathForLib(string memory libDir, string memory libraryName) internal pure returns (string memory) {
        return string.concat(libDir, "/", libraryName, ".sol");
    }

    /// The path of a generated lib in a repo's real `LIB_DIR`.
    /// @param libraryName The generated library's name.
    /// @return The path.
    function pathForLib(string memory libraryName) internal pure returns (string memory) {
        return pathForLib(LIB_DIR, libraryName);
    }

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

    /// The constants a snapshot declares below the `BYTECODE_HASH` that
    /// `LibFs.buildFileForContract` writes itself: the deploy address, the
    /// creation code, the runtime code and the frozen dependency list, in that
    /// order.
    ///
    /// Split out of `writeSnapshot` rather than inlined there because the
    /// deployed address, the creation code, the dependency list and the two
    /// names `LibFs` needs are more live values than the legacy codegen has
    /// stack for. Splitting the emission from the deploy-and-write is the
    /// division that falls out of that, and it puts the file's whole shape in
    /// one expression.
    /// @param vm The Vm instance for string operations.
    /// @param deployed The address the creation code deployed to.
    /// @param creationCode The contract's creation code.
    /// @param dependencies The addresses that must already have code on a
    /// network before this contract can be broadcast there.
    /// @return The constants, as Solidity source.
    function snapshotConstants(Vm vm, address deployed, bytes memory creationCode, address[] memory dependencies)
        internal
        view
        returns (string memory)
    {
        return string.concat(
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
            ),
            LibCodeGen.bytesConstantString(
                vm,
                "/// @dev The addresses that MUST already have code on a network before\n"
                "/// this release can be broadcast there, `abi.encode`d as an `address[]`\n"
                "/// because Solidity has no file-scope constant of dynamic array type.",
                "DEPENDENCIES",
                abi.encode(dependencies)
            )
        );
    }

    /// Generate one snapshot for one contract.
    ///
    /// There is no output root to choose. `LibFs.pathForContract` hardcodes
    /// `LIB_FS_ROOT` and takes a contract name rather than a path, and this is
    /// the repo's real deploy record, which belongs under that root and nowhere
    /// else. A test that wants a record tree of its own writes one with
    /// `vm.writeFile` and reads it with `frozenSnapshotPaths`, which does take a
    /// root, because reading somebody else's tree is a thing a walk genuinely
    /// does and writing this repo's record somewhere else is not.
    ///
    /// The dependency list is frozen here with the rest, and it is not
    /// metadata. `RainDeployBroadcast.run` hands a suite's `dependencies` to
    /// `LibRainDeploy.deployToNetworks`, which refuses to broadcast on any
    /// network where one of them has no code — so it is a precondition of the
    /// deployment, decided when the release is cut. Re-broadcasting a past
    /// release onto a newly supported chain has to check the list THAT release
    /// was cut with; regenerating it from current source would drop a
    /// dependency an old release still needs the moment current source stops
    /// needing it, and impose a new one on a release that never had it.
    ///
    /// `abi.encode`d because Solidity has no file-scope constant of dynamic
    /// array type. The consumer is `releasedLibraryBlock`, which emits the
    /// matching `abi.decode`.
    /// @param vm The Vm instance for file operations.
    /// @param dir The snapshot directory name — a release tag, or `CANDIDATE`.
    /// @param contractName The contract the snapshot describes.
    /// @param creationCode That contract's creation code.
    /// @param dependencies The addresses that must already have code on a
    /// network before this contract can be broadcast there.
    /// @return The path written.
    function writeSnapshot(
        Vm vm,
        string memory dir,
        string memory contractName,
        bytes memory creationCode,
        address[] memory dependencies
    ) internal returns (string memory) {
        LibRainDeploy.etchZoltuFactory(vm);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(dirForSnapshot(dir), true);

        address deployed = LibRainDeploy.deployZoltu(creationCode);

        LibFs.buildFileForContract(
            vm, deployed, snapshotName(dir, contractName), snapshotConstants(vm, deployed, creationCode, dependencies)
        );

        return pathForSnapshot(dir, contractName);
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
        string memory path = pathForLib(libraryName);

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

    /// The release tag a record path sits under.
    /// @param vm The Vm instance for string operations.
    /// @param path A record file, as `frozenSnapshotPaths` returns it.
    /// @return The tag, e.g. `0_1_7`.
    function tagForRecordPath(Vm vm, string memory path) internal pure returns (string memory) {
        string[] memory components = vm.split(path, "/");
        return components[components.length - 2];
    }

    /// The contract a record path names.
    /// @param vm The Vm instance for string operations.
    /// @param path A record file, as `frozenSnapshotPaths` returns it.
    /// @return The contract name, e.g. `AddressRegistry`.
    function contractForRecordPath(Vm vm, string memory path) internal pure returns (string memory) {
        string[] memory components = vm.split(path, "/");
        return vm.replace(components[components.length - 1], ".sol", "");
    }

    /// The alias prefix a record's four constants are imported under.
    ///
    /// Both the tag and the contract, because a release freezes every contract
    /// it names into one directory: the tag alone collides the moment a repo
    /// releases two contracts together, and a collision here is a generated
    /// file that does not compile.
    /// @param vm The Vm instance for string operations.
    /// @param path A record file, as `frozenSnapshotPaths` returns it.
    /// @return The prefix, e.g. `AddressRegistry_0_1_7`.
    function releasedConstantPrefix(Vm vm, string memory path) internal pure returns (string memory) {
        return string.concat(contractForRecordPath(vm, path), "_", tagForRecordPath(vm, path));
    }

    /// Whether record file `a` is emitted before record file `b`: by release
    /// tag, then by path.
    ///
    /// Tags compare as VERSIONS rather than as text — `0_10_0` follows `0_9_0`
    /// as a release and precedes it as a string, so a text comparison misorders
    /// every record that outlives a single-digit minor. Both tags are `isTag`,
    /// so every component is a run of digits `parseUint` reads.
    ///
    /// The tie break is the path, byte for byte, so two contracts frozen under
    /// one tag have an order at all. The walk's own order is the filesystem's,
    /// and a generated file that changes with it is a diff on every build.
    /// @param vm The Vm instance for string operations.
    /// @param a A record file.
    /// @param b A record file.
    /// @return Whether `a` precedes `b`.
    function recordPrecedes(Vm vm, string memory a, string memory b) internal pure returns (bool) {
        string[] memory left = vm.split(tagForRecordPath(vm, a), "_");
        string[] memory right = vm.split(tagForRecordPath(vm, b), "_");
        for (uint256 i = 0; i < left.length; i++) {
            uint256 leftComponent = vm.parseUint(left[i]);
            uint256 rightComponent = vm.parseUint(right[i]);
            if (leftComponent != rightComponent) {
                return leftComponent < rightComponent;
            }
        }

        bytes memory aBytes = bytes(a);
        bytes memory bBytes = bytes(b);
        uint256 shortest = aBytes.length < bBytes.length ? aBytes.length : bBytes.length;
        for (uint256 i = 0; i < shortest; i++) {
            if (aBytes[i] != bBytes[i]) {
                return aBytes[i] < bBytes[i];
            }
        }
        return aBytes.length < bBytes.length;
    }

    /// The record's files in the order they are emitted.
    ///
    /// An insertion sort, because a record is one directory per release and
    /// nothing sorts a list that short faster than it takes to say so.
    /// @param vm The Vm instance for string operations.
    /// @param paths The record's files, in any order.
    /// @return sorted The same files, in release order.
    function sortedRecordPaths(Vm vm, string[] memory paths) internal pure returns (string[] memory sorted) {
        sorted = new string[](paths.length);
        for (uint256 i = 0; i < paths.length; i++) {
            uint256 j = i;
            while (j > 0 && recordPrecedes(vm, paths[i], sorted[j - 1])) {
                sorted[j] = sorted[j - 1];
                j--;
            }
            sorted[j] = paths[i];
        }
    }

    /// One contract's releases out of a record, in tag order.
    ///
    /// The record holds every contract a repo has ever frozen, and `freeze`
    /// takes a LIST of contract names, so a release of two contracts writes two
    /// files under one tag. A released-suites lib describes one contract, so it
    /// has to select rather than take the record whole: emitting another
    /// contract's snapshot into it would give that entry this contract's suite
    /// key, which collides with this contract's own entry for the same tag and
    /// reverts `allSuites()` with `DuplicateDeploySuite`. A repo with one
    /// contract never sees it, which is exactly why it is selected here rather
    /// than left to be discovered by the first repo that freezes two.
    /// @param vm The Vm instance for file operations.
    /// @param recordRoot The record root to read releases from.
    /// @param contractName The contract to select.
    /// @return This contract's record paths, in tag order.
    function recordPathsForContract(Vm vm, string memory recordRoot, string memory contractName)
        internal
        view
        returns (string[] memory)
    {
        string[] memory paths = frozenSnapshotPaths(vm, recordRoot);

        string[] memory found = new string[](paths.length);
        uint256 count = 0;
        for (uint256 i = 0; i < paths.length; i++) {
            if (keccak256(bytes(contractForRecordPath(vm, paths[i]))) != keccak256(bytes(contractName))) {
                continue;
            }
            found[count] = paths[i];
            count++;
        }

        string[] memory selected = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            selected[i] = found[i];
        }
        return sortedRecordPaths(vm, selected);
    }

    /// The name of the generated lib that declares ONE contract's releases.
    ///
    /// Spelled once because two emitters have to agree on it: the writer that
    /// emits that lib, and the aggregate that imports it. A second spelling is
    /// an aggregate importing a file nothing ever wrote — which does not
    /// compile, but only for the repo that regenerates, and the point of
    /// generating the aggregate is that nobody has to.
    /// @param contractName The contract the released record describes.
    /// @return The library name, e.g. `LibAddressRegistryReleased`.
    function releasedLibraryName(string memory contractName) internal pure returns (string memory) {
        return string.concat("Lib", contractName, "Released");
    }

    /// The aliased import one record file contributes: all four consensus
    /// fields and the frozen dependency list, under that release's prefix.
    ///
    /// Split per file rather than inlined into the block for the same reason
    /// `snapshotConstants` is split out of `writeSnapshot`: five aliases and
    /// the path they come from are more live values than the legacy codegen has
    /// stack for.
    /// @param vm The Vm instance for string operations.
    /// @param path A record file, as `frozenSnapshotPaths` returns it.
    /// @return The import statement, and the blank line after it.
    function releasedImport(Vm vm, string memory path) internal pure returns (string memory) {
        string memory prefix = releasedConstantPrefix(vm, path);
        return string.concat(
            "import {\n    DEPLOYED_ADDRESS as ",
            prefix,
            "_DEPLOYED_ADDRESS,\n    BYTECODE_HASH as ",
            prefix,
            "_BYTECODE_HASH,\n    CREATION_CODE as ",
            prefix,
            "_CREATION_CODE,\n    RUNTIME_CODE as ",
            prefix,
            "_RUNTIME_CODE,\n    DEPENDENCIES as ",
            prefix,
            "_DEPENDENCIES\n} from \"../generated/",
            tagForRecordPath(vm, path),
            "/",
            contractForRecordPath(vm, path),
            ".sol\";\n\n"
        );
    }

    /// The import block of a generated released-suites lib.
    ///
    /// One aliased import per record file, carrying all four consensus fields
    /// and the frozen dependency list. A released entry can therefore only say
    /// what its own frozen snapshot says — there is no path by which a released
    /// address, code hash, creation code, runtime code or dependency list is
    /// written anywhere but into the immutable record.
    /// @param vm The Vm instance for string operations.
    /// @param paths The record's files, in the order they are emitted.
    /// @return imports The import block.
    function releasedImportBlock(Vm vm, string[] memory paths) internal pure returns (string memory imports) {
        imports = "import {DeploySuite} from \"../abstract/RainDeploySuitesBase.sol\";\n\n";
        for (uint256 i = 0; i < paths.length; i++) {
            imports = string.concat(imports, releasedImport(vm, paths[i]));
        }
    }

    /// The library block of a generated released-suites lib.
    ///
    /// FIVE fields per entry alias the frozen snapshot: the four consensus
    /// fields and the dependency list. The dependency list is aliased rather
    /// than rebuilt from `template` because it is a precondition of the
    /// deployment and not metadata — `RainDeployBroadcast.run` passes it to
    /// `LibRainDeploy.deployToNetworks`, which refuses to broadcast on a
    /// network where one of them has no code. Broadcasting a past release onto
    /// a newly supported chain therefore has to check the list that release was
    /// cut with, so it is read from that release's own frozen snapshot.
    ///
    /// The other two come from `template`, the candidate declaration, and are
    /// regenerated from it on every build: the key and the artifact path are
    /// explorer and ordering metadata rather than anything a broadcast acts on,
    /// and preserving what a previous generation wrote would mean parsing
    /// generated Solidity back in.
    ///
    /// The key is the template's with the tag appended, so every entry is
    /// unique and `allSuites`'s duplicate check is satisfied by construction
    /// rather than by whoever writes the declaration.
    /// @param vm The Vm instance for string operations.
    /// @param libraryName The generated library's name.
    /// @param contractName The contract the released record describes.
    /// @param paths The record's files, in the order they are emitted.
    /// @param template The candidate declaration the metadata comes from.
    /// @return The library block.
    function releasedLibraryBlock(
        Vm vm,
        string memory libraryName,
        string memory contractName,
        string[] memory paths,
        DeploySuite memory template
    ) internal pure returns (string memory) {
        string memory entries = "";
        for (uint256 i = 0; i < paths.length; i++) {
            string memory index = vm.toString(i);
            string memory prefix = releasedConstantPrefix(vm, paths[i]);

            entries = string.concat(
                entries,
                "        suites[",
                index,
                "] = DeploySuite({\n            suite: \"",
                template.suite,
                "@",
                tagForRecordPath(vm, paths[i]),
                "\",\n            creationCode: ",
                prefix,
                "_CREATION_CODE,\n            storedDeployedAddress: ",
                prefix,
                "_DEPLOYED_ADDRESS,\n            storedBytecodeHash: ",
                prefix,
                "_BYTECODE_HASH,\n            storedRuntimeCode: ",
                prefix,
                "_RUNTIME_CODE,\n            artifactPath: \"",
                template.artifactPath,
                "\",\n            dependencies: abi.decode(",
                prefix,
                "_DEPENDENCIES, (address[]))\n        });\n"
            );
        }

        return string.concat(
            "/// @title ",
            libraryName,
            "\n/// @notice Every frozen release of `",
            contractName,
            "`: one entry per file in\n" "/// the append-only `src/generated/<tag>/` record, in tag order.\n///\n"
            "/// The deploy address, code hash, creation code, runtime code and dependency\n"
            "/// list of each entry are aliased from that release's own frozen snapshot, so\n"
            "/// what a release deployed, and what it required to already be on chain, are\n"
            "/// read from the immutable file and from nowhere else. A dependency dropped\n"
            "/// from current source stays required by the releases cut with it, and one\n"
            "/// added is not imposed on releases cut without it.\n///\n"
            "/// The key and the artifact path are explorer and ordering metadata\n"
            "/// regenerated from the CURRENT declaration, and are not part of that\n"
            "/// record. A moved source path retroactively updates every entry's artifact\n"
            "/// path, which is intended: the alternative is parsing this generated file\n"
            "/// back in to preserve what it last said.\nlibrary ",
            libraryName,
            " {\n    /// Every frozen release, in tag order.\n" "    /// @return suites The released suites.\n"
            "    function releasedSuites() internal pure returns (DeploySuite[] memory suites) {\n"
            "        suites = new DeploySuite[](",
            vm.toString(paths.length),
            ");\n",
            entries,
            "    }\n}\n"
        );
    }

    /// Generate the released-suites lib for a repo's frozen record: the
    /// declaration of what this repo has released, emitted from the record
    /// itself.
    ///
    /// The record and the declaration of it are produced by ONE call, so a
    /// release that `src/generated/<tag>/` holds is a release `releasedSuites()`
    /// names. A hand-written declaration is the one thing that can silently
    /// drop a release out of every check there is — `RainDeployVerifySnapshot`
    /// checks the declaration against the record precisely because nothing else
    /// would notice, and generating both here is what makes that check pass by
    /// construction rather than by remembering.
    ///
    /// Written beside the alias lib, under the same `Lib<Contract>` naming, so
    /// all generated non-snapshot Solidity is in one directory.
    ///
    /// Five fields per entry come from the frozen snapshot and two from
    /// `template`. Those two — the key and the artifact path — are explorer and
    /// ordering metadata regenerated from the CURRENT declaration on every
    /// build, NOT part of the frozen record. Moving a source file retroactively
    /// updates the artifact path of every entry, including releases cut years
    /// ago, which is intended: the alternative is parsing the previously
    /// generated Solidity back in to preserve what it said.
    ///
    /// The dependency list is deliberately NOT among them. It is what a
    /// broadcast checks is already on chain before it deploys anything, so
    /// regenerating it from current source would mean re-broadcasting a past
    /// release onto a new chain under today's preconditions rather than the
    /// ones that release was cut with. It is frozen into the snapshot by
    /// `writeSnapshot` and aliased back out here.
    /// @param vm The Vm instance for file operations.
    /// @param recordRoot The record root to read releases from — `LIB_FS_ROOT`
    /// for a repo's real record. A parameter for the same reason
    /// `frozenSnapshotPaths` takes one: a writer that can only be pointed at
    /// the real record can only be tested against it, and a repo that has cut
    /// no release has nothing there to test against.
    /// @param contractName The contract the released record describes.
    /// @param template The candidate declaration the metadata comes from.
    /// @return The path written.
    function writeReleasedSuitesLib(
        Vm vm,
        string memory recordRoot,
        string memory contractName,
        DeploySuite memory template
    ) internal returns (string memory) {
        string memory libraryName = releasedLibraryName(contractName);
        string memory path = pathForLib(libraryName);
        string[] memory paths = recordPathsForContract(vm, recordRoot, contractName);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(
            path,
            string.concat(
                LibCodeGen.filePrefix(),
                "\n",
                releasedImportBlock(vm, paths),
                releasedLibraryBlock(vm, libraryName, contractName, paths, template)
            )
        );
        return path;
    }

    /// The import block of the generated aggregate lib.
    ///
    /// One import per contract, of the released lib `writeReleasedSuitesLib`
    /// emitted for it, by sibling path — both writers emit into `LIB_DIR`, and
    /// naming the sibling rather than the directory is what keeps that true of
    /// a repo that moves the directory.
    /// @param contractNames The contracts whose released libs to aggregate.
    /// @return imports The import block.
    function aggregateImportBlock(string[] memory contractNames) internal pure returns (string memory imports) {
        imports = "import {DeploySuite} from \"../abstract/RainDeploySuitesBase.sol\";\n\n";
        for (uint256 i = 0; i < contractNames.length; i++) {
            string memory libraryName = releasedLibraryName(contractNames[i]);
            imports = string.concat(imports, "import {", libraryName, "} from \"./", libraryName, ".sol\";\n\n");
        }
    }

    /// The library block of the generated aggregate lib: every per-contract
    /// released lib read once and copied into one array, in declaration order.
    ///
    /// It emits the concatenation rather than computing one, because the
    /// entries are only known when the emitted source RUNS: a released lib
    /// declares its own releases, and how many it has is not a thing this
    /// emitter can see or should have to. So the lengths are summed and the
    /// offsets are spelled as expressions over them.
    ///
    /// A repo with no generated contracts emits a lib returning an empty array.
    /// That is the state of a deploy repo whose declaration is not written yet,
    /// and it MUST compile: the aggregate is imported by ordinary source, so a
    /// repo that could not emit one could not build to get to the point of
    /// declaring anything.
    /// @param vm The Vm instance for string operations.
    /// @param contractNames The contracts whose released libs to aggregate.
    /// @return The library block.
    function aggregateLibraryBlock(Vm vm, string[] memory contractNames) internal pure returns (string memory) {
        string memory locals = "";
        string memory copies = "";
        // The running sum of the lengths already emitted: the whole array's
        // length once the loop is done, and the OFFSET of the contract the loop
        // is on before its own length is added to it.
        string memory total = "";

        for (uint256 i = 0; i < contractNames.length; i++) {
            string memory local = string.concat("released", vm.toString(i));

            locals = string.concat(
                locals,
                "        DeploySuite[] memory ",
                local,
                " = ",
                releasedLibraryName(contractNames[i]),
                ".releasedSuites();\n"
            );

            copies = string.concat(
                copies,
                "        for (uint256 i = 0; i < ",
                local,
                ".length; i++) {\n            suites[",
                bytes(total).length == 0 ? "" : string.concat(total, " + "),
                "i] = ",
                local,
                "[i];\n        }\n"
            );

            total = string.concat(total, bytes(total).length == 0 ? "" : " + ", local, ".length");
        }

        return string.concat(
            "/// @title ",
            RELEASED_SUITES_LIBRARY,
            "\n/// @notice Every frozen release this repo has cut, of every contract it\n",
            "/// deploys: the per-contract released libs concatenated, in declaration\n",
            "/// order.\n///\n",
            "/// There is one released lib per deployed contract because a release freezes\n",
            "/// every contract it names into a single tag directory, so a lib that took\n",
            "/// the record whole would give another contract's snapshot this contract's\n",
            "/// suite key and collide with its own entry for that tag. This is where\n",
            "/// those libs meet, and it is emitted from the same list that wrote them --\n",
            "/// so a contract that is generated, aliased and frozen cannot be missing\n",
            "/// from the declaration, and a release missing from the declaration is a\n",
            "/// release every check quietly stops asking about.\nlibrary ",
            RELEASED_SUITES_LIBRARY,
            " {\n    /// Every released suite, in declaration order.\n",
            "    /// @return suites The released suites.\n",
            "    function releasedSuites() internal pure returns (DeploySuite[] memory suites) {\n",
            contractNames.length == 0
                ? "        suites = new DeploySuite[](0);\n"
                : string.concat(locals, "\n        suites = new DeploySuite[](", total, ");\n\n", copies),
            "    }\n}\n"
        );
    }

    /// Generate the ONE released-suites lib a repo's declaration reads: the
    /// per-contract libs concatenated, emitted from the same list that wrote
    /// them.
    ///
    /// The concatenation is the LAST place a contract could be generated,
    /// aliased and frozen and still be absent from the declaration. Written by
    /// hand it is also the only one of those places nothing enforces: a
    /// candidate with no snapshot and a snapshot with no candidate both fail
    /// the shape assertions, and a missing generated file fails to compile,
    /// while a released lib that exists and is concatenated nowhere compiles
    /// cleanly, is read by nothing, and leaves the whole suite green until the
    /// release that first freezes that contract — at which point the record
    /// check fails the release job with the tag already pushed.
    ///
    /// So it is emitted rather than written, from the one list everything else
    /// reads, and there is no fourth place.
    ///
    /// Written beside the libs it imports, which is what makes those imports
    /// sibling paths.
    /// @param vm The Vm instance for file operations.
    /// @param libDir The directory the per-contract released libs were written
    /// to, which this is written into as well — `LIB_DIR` for a repo's real
    /// libs. A parameter for the same reason `writeReleasedSuitesLib` takes a
    /// record root: a writer that can only be pointed at the committed
    /// declaration can only be tested by overwriting it, and a test that
    /// overwrites a file the rest of the suite reads is a test that fails on
    /// timing. Sibling imports are what make any directory correct, so the
    /// caller's only obligation is to name the one the released libs went to.
    /// @param contractNames The contracts whose released libs to aggregate.
    /// @return The path written.
    function writeReleasedSuitesAggregate(Vm vm, string memory libDir, string[] memory contractNames)
        internal
        returns (string memory)
    {
        string memory path = pathForLib(libDir, RELEASED_SUITES_LIBRARY);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(
            path,
            string.concat(
                LibCodeGen.filePrefix(),
                "\n",
                aggregateImportBlock(contractNames),
                aggregateLibraryBlock(vm, contractNames)
            )
        );
        return path;
    }

    /// Regenerate the rolling snapshot and freeze it as this release's record,
    /// in that order, in one call.
    ///
    /// Every guard runs, and every byte that will be written is in hand, BEFORE
    /// `<tag>/` is created. That ordering is load bearing rather than tidy.
    /// Filesystem cheatcodes are not undone by a revert, so a throw once the
    /// directory exists leaves a partial record behind — and a partial record is
    /// a frozen tag, which `SnapshotAlreadyFrozen` then refuses the retry of.
    /// The only exit from that state is deleting a directory this design calls
    /// append-only, so the release is wedged by the failure rather than merely
    /// stopped by it.
    ///
    /// The guards, in order:
    ///
    /// - the version must be strict `X.Y.Z` (`deployTag`)
    /// - this release must not already be frozen — a release is cut once
    /// - the release must name at least one contract, because a release with no
    ///   record is not a release and freezing one wedges the tag exactly as a
    ///   partial write does
    /// - every named contract must have a rolling snapshot, once regenerated
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
        if (contractNames.length == 0) {
            revert EmptyRelease(tag);
        }

        regenerate();

        // Read the whole record before writing any of it. Every reason this
        // call can fail is now behind it, so what follows is writes only.
        string[] memory records = new string[](contractNames.length);
        for (uint256 i = 0; i < contractNames.length; i++) {
            string memory rollingPath = pathForSnapshot(CANDIDATE, contractNames[i]);
            if (!vm.exists(rollingPath)) {
                revert NothingToFreeze(rollingPath);
            }
            records[i] = vm.readFile(rollingPath);
        }

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(frozenDir, true);
        for (uint256 i = 0; i < contractNames.length; i++) {
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.writeFile(pathForSnapshot(tag, contractNames[i]), records[i]);
        }
    }
}
