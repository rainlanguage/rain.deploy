// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {
    LibCodeGen,
    RAIN_COPYRIGHT_TEXT,
    RAIN_SPDX_LICENSE_IDENTIFIER
} from "rain-sol-codegen-0.1.39/src/lib/LibCodeGen.sol";
import {GENERATED_DIR, LibFs} from "rain-sol-codegen-0.1.39/src/lib/LibFs.sol";
import {DeployDeclaration, DeploySuite} from "../abstract/RainDeploySuitesBase.sol";
import {DeployDependency, LibRainDeploy} from "./LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "./LibRainDeployDeclaration.sol";
import {ZOLTU_MECHANISM_ID} from "./LibRainDeployZoltuMechanism.sol";

/// Thrown when `[external.package].version` is not strict `X.Y.Z`. A version
/// like `0.1.7-rc1` maps to the directory `0_1_7-rc1`, which the append-only
/// gate's tag predicate ignores forever — an orphan snapshot nothing protects.
/// Refused rather than frozen.
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

/// Thrown when a release tag does not strictly follow every tag already frozen
/// in the record. The record is append-only, so a tag frozen out of order can
/// never be removed: `releasedSuites()` declares it forever and the chain group
/// then demands it be live on every supported network forever. Refused at the
/// one place a release identity is minted, rather than discovered afterwards by
/// whoever reads the record and finds a release nobody cut.
/// @param tag The tag being cut.
/// @param newestFrozenTag The newest tag already in the record.
error NonMonotonicRelease(string tag, string newestFrozenTag);

/// Thrown when a record root is not a path this library can place a record at.
/// A root is interpolated into every snapshot path a caller hands it, so one
/// that climbs out of the tree, starts at `/` or is empty makes the paths this
/// library returns paths to somewhere else entirely — and `fs_permissions`, a
/// consuming repo's config rather than this library's argument, the only thing
/// standing between a generated file and an arbitrary location on disk.
/// @param root The rejected root.
error InvalidRecordRoot(string root);

/// Thrown when a file in the frozen record declares no deployed address, declares one as
/// `DEPLOYED_ADDRESS_<x>` where `<x>` is not a chain id in decimal digits without a leading zero, names
/// `DEPLOYED_ADDRESS` or `MECHANISM_DATA` outside a block comment on a line not starting with the writer's
/// declaration of it (a line comment, the SPDX header's licence identifier and copyright text included), declares
/// one whose value is not `0x` and 40 hex digits, bare or in `address(...)`, then `;`, declares one outside the
/// writer's format (`=` fourth of five space-separated tokens, or wrapped onto the next line at the writer's indent),
/// or holds a line break other than `\n` that solc honours.
/// @param path The record file that declares no deployed address, declares one it cannot read, or
/// holds a line break other than `\n`.
error FrozenSnapshotUnreadable(string path);

/// Thrown when a file in the frozen record declares its deployed address more than once.
/// @param path The record file declaring its deployed address more than once.
error FrozenSnapshotAmbiguous(string path);

/// Thrown when a file in the frozen record declares `MECHANISM_DATA` more than once.
/// @param path The record file declaring `MECHANISM_DATA` more than once.
error FrozenSnapshotMechanismDataAmbiguous(string path);

/// Thrown when a file in the frozen record declares its deployed addresses per network, as
/// `DEPLOYED_ADDRESS_<chainId>`, and declares no `MECHANISM_DATA`.
/// @param path The record file.
error FrozenSnapshotMechanismDataMissing(string path);

/// @title LibRainDeploySnapshot
/// @notice Which release is being built, where its record lives, and how it is
/// frozen. Release machinery, not code generation.
///
/// It lives here rather than in `rain-sol-codegen` deliberately. Emitting a
/// Solidity constant is codegen; reading `[external.package].version`, deciding
/// a release directory and making that directory immutable is the deploy
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
/// @dev The consuming repo's `foundry.toml` must declare the release version
/// at `[external.package].version` and grant read access to itself so
/// `deployTag` can read it:
/// `fs_permissions = [{ access = "read", path = "./foundry.toml" }, ...]`
/// alongside read-write access to `./src`.
library LibRainDeploySnapshot {
    /// The rolling snapshot's directory name. A sibling of the frozen tag
    /// directories rather than a file beside them, so `src/generated/` reads as
    /// `candidate/ 0_1_6/ 0_1_7/` and "which one is current" is answered by
    /// looking.
    string constant CANDIDATE = "candidate";

    /// The canonical release tag: `foundry.toml` `[external.package].version`
    /// with dots converted to underscores (`0.1.7` -> `0_1_7`) for the Solidity
    /// directory form. The single definition of the tag form — the version in
    /// `foundry.toml` is the one source of truth for which release is being
    /// built, so every path derives from it rather than restating it.
    /// @param vm The Vm instance for file operations.
    /// @return The tag.
    function deployTag(Vm vm) internal view returns (string memory) {
        return tagForVersion(vm.parseTomlString(vm.readFile("foundry.toml"), ".external.package.version"));
    }

    /// Whether `subject` is three `uint256`s joined by exactly two
    /// `separator`s, each written without a leading zero.
    ///
    /// The ONE definition of the release-version shape. It is asked with `.`
    /// for a version out of `foundry.toml` and with `_` for the directory that
    /// version freezes to, so what `tagForVersion` accepts and what
    /// `frozenSnapshotPaths` recognises as a release cannot drift apart. Two
    /// spellings of one rule is how a version becomes freezable to a directory
    /// the record then ignores.
    ///
    /// A component is a `uint256` and not merely a run of digits, because
    /// `tagPrecedes` reads one back with `parseUint` to order the record. A
    /// component past that range is digits the ordering cannot read, so
    /// admitting it would freeze a directory every ordering read of an
    /// append-only record reverts on.
    /// @param subject The string to test.
    /// @param separator The component separator: `.` for a version, `_` for a
    /// tag.
    /// @return Whether it has the shape.
    function isStrictTriple(string memory subject, bytes1 separator) internal pure returns (bool) {
        bytes memory subjectBytes = bytes(subject);
        bytes1 zero = "0";

        uint256 separators = 0;
        uint256 digitsInComponent = 0;
        uint256 component = 0;
        for (uint256 i = 0; i < subjectBytes.length; i++) {
            bytes1 char = subjectBytes[i];
            if (char == separator) {
                // No leading separator, and no empty component.
                if (digitsInComponent == 0) {
                    return false;
                }
                separators++;
                digitsInComponent = 0;
                component = 0;
            } else if (char >= "0" && char <= "9") {
                // A component is one number, so it has one spelling. `01` and
                // `1` are the same release and would freeze to two directories,
                // neither of which `SnapshotAlreadyFrozen` sees as the other,
                // and which `recordPrecedes` cannot order because they compare
                // equal as versions. `i` is at least 1 wherever
                // `digitsInComponent == 1`, because that digit was read at an
                // earlier index.
                if (digitsInComponent == 1 && subjectBytes[i - 1] == "0") {
                    return false;
                }
                // The parse's own bound rather than a digit count, so exactly
                // the components `parseUint` reads are the ones a release can
                // be cut at.
                uint256 digit = uint256(uint8(char)) - uint256(uint8(zero));
                if (component > (type(uint256).max - digit) / 10) {
                    return false;
                }
                component = component * 10 + digit;
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

    /// The output root `LibFs` writes to, and the only one it can write to.
    ///
    /// `LibFs`'s own constant rather than a copy of its text. Everything here
    /// that names the root — the directory a snapshot is written into, and the
    /// tree the frozen record is walked from — reads it, so a root this library
    /// walks that is not a root it writes to is not a state it can be in. It
    /// was a second constant held equal to `LibFs`'s by an assertion until
    /// `rain-sol-codegen` exported its own; one constant is the thing an
    /// assertion was standing in for.
    string constant LIB_FS_ROOT = GENERATED_DIR;

    /// Reverts unless `root` is a path of record root segments: at least one
    /// segment, separated by single `/`, each of them at least one character
    /// and every character an ASCII letter, a digit, `_`, `$` or `-`.
    ///
    /// That is `LibFs.requireTag`'s alphabet with `-` admitted as well, and a
    /// root is held to it segment by segment for the reason `requireTag` states
    /// of a tag: no character in the set is a path separator and none of them is
    /// `.`, so no segment is `.` or `..` and none reaches past the single
    /// directory it names. Refusing the empty segment is what carries that from
    /// a segment to a path — it takes the leading `/` of an absolute path, the
    /// trailing one, the doubled one, and the empty root itself.
    ///
    /// `requireTag` cannot be asked this, because the separators that make a
    /// path a path are exactly what it refuses; the alphabet BETWEEN them is a
    /// copy of its, held to it byte for byte by
    /// `testRecordRootSegmentIsTheTagAlphabetPlusHyphen`. The `-` is the whole
    /// of the widening and it is what this repo's own roots need: `src/generated`
    /// is tag segments already, while every fixture root the tests build is
    /// `test/generated-<something>` or `test/fixture-record`.
    /// @param root The record root to check.
    function requireRecordRoot(string memory root) internal pure {
        bytes memory rootBytes = bytes(root);
        uint256 segmentLength = 0;
        for (uint256 i = 0; i < rootBytes.length; i++) {
            bytes1 char = rootBytes[i];
            if (char == "/") {
                if (segmentLength == 0) {
                    revert InvalidRecordRoot(root);
                }
                segmentLength = 0;
                continue;
            }
            bool isLetter = (char >= 0x41 && char <= 0x5A) || (char >= 0x61 && char <= 0x7A);
            bool isDigit = char >= 0x30 && char <= 0x39;
            bool isUnderscoreOrDollar = char == 0x5F || char == 0x24;
            if (!(isLetter || isDigit || isUnderscoreOrDollar || char == "-")) {
                revert InvalidRecordRoot(root);
            }
            segmentLength++;
        }
        if (segmentLength == 0) {
            revert InvalidRecordRoot(root);
        }
    }

    /// The directory holding a snapshot, rolling or frozen, under a record
    /// root.
    ///
    /// Refuses a directory name `LibFs` would refuse to write into, through
    /// `LibFs.requireTag` rather than through a rule restated here. A reader
    /// that admitted a name the writer refuses is a reader pointed at a path
    /// nothing can ever have written, and a fixture record that admitted one
    /// would be a fixture of a layout the real record cannot hold.
    ///
    /// The root is checked here too, and this is where it has to be: it is the
    /// one place the root becomes a path, and the two halves of that path are
    /// concatenated caller input. A checked `dir` beside an unchecked root is
    /// only the shorter half of the path confined.
    /// @param root The record root — `LIB_FS_ROOT` for a repo's real record.
    /// MUST be a path of record root segments.
    /// @param dir The snapshot directory name — a release tag, or `CANDIDATE`.
    /// MUST be drawn from `LibFs`'s tag alphabet.
    /// @return The directory path.
    function dirForSnapshot(string memory root, string memory dir) internal pure returns (string memory) {
        requireRecordRoot(root);
        LibFs.requireTag(dir);
        return string.concat(root, "/", dir);
    }

    /// The directory holding a snapshot in a repo's REAL record.
    ///
    /// `LibFs`'s own spelling of it, so the directory this library names is the
    /// directory the writer creates and writes into. The root-aware spelling
    /// above is the only other one there is, and
    /// `testRecordRootIsTheRootTheWriterWritesTo` is where the two are held to
    /// being one path.
    /// @param dir The snapshot directory name — a release tag, or `CANDIDATE`.
    /// @return The directory path.
    function dirForSnapshot(string memory dir) internal pure returns (string memory) {
        return LibFs.dirForTag(dir);
    }

    /// The path of a contract's generated file within a snapshot, under a
    /// record root.
    ///
    /// `LibFs` writes under `LIB_FS_ROOT` and takes no root, so it cannot spell
    /// this one — but the two MUST be one path where the root is the real one,
    /// and `testRootAwareSnapshotPathIsTheWritersAtTheRealRoot` is where that is
    /// held. This is the only other spelling of a snapshot path there is, so a
    /// reader pointed at a record root and a writer pointed at the real one
    /// cannot drift by more than that one assertion.
    ///
    /// Both guards are `LibFs.pathForTaggedContract`'s, asked in its order —
    /// the directory first, so a call that gets both wrong names the directory.
    /// That is what makes the two spellings agree on which paths EXIST as well
    /// as on how they are spelled: a reader that accepted what the writer
    /// refuses is the same divergence one step quieter.
    /// @param root The record root — `LIB_FS_ROOT` for a repo's real record.
    /// MUST be a path of record root segments.
    /// @param dir The snapshot directory name — a release tag, or `CANDIDATE`.
    /// MUST be drawn from `LibFs`'s tag alphabet.
    /// @param contractName The name of the contract. MUST be a Solidity
    /// identifier.
    /// @return The file path.
    function pathForSnapshot(string memory root, string memory dir, string memory contractName)
        internal
        pure
        returns (string memory)
    {
        string memory snapshotDir = dirForSnapshot(root, dir);
        LibCodeGen.requireIdentifier(contractName);
        return string.concat(snapshotDir, "/", contractName, ".sol");
    }

    /// The path of a contract's generated file within a snapshot in a repo's
    /// REAL record.
    ///
    /// Delegated to `LibFs` rather than concatenated here, so the path this
    /// library freezes FROM is the same definition `LibFs` writes TO. Two
    /// spellings of one path is how a freeze silently reads nothing.
    ///
    /// `pathForTaggedContract` is the entry point that exists for this layout:
    /// the snapshot directory is an ARGUMENT, so it is checked as a directory
    /// name. It replaced folding the directory into the contract name, which
    /// smuggled a path separator through an argument documented to be a
    /// Solidity identifier and is refused outright now.
    /// @param dir The snapshot directory name — a release tag, or `CANDIDATE`.
    /// @param contractName The name of the contract.
    /// @return The file path.
    function pathForSnapshot(string memory dir, string memory contractName) internal pure returns (string memory) {
        return LibFs.pathForTaggedContract(dir, contractName);
    }

    /// Where every generated non-snapshot lib in a repo's REAL tree is written
    /// — the alias libs, the per-contract released libs and the aggregate over
    /// them — and the only directory the text any of them holds compiles in.
    ///
    /// ONE constant rather than one per writer, because the aggregate imports
    /// the per-contract libs as `./Lib<Contract>Released.sol` — a sibling path,
    /// which is only a sibling path while every writer is pointed at this one
    /// directory. Two spellings of it is a generated file that stops compiling
    /// the moment one of them moves.
    ///
    /// The other imports are parent-relative and constrain it further still:
    /// an alias lib reaches `../generated/`, a released lib and the aggregate
    /// `../abstract/`. So a lib written anywhere else names files that are not
    /// there, and one left under a compiled root fails the whole build.
    string constant LIB_DIR = "src/lib";

    /// Where `DeploySuite` is declared inside this package, below the source
    /// root. The ONE spelling of it: both forms a generated lib can reach it by
    /// are built from this, so the type can be renamed or moved in one edit.
    /// Spelled twice, the second copy is the one that goes stale — and it would
    /// be the in-repo form, which only this repo's own build ever emits, so a
    /// consumer build could not catch it.
    string constant SUITES_SOURCE_SUBPATH = "abstract/RainDeploySuitesBase.sol";

    /// Where `LibDeploySuiteConcat` is declared inside this package, below the
    /// source root.
    string constant CONCAT_SOURCE_SUBPATH = "lib/LibDeploySuiteConcat.sol";

    /// The source root both this package and a consumer put Solidity under, and
    /// the directory `LIB_DIR` sits in.
    string constant SOURCE_ROOT = "src";

    /// The path a generated suites lib reaches `DeploySuite` by, when the lib is
    /// written into THIS repo's `LIB_DIR`.
    ///
    /// Correct here and nowhere else. `LIB_DIR` and the type's directory are
    /// siblings under `SOURCE_ROOT` in this repo, so one directory up finds it.
    /// A consumer's `LIB_DIR` has no sibling holding the type at all, because
    /// the type is in this package rather than in theirs.
    ///
    /// A function and not a constant because `string.concat` is not a
    /// compile-time constant on solc 0.8.25, and respelling the subpath to get
    /// one back is the duplication `SUITES_SOURCE_SUBPATH` exists to remove.
    /// @return The path.
    function suitesImportPathInThisRepo() internal pure returns (string memory) {
        return importPathInThisRepo(SUITES_SOURCE_SUBPATH);
    }

    /// `suitesImportPathInThisRepo` for `LibDeploySuiteConcat`.
    /// @return The path.
    function concatImportPathInThisRepo() internal pure returns (string memory) {
        return importPathInThisRepo(CONCAT_SOURCE_SUBPATH);
    }

    /// The path a lib in THIS repo's `LIB_DIR` reaches a file of this package by.
    /// @param subpath The file, below `SOURCE_ROOT`.
    /// @return The path.
    function importPathInThisRepo(string memory subpath) internal pure returns (string memory) {
        return string.concat("../", subpath);
    }

    /// This library's own soldeer package name, which is also the remapping
    /// prefix a consumer reaches it by — soldeer writes `<name>-<version>/`.
    string constant PACKAGE_NAME = "rain-deploy";

    /// The path a generated suites lib reaches `DeploySuite` by, derived from
    /// the tree being generated in rather than restated by the caller.
    ///
    /// A consumer reaches the type through soldeer, and the version it pinned
    /// is already in its own `foundry.toml`. Reading it there is the move
    /// `deployTag` makes, for the reason `deployTag` gives: `foundry.toml` is
    /// the one source of truth, so a bump is one edit and a regenerate. A path
    /// passed in instead would be the version written down twice, and the copy
    /// that is not `foundry.toml` is the one that goes stale — silently, until
    /// a build names a directory the bump removed.
    ///
    /// No pin means the tree is THIS repo, because nothing depends on itself,
    /// and then the type is a sibling directory away.
    /// @param vm The Vm instance for file operations.
    /// @return The import path.
    function derivedSuitesImportPath(Vm vm) internal view returns (string memory) {
        return suitesImportPathForToml(vm, vm.readFile("foundry.toml"));
    }

    /// `derivedSuitesImportPath` against a given `foundry.toml` rather than the
    /// one on disk.
    ///
    /// Split out so both branches are testable. The pinned branch cannot be
    /// reached through the file: this repo does not depend on itself, so the
    /// only `foundry.toml` the reading arity can see is one with no pin, and a
    /// test that overwrote it to make the pin appear would be a test that
    /// rewrites the manifest the rest of the suite builds against.
    /// @param vm The Vm instance for TOML operations.
    /// @param toml The manifest contents to read the pin from.
    /// @return The import path.
    function suitesImportPathForToml(Vm vm, string memory toml) internal view returns (string memory) {
        return importPathForToml(vm, toml, SUITES_SOURCE_SUBPATH);
    }

    /// `derivedSuitesImportPath` for `LibDeploySuiteConcat`.
    /// @param vm The Vm instance for file operations.
    /// @return The import path.
    function derivedConcatImportPath(Vm vm) internal view returns (string memory) {
        return concatImportPathForToml(vm, vm.readFile("foundry.toml"));
    }

    /// `suitesImportPathForToml` for `LibDeploySuiteConcat`.
    /// @param vm The Vm instance for TOML operations.
    /// @param toml The manifest contents to read the pin from.
    /// @return The import path.
    function concatImportPathForToml(Vm vm, string memory toml) internal view returns (string memory) {
        return importPathForToml(vm, toml, CONCAT_SOURCE_SUBPATH);
    }

    /// The path a generated lib reaches a file of this package by, read from a
    /// given `foundry.toml`.
    /// @param vm The Vm instance for TOML operations.
    /// @param toml The manifest contents to read the pin from.
    /// @param subpath The file, below `SOURCE_ROOT`.
    /// @return The import path.
    function importPathForToml(Vm vm, string memory toml, string memory subpath) internal view returns (string memory) {
        // Unquoted, hyphen and all: a quoted path component is a path error
        // rather than a lookup, and TOML has already normalised the quoted key
        // a consumer spells this pin with.
        string memory key = string.concat(".dependencies.", PACKAGE_NAME);
        if (!vm.keyExistsToml(toml, key)) {
            return importPathInThisRepo(subpath);
        }
        // Soldeer takes a pin either as a bare version string or as an inline
        // table carrying `version` beside a git or path source, so the version
        // sits at one of two selectors. Reading only the bare one reverts on
        // the table form — `expected string, found JSON object` — and it
        // reverts inside the writer, before anything is emitted, so the repo
        // gets no lib rather than a wrong one.
        string memory versionKey = string.concat(key, ".version");
        string memory version =
            vm.keyExistsToml(toml, versionKey) ? vm.parseTomlString(toml, versionKey) : vm.parseTomlString(toml, key);
        return string.concat(PACKAGE_NAME, "-", version, "/", SOURCE_ROOT, "/", subpath);
    }

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

    /// The stdout line `rainix-copy-artifacts` reads a generated path from. It
    /// fails the job on a declared path the run did not write.
    string constant CODEGEN_OWNS_PREFIX = "rainix-codegen owns ";

    /// Every path a `BuildScript.run()` must rewrite: each candidate snapshot,
    /// each contract's released-suites lib and the aggregate. Computed from the
    /// names rather than from the writers, so a dropped writer call is visible.
    /// @param libDir The directory the libs are written into.
    /// @param recordRoot The record root the candidate snapshots are written under.
    /// @param recordNames The snapshots a release freezes.
    /// @param contractNames The contracts with a released-suites lib.
    /// @return The paths.
    function generatedPaths(
        string memory libDir,
        string memory recordRoot,
        string[] memory recordNames,
        string[] memory contractNames
    ) internal pure returns (string[] memory) {
        string[] memory paths = new string[](recordNames.length + contractNames.length + 1);
        for (uint256 i = 0; i < recordNames.length; i++) {
            paths[i] = pathForSnapshot(recordRoot, CANDIDATE, recordNames[i]);
        }
        for (uint256 i = 0; i < contractNames.length; i++) {
            paths[recordNames.length + i] = pathForLib(libDir, releasedLibraryName(contractNames[i]));
        }
        paths[paths.length - 1] = pathForLib(libDir, RELEASED_SUITES_LIBRARY);
        return paths;
    }

    /// The declaration lines for `paths`.
    /// @param paths The generated paths.
    /// @return The lines.
    function codegenDeclaration(string[] memory paths) internal pure returns (string[] memory) {
        string[] memory lines = new string[](paths.length);
        for (uint256 i = 0; i < paths.length; i++) {
            lines[i] = string.concat(CODEGEN_OWNS_PREFIX, paths[i]);
        }
        return lines;
    }

    /// Prints `codegenDeclaration(paths)`, one line each.
    /// @param paths The generated paths.
    function declareGenerated(string[] memory paths) internal pure {
        string[] memory lines = codegenDeclaration(paths);
        for (uint256 i = 0; i < lines.length; i++) {
            console2.log(lines[i]);
        }
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
    /// The root is checked before the walk, because a root nothing can be
    /// written under is not a record that happens to be empty. This is the one
    /// root-taking entry point that does not reach `dirForSnapshot`, so the two
    /// together are every way a root gets into this library.
    /// @param vm The Vm instance for file operations.
    /// @param root The record root — `LIB_FS_ROOT` for a repo's real record.
    /// MUST be a path of record root segments.
    /// @return Every frozen record file.
    function frozenSnapshotPaths(Vm vm, string memory root) internal view returns (string[] memory) {
        requireRecordRoot(root);

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

        string[] memory paths = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            paths[i] = found[i];
        }
        return paths;
    }

    /// Every file in the FROZEN record of a repo's REAL record.
    ///
    /// The spelling a repo's own checks call, so the root is not something
    /// their call sites hand over and cannot be what one of them gets wrong. A
    /// walk of a root nothing writes to finds nothing, forever and silently, so
    /// pointing one somewhere else is how a record-anchored check is made inert
    /// while it still reports green. The rooted spelling above is for a FIXTURE
    /// record, a tree a test builds rather than the tree a repo asks about
    /// itself.
    ///
    /// `testFrozenSnapshotPathsDefaultToTheWritersRecord` is where this default
    /// is held to the writer's own paths.
    /// @param vm The Vm instance for file operations.
    /// @return Every frozen record file.
    function frozenSnapshotPaths(Vm vm) internal view returns (string[] memory) {
        return frozenSnapshotPaths(vm, LIB_FS_ROOT);
    }

    /// The constants a snapshot declares below the `BYTECODE_HASH` that
    /// `LibFs.buildFileForTaggedContract` writes itself: the deploy address, the
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
    /// @param dependencies Each address that must already have code on a
    /// network before this contract can be broadcast there, with that code.
    /// @return The constants, as Solidity source.
    function snapshotConstants(
        Vm vm,
        address deployed,
        bytes memory creationCode,
        DeployDependency[] memory dependencies
    ) internal view returns (string memory) {
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
                "/// @dev What MUST already be on a network before this release can be\n"
                "/// broadcast there: an address, and the runtime code that belongs at it.\n"
                "/// `abi.encode`d as a `DeployDependency[]` because Solidity has no\n"
                "/// file-scope constant of dynamic array type.",
                "DEPENDENCIES",
                abi.encode(dependencies)
            )
        );
    }

    /// Generate one snapshot for one contract.
    ///
    /// The output root is the one `freeze` is handed, and it is required for
    /// the same reason: `cutRelease()` regenerates and then freezes within ONE
    /// record tree. A generator that could only write under `LIB_FS_ROOT` would
    /// leave a release cut under any other root frozen from a rolling snapshot
    /// its own regeneration never wrote — after writing the real record on the
    /// way there, which is the tree a `recordRoot()` override exists to keep a
    /// caller's hands off.
    ///
    /// `LibFs.buildFileForContract` takes the directory it writes into, so the
    /// root reaches the writer through `dirForSnapshot(root, dir)`, which is
    /// where both halves of the directory are checked: `dir` against `LibFs`'s
    /// tag alphabet and the root against `requireRecordRoot`. The root is a
    /// caller's string and it is the half that names where the tree IS, so an
    /// unchecked one would make the output directory of every write here the
    /// caller's to place anywhere `fs_permissions` allows — which is a
    /// consuming repo's config, not an argument this library gets to see. At
    /// `LIB_FS_ROOT` that directory is
    /// `LibFs.dirForTag(dir)`, which is where
    /// `testRootAwareSnapshotPathIsTheWritersAtTheRealRoot` holds the two
    /// spellings to being one path.
    ///
    /// The dependency list is frozen here with the rest, and it is not
    /// metadata. `RainDeployBroadcast.run` hands a suite's dependency list to
    /// `LibRainDeploy.deployToNetworks`, which refuses to broadcast on any
    /// network where one of them has no code, or holds code that is not the
    /// `runtimeCode` the entry declares — so it is a precondition of the
    /// deployment, decided when the release is cut. Re-broadcasting a past
    /// release onto a newly supported chain has to check the list THAT release
    /// was cut with; regenerating it from current source would drop a
    /// dependency an old release still needs the moment current source stops
    /// needing it, and impose a new one on a release that never had it.
    ///
    /// `abi.encode`d because Solidity has no file-scope constant of dynamic
    /// array type. The consumer is `releasedLibraryBlock`, which emits the
    /// matching `abi.decode`.
    /// A snapshot lands in the calling repo's own tree, so the header is that
    /// repo's statement. Repos outside this org call this overload; repos
    /// inside it call the one that defaults to the org's values.
    /// @param vm The Vm instance for file operations.
    /// @param root The record root to generate into — `LIB_FS_ROOT` for a
    /// repo's real record. MUST be a path of record root segments.
    /// @param dir The snapshot directory name — a release tag, or `CANDIDATE`.
    /// @param contractName The contract the snapshot describes.
    /// @param spdxLicenseIdentifier The SPDX licence identifier the written
    /// snapshot declares.
    /// @param copyrightText The copyright text the written snapshot declares.
    /// @param creationCode That contract's creation code.
    /// @param dependencies Each address that must already have code on a
    /// network before this contract can be broadcast there, with that code.
    /// @return The path written.
    function writeSnapshot(
        Vm vm,
        string memory root,
        string memory dir,
        string memory contractName,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        bytes memory creationCode,
        DeployDependency[] memory dependencies
    ) internal returns (string memory) {
        address deployed = LibRainDeploy.etchAndDeployZoltu(vm, creationCode);
        string memory constants = snapshotConstants(vm, deployed, creationCode, dependencies);

        // The directory is created by the writer, from the same root and tag
        // this path is derived from, so there is no `createDir` here to
        // disagree with it.
        LibFs.buildFileForContract(
            vm, deployed, dirForSnapshot(root, dir), contractName, spdxLicenseIdentifier, copyrightText, constants
        );

        return pathForSnapshot(root, dir, contractName);
    }

    /// `writeSnapshot` applied to `RAIN_SPDX_LICENSE_IDENTIFIER` and
    /// `RAIN_COPYRIGHT_TEXT`, for a repo this org owns.
    /// @param vm The Vm instance for file operations.
    /// @param root The record root — `LIB_FS_ROOT` for a repo's real record.
    /// MUST be a path of record root segments.
    /// @param dir The snapshot directory name — a release tag, or `CANDIDATE`.
    /// @param contractName The contract the snapshot describes.
    /// @param creationCode That contract's creation code.
    /// @param dependencies Each address that must already have code on a
    /// network before this contract can be broadcast there, with that code.
    /// @return The path written.
    function writeSnapshot(
        Vm vm,
        string memory root,
        string memory dir,
        string memory contractName,
        bytes memory creationCode,
        DeployDependency[] memory dependencies
    ) internal returns (string memory) {
        return writeSnapshot(
            vm, root, dir, contractName, RAIN_SPDX_LICENSE_IDENTIFIER, RAIN_COPYRIGHT_TEXT, creationCode, dependencies
        );
    }

    /// The constants a parameterised snapshot declares below the
    /// `BYTECODE_HASH` that `LibFs` writes itself: the creation code without
    /// constructor arguments, then the runtime code, in that order.
    /// @param vm The Vm instance for string operations.
    /// @param creationCode The contract's creation code, without constructor
    /// arguments.
    /// @param runtimeCode The runtime code a deploy of it carries.
    /// @return The constants, as Solidity source.
    function parameterisedSnapshotConstants(Vm vm, bytes memory creationCode, bytes memory runtimeCode)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            LibCodeGen.bytesConstantString(
                vm,
                "/// @dev The creation bytecode of the contract, without constructor\n/// arguments.",
                "CREATION_CODE",
                creationCode
            ),
            LibCodeGen.bytesConstantString(
                vm, "/// @dev The runtime bytecode of the contract.", "RUNTIME_CODE", runtimeCode
            )
        );
    }

    /// Generate one snapshot for a contract whose constructor takes arguments.
    ///
    /// Such a contract has no single deploy address: the Zoltu address is a
    /// function of the creation code WITH its arguments, so each argument set
    /// is its own deploy. The snapshot therefore records the code and not a
    /// deploy: `BYTECODE_HASH`, `CREATION_CODE` without arguments and
    /// `RUNTIME_CODE`. It declares no `DEPLOYED_ADDRESS` and no `DEPENDENCIES`,
    /// and it is not a deploy suite: the caller that picks the arguments derives
    /// the address and deploys.
    ///
    /// The runtime code is read from a reference deploy of `creationCode` with
    /// `referenceConstructorArgs` appended, as `writeSnapshot` reads it from
    /// its deploy. The record states one runtime code for every argument set,
    /// which holds only for a contract whose runtime code does not depend on
    /// its constructor arguments — one with no immutables. Recording a contract
    /// with immutables here records the reference arguments' runtime code.
    /// @param vm The Vm instance for file operations.
    /// @param root The record root to generate into — `LIB_FS_ROOT` for a
    /// repo's real record. MUST be a path of record root segments.
    /// @param dir The snapshot directory name.
    /// @param contractName The contract the snapshot describes.
    /// @param spdxLicenseIdentifier The SPDX licence identifier the written
    /// snapshot declares.
    /// @param copyrightText The copyright text the written snapshot declares.
    /// @param creationCode That contract's creation code, without constructor
    /// arguments.
    /// @param referenceConstructorArgs Any constructor arguments the creation
    /// code deploys with.
    /// @return The path written.
    function writeParameterisedSnapshot(
        Vm vm,
        string memory root,
        string memory dir,
        string memory contractName,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        bytes memory creationCode,
        bytes memory referenceConstructorArgs
    ) internal returns (string memory) {
        // The deploy and the emission are scoped away before the write, for the
        // reason `writeReleasedSuitesLib` scopes its paths: with every argument
        // still live, solc 0.8.25 without `--via-ir` refuses the flat form as
        // stack too deep.
        address instance;
        string memory constants;
        {
            instance = LibRainDeploy.etchAndDeployZoltu(vm, abi.encodePacked(creationCode, referenceConstructorArgs));
            constants = parameterisedSnapshotConstants(vm, creationCode, instance.code);
        }
        string memory snapshotDir = dirForSnapshot(root, dir);
        LibFs.buildFileForContract(
            vm, instance, snapshotDir, contractName, spdxLicenseIdentifier, copyrightText, constants
        );
        return pathForSnapshot(root, dir, contractName);
    }

    /// `writeParameterisedSnapshot` applied to `RAIN_SPDX_LICENSE_IDENTIFIER`
    /// and `RAIN_COPYRIGHT_TEXT`, for a repo this org owns.
    /// @param vm The Vm instance for file operations.
    /// @param root The record root — `LIB_FS_ROOT` for a repo's real record.
    /// MUST be a path of record root segments.
    /// @param dir The snapshot directory name.
    /// @param contractName The contract the snapshot describes.
    /// @param creationCode That contract's creation code, without constructor
    /// arguments.
    /// @param referenceConstructorArgs Any constructor arguments the creation
    /// code deploys with.
    /// @return The path written.
    function writeParameterisedSnapshot(
        Vm vm,
        string memory root,
        string memory dir,
        string memory contractName,
        bytes memory creationCode,
        bytes memory referenceConstructorArgs
    ) internal returns (string memory) {
        return writeParameterisedSnapshot(
            vm,
            root,
            dir,
            contractName,
            RAIN_SPDX_LICENSE_IDENTIFIER,
            RAIN_COPYRIGHT_TEXT,
            creationCode,
            referenceConstructorArgs
        );
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
    /// problem, to save a caller one short string. The library NAME is derived,
    /// because `Lib<Contract>Deploy` is mechanical.
    ///
    /// The header comes from `LibCodeGen.filePrefix`, the same one `LibFs`
    /// gives a snapshot, so an alias lib and a snapshot say they are generated
    /// in identical words and neither restates the other. The licence and the
    /// copyright holder are the calling repo's, for the reason `writeSnapshot`
    /// gives, and reach `filePrefix` from here unchanged.
    /// @param vm The Vm instance for file operations.
    /// @param libDir The directory to write the lib into — `LIB_DIR` for a
    /// repo's real tree. A parameter for the same reason `recordRoot` is one on
    /// `writeReleasedSuitesLib`: a writer that can only be pointed at the
    /// committed tree can only be tested by overwriting it, and the directory
    /// MUST already exist.
    /// @param contractName The contract the snapshot describes.
    /// @param constantPrefix The prefix for the emitted constants, e.g.
    /// `ADDRESS_REGISTRY`.
    /// @param dir The snapshot directory to alias — ordinarily `CANDIDATE`.
    /// @param spdxLicenseIdentifier The SPDX licence identifier the written lib
    /// declares.
    /// @param copyrightText The copyright text the written lib declares.
    /// @return The path written.
    function writeAliasLib(
        Vm vm,
        string memory libDir,
        string memory contractName,
        string memory constantPrefix,
        string memory dir,
        string memory spdxLicenseIdentifier,
        string memory copyrightText
    ) internal returns (string memory) {
        string memory libraryName = aliasLibraryName(contractName);
        string memory path = pathForLib(libDir, libraryName);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(
            path,
            string.concat(
                LibCodeGen.filePrefix(spdxLicenseIdentifier, copyrightText),
                "\n",
                aliasImportBlock(contractName, constantPrefix, dir),
                aliasLibraryBlock(contractName, constantPrefix, libraryName)
            )
        );
        return path;
    }

    /// `writeAliasLib` applied to `RAIN_SPDX_LICENSE_IDENTIFIER` and
    /// `RAIN_COPYRIGHT_TEXT`, for a repo this org owns.
    /// @param vm The Vm instance for file operations.
    /// @param libDir The directory to write the lib into — `LIB_DIR` for a
    /// repo's real tree.
    /// @param contractName The contract the alias lib is written for.
    /// @param constantPrefix The prefix for the emitted constants.
    /// @param dir The snapshot directory to alias.
    /// @return The path written.
    function writeAliasLib(
        Vm vm,
        string memory libDir,
        string memory contractName,
        string memory constantPrefix,
        string memory dir
    ) internal returns (string memory) {
        return writeAliasLib(
            vm, libDir, contractName, constantPrefix, dir, RAIN_SPDX_LICENSE_IDENTIFIER, RAIN_COPYRIGHT_TEXT
        );
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

    /// Whether release tag `a` strictly precedes release tag `b`.
    ///
    /// Tags compare as VERSIONS rather than as text — `0_10_0` follows `0_9_0`
    /// as a release and precedes it as a string, so a text comparison misorders
    /// every record that outlives a single-digit minor. Both MUST be `isTag`,
    /// so every component is a run of digits `parseUint` reads and both have
    /// the same number of them.
    ///
    /// The ONE definition of what "follows" means for a release, asked by the
    /// emission order and by the freeze's ordering guard alike. Two spellings
    /// of it is how a record sorts one way and admits a tag the other way.
    ///
    /// Taking the tags rather than record paths is what makes the guard
    /// reachable: a release being cut has no record file yet, and a comparison
    /// that could only be asked with two paths could only be asked about
    /// releases that already happened — the same reason `tagForVersion` is
    /// split out of `deployTag`.
    /// @param vm The Vm instance for string operations.
    /// @param a A release tag.
    /// @param b A release tag.
    /// @return Whether `a` strictly precedes `b`.
    function tagPrecedes(Vm vm, string memory a, string memory b) internal pure returns (bool) {
        string[] memory left = vm.split(a, "_");
        string[] memory right = vm.split(b, "_");
        for (uint256 i = 0; i < left.length; i++) {
            uint256 leftComponent = vm.parseUint(left[i]);
            uint256 rightComponent = vm.parseUint(right[i]);
            if (leftComponent != rightComponent) {
                return leftComponent < rightComponent;
            }
        }
        return false;
    }

    /// Whether record file `a` is emitted before record file `b`: by release
    /// tag (`tagPrecedes`), then by path.
    ///
    /// The tie break is the path, byte for byte, so two contracts frozen under
    /// one tag have an order at all. The walk's own order is the filesystem's,
    /// and a generated file that changes with it is a diff on every build. It
    /// applies only when neither tag precedes the other, i.e. the two files are
    /// the same release — a tag that follows the other is ordered by that and
    /// never by the text of its path.
    /// @param vm The Vm instance for string operations.
    /// @param a A record file.
    /// @param b A record file.
    /// @return Whether `a` precedes `b`.
    function recordPrecedes(Vm vm, string memory a, string memory b) internal pure returns (bool) {
        string memory leftTag = tagForRecordPath(vm, a);
        string memory rightTag = tagForRecordPath(vm, b);
        if (tagPrecedes(vm, leftTag, rightTag)) {
            return true;
        }
        if (tagPrecedes(vm, rightTag, leftTag)) {
            return false;
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
    /// @return The same files, in release order.
    function sortedRecordPaths(Vm vm, string[] memory paths) internal pure returns (string[] memory) {
        string[] memory sorted = new string[](paths.length);
        for (uint256 i = 0; i < paths.length; i++) {
            uint256 j = i;
            while (j > 0 && recordPrecedes(vm, paths[i], sorted[j - 1])) {
                sorted[j] = sorted[j - 1];
                j--;
            }
            sorted[j] = paths[i];
        }
        return sorted;
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

    /// The name of the alias lib that re-exports ONE contract's candidate pins.
    /// @param contractName The contract the alias lib describes.
    /// @return The library name, e.g. `LibConfigRegistryDeploy`.
    function aliasLibraryName(string memory contractName) internal pure returns (string memory) {
        return string.concat("Lib", contractName, "Deploy");
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

    /// The name every deployed address constant starts with. A line holding it anywhere but at the start of the
    /// writer's declaration is not the writer's.
    string constant DEPLOYED_ADDRESS_NAME = "DEPLOYED_ADDRESS";

    string constant DEPLOYED_ADDRESS_DECLARATION = "address constant DEPLOYED_ADDRESS =";

    string constant DEPLOYED_ADDRESS_CHAIN_DECLARATION_PREFIX = "address constant DEPLOYED_ADDRESS_";

    /// The indent the writer gives a declaration value wrapped onto its own line.
    string constant WRAPPED_INDENT = "    ";

    /// The name of the mechanism data constant. A line holding it anywhere but at the start of the writer's declaration
    /// is not the writer's.
    string constant MECHANISM_DATA_NAME = "MECHANISM_DATA";

    string constant MECHANISM_DATA_DECLARATION = "bytes constant MECHANISM_DATA =";

    /// The addresses a frozen record declares as its deploy addresses, and the chain id each is
    /// for.
    /// @param vm The Vm instance for string operations.
    /// @param path The record file, for the error only.
    /// @param record The record file's contents.
    /// @return The chain id each address is for.
    /// @return The addresses the record declares, in file order.
    function recordedDeployedAddresses(Vm vm, string memory path, string memory record)
        internal
        pure
        returns (uint256[] memory, address[] memory)
    {
        return recordedDeployedAddresses(vm, path, recordLines(vm, path, record));
    }

    /// The addresses a frozen record declares as its deploy addresses, and the chain id each is
    /// for, from the record's lines.
    /// @param vm The Vm instance for string operations.
    /// @param path The record file, for the error only.
    /// @param lines The record's lines, as `recordLines` returns them.
    /// @return The chain id each address is for.
    /// @return The addresses the record declares, in file order.
    function recordedDeployedAddresses(Vm vm, string memory path, string[] memory lines)
        internal
        pure
        returns (uint256[] memory, address[] memory)
    {
        uint256[] memory chainIds = new uint256[](lines.length);
        address[] memory addresses = new address[](lines.length);
        uint256 perNetwork = 0;
        bool everyNetwork = false;
        for (uint256 i = 0; i < lines.length; i++) {
            bool isEveryNetwork = vm.indexOf(lines[i], DEPLOYED_ADDRESS_DECLARATION) == 0;
            if (!isEveryNetwork && vm.indexOf(lines[i], DEPLOYED_ADDRESS_CHAIN_DECLARATION_PREFIX) != 0) {
                if (vm.contains(lines[i], DEPLOYED_ADDRESS_NAME)) {
                    revert FrozenSnapshotUnreadable(path);
                }
                continue;
            }
            if (everyNetwork || (isEveryNetwork && perNetwork != 0)) {
                revert FrozenSnapshotAmbiguous(path);
            }
            address declared = declarationAddress(vm, path, lines, i);
            if (isEveryNetwork) {
                everyNetwork = true;
                addresses[0] = declared;
                continue;
            }
            uint256 chainId = declaredChainId(path, lines[i]);
            for (uint256 j = 0; j < perNetwork; j++) {
                if (chainIds[j] == chainId) {
                    revert FrozenSnapshotAmbiguous(path);
                }
            }
            chainIds[perNetwork] = chainId;
            addresses[perNetwork] = declared;
            perNetwork++;
        }
        if (!everyNetwork && perNetwork == 0) {
            revert FrozenSnapshotUnreadable(path);
        }
        uint256 chainIdsLength = perNetwork;
        uint256 addressesLength = everyNetwork ? 1 : perNetwork;
        assembly ("memory-safe") {
            mstore(chainIds, chainIdsLength)
            mstore(addresses, addressesLength)
        }
        return (chainIds, addresses);
    }

    /// The address the declaration on `lines[line]` names, read by `declarationValue` with `address(` at the
    /// writer's `WRAPPED_INDENT`.
    /// @param vm The Vm instance for string operations.
    /// @param path The record file, for the error only.
    /// @param lines The record's lines, block comments removed.
    /// @param line The declaration's line.
    /// @return The address.
    function declarationAddress(Vm vm, string memory path, string[] memory lines, uint256 line)
        internal
        pure
        returns (address)
    {
        // An unreadable declaration's value is empty, which `declaredAddress` refuses at its `0x` split.
        (, string memory value) = declarationValue(vm, lines, line, string.concat(WRAPPED_INDENT, "address("));
        return declaredAddress(vm, path, value);
    }

    /// The value the declaration on `lines[line]` gives, held to the writer's format: the last of exactly five
    /// space-separated tokens, on the declaration's own line with `=` fourth, or on the next line when the declaration
    /// ends at its `=` and that line starts with `wrappedPrefix`.
    /// @param vm The Vm instance for string operations.
    /// @param lines The record's lines, block comments removed.
    /// @param line The declaration's line.
    /// @param wrappedPrefix The start the writer gives a wrapped value's line.
    /// @return Whether the declaration is in the writer's format.
    /// @return The value's token, empty when not readable.
    function declarationValue(Vm vm, string[] memory lines, uint256 line, string memory wrappedPrefix)
        internal
        pure
        returns (bool, string memory)
    {
        string[] memory tokens = vm.split(lines[line], " ");
        bool readable = tokens.length >= 4 && keccak256(bytes(tokens[3])) == keccak256("=");
        if (readable && tokens.length == 4) {
            readable = line + 1 < lines.length && vm.indexOf(lines[line + 1], wrappedPrefix) == 0;
            if (readable) {
                tokens = vm.split(lines[line + 1], " ");
            }
        }
        readable = readable && tokens.length == 5;
        return (readable, readable ? tokens[4] : "");
    }

    /// The address a declaration line's value names: `0x` and 40 hex digits, wrapped in the writer's `address(` and
    /// `)` or bare, then `;`. `vm.parseAddress` refuses any other digit count.
    /// @param vm The Vm instance for string operations.
    /// @param path The record file, for the error only.
    /// @param value The declaration's last token, from the line after it when the writer wrapped it.
    /// @return The address.
    function declaredAddress(Vm vm, string memory path, string memory value) internal pure returns (address) {
        string[] memory opened = vm.split(value, "0x");
        if (opened.length != 2) {
            revert FrozenSnapshotUnreadable(path);
        }
        bool wrapped = keccak256(bytes(opened[0])) == keccak256("address(");
        if (!wrapped && bytes(opened[0]).length != 0) {
            revert FrozenSnapshotUnreadable(path);
        }
        string[] memory closed = vm.split(opened[1], wrapped ? ");" : ";");
        if (closed.length != 2 || bytes(closed[1]).length != 0) {
            revert FrozenSnapshotUnreadable(path);
        }
        // `vm.parseAddress` reads the 40 digits with or without the `0x` the split removed.
        try vm.parseAddress(closed[0]) returns (address declared) {
            return declared;
        } catch {
            revert FrozenSnapshotUnreadable(path);
        }
    }

    /// The chain id a per-network declaration line names.
    /// @param path The record file, for the error only.
    /// @param line A line starting with `DEPLOYED_ADDRESS_CHAIN_DECLARATION_PREFIX`.
    /// @return The chain id.
    function declaredChainId(string memory path, string memory line) internal pure returns (uint256) {
        bytes memory text = bytes(line);
        uint256 start = bytes(DEPLOYED_ADDRESS_CHAIN_DECLARATION_PREFIX).length;
        uint256 end = start;
        uint256 chainId = 0;
        while (end < text.length && text[end] != " ") {
            uint8 character = uint8(text[end]);
            if (character < 0x30 || character > 0x39) {
                revert FrozenSnapshotUnreadable(path);
            }
            uint256 digit = character - 0x30;
            if (chainId > (type(uint256).max - digit) / 10) {
                revert FrozenSnapshotUnreadable(path);
            }
            chainId = chainId * 10 + digit;
            end++;
        }
        if (end == start || (end - start > 1 && text[start] == "0")) {
            revert FrozenSnapshotUnreadable(path);
        }
        return chainId;
    }

    /// A record's lines, block comments removed, from a record whose only line break is `\n`.
    /// Reverts with `FrozenSnapshotUnreadable` on any other line break solc honours.
    /// @param vm The Vm instance for string operations.
    /// @param path The record file, for the error only.
    /// @param record The record file's contents.
    /// @return The lines.
    function recordLines(Vm vm, string memory path, string memory record) internal pure returns (string[] memory) {
        if (hasForeignLineBreak(vm, record)) {
            revert FrozenSnapshotUnreadable(path);
        }
        return splitRecordLines(vm, record);
    }

    /// A record's lines, block comments removed, split on `\n` alone with no line break check.
    /// @param vm The Vm instance for string operations.
    /// @param record The record file's contents.
    /// @return The lines.
    function splitRecordLines(Vm vm, string memory record) internal pure returns (string[] memory) {
        return vm.split(withoutBlockComments(record), "\n");
    }

    /// Whether a record holds a line break solc honours other than `\n`: `\r`, `\x0b`, `\x0c`, NEL, LS or PS.
    /// @param vm The Vm instance for string operations.
    /// @param record The record file's contents.
    /// @return Whether it holds one.
    function hasForeignLineBreak(Vm vm, string memory record) internal pure returns (bool) {
        return vm.contains(record, "\r") || vm.contains(record, "\x0b") || vm.contains(record, "\x0c")
            || vm.contains(record, "\xc2\x85") || vm.contains(record, "\xe2\x80\xa8")
            || vm.contains(record, "\xe2\x80\xa9");
    }

    /// A record's text with every block comment removed but its line breaks, read left to right: the first `*/` closes
    /// a block comment, a `//` comment runs to the next `\n`, and a quoted string runs to its unescaped closing quote.
    /// @param record The record file's contents.
    /// @return The contents with every block comment removed but its line breaks.
    function withoutBlockComments(string memory record) internal pure returns (string memory) {
        bytes memory text = bytes(record);
        bytes memory stripped = new bytes(text.length);
        uint256 length = 0;
        uint256 i = 0;
        unchecked {
            while (i < text.length) {
                bytes1 character = text[i];
                bool slashNext = character == "/" && i + 1 < text.length;
                if (slashNext && text[i + 1] == "*") {
                    i += 2;
                    while (i < text.length && !(text[i] == "*" && i + 1 < text.length && text[i + 1] == "/")) {
                        if (text[i] == "\n") {
                            stripped[length++] = "\n";
                        }
                        i++;
                    }
                    i += 2;
                    continue;
                }
                bytes1 closing = 0;
                if (slashNext && text[i + 1] == "/") {
                    closing = "\n";
                } else if (character == "\"" || character == "'") {
                    closing = character;
                }
                stripped[length++] = character;
                i++;
                if (closing == 0) {
                    continue;
                }
                while (i < text.length) {
                    character = text[i];
                    stripped[length++] = character;
                    i++;
                    if (character == closing) {
                        break;
                    }
                    if (closing != "\n" && character == "\\" && i < text.length) {
                        stripped[length++] = text[i];
                        i++;
                    }
                }
            }
        }
        assembly ("memory-safe") {
            mstore(stripped, length)
        }
        return string(stripped);
    }

    /// Whether a frozen record declares `MECHANISM_DATA`, and whether it declares its addresses per network as
    /// `DEPLOYED_ADDRESS_<chainId>`. Refuses `FrozenSnapshotMechanismDataAmbiguous` for more than one declaration and
    /// `FrozenSnapshotMechanismDataMissing` for a per-network record with none.
    /// @param vm The Vm instance for file and string operations.
    /// @param path A record file, as `frozenSnapshotPaths` returns it.
    /// @return Whether it declares `MECHANISM_DATA`.
    /// @return Whether it declares its addresses per network.
    function recordedMechanismShape(Vm vm, string memory path) internal view returns (bool, bool) {
        return recordedMechanismShape(vm, path, recordLines(vm, path, vm.readFile(path)));
    }

    /// `recordedMechanismShape` over a record's already-read `recordLines`.
    /// @param vm The Vm instance for string operations.
    /// @param path The record file the lines were read from.
    /// @param lines Its `recordLines`.
    /// @return Whether it declares `MECHANISM_DATA`.
    /// @return Whether it declares its addresses per network.
    function recordedMechanismShape(Vm vm, string memory path, string[] memory lines)
        internal
        pure
        returns (bool, bool)
    {
        (uint256[] memory chainIds,) = recordedDeployedAddresses(vm, path, lines);
        uint256 mechanismData = 0;
        for (uint256 i = 0; i < lines.length; i++) {
            if (vm.indexOf(lines[i], MECHANISM_DATA_DECLARATION) == 0) {
                mechanismData++;
            } else if (vm.contains(lines[i], MECHANISM_DATA_NAME)) {
                revert FrozenSnapshotUnreadable(path);
            }
        }
        if (mechanismData > 1) {
            revert FrozenSnapshotMechanismDataAmbiguous(path);
        }
        if (mechanismData == 0 && chainIds.length != 0) {
            revert FrozenSnapshotMechanismDataMissing(path);
        }
        return (mechanismData != 0, chainIds.length != 0);
    }

    /// @param vm The Vm instance for file and string operations.
    /// @param path A record file, as `frozenSnapshotPaths` returns it.
    /// @return Whether it declares `MECHANISM_DATA`, with `recordedMechanismShape`'s refusals.
    function recordDeclaresMechanismData(Vm vm, string memory path) internal view returns (bool) {
        (bool mechanismData,) = recordedMechanismShape(vm, path);
        return mechanismData;
    }

    /// The mechanism id a record declares: `ZOLTU_MECHANISM_ID` without `MECHANISM_DATA`, else its leading word. Refuses
    /// `FrozenSnapshotUnreadable` for a `MECHANISM_DATA` not a `hex"..."` literal of at least a word, with
    /// `recordedMechanismShape`'s refusals.
    /// @param vm The Vm instance for file and string operations.
    /// @param path A record file, as `frozenSnapshotPaths` returns it.
    /// @return The id.
    function recordedMechanismId(Vm vm, string memory path) internal view returns (bytes32) {
        return recordedMechanismId(vm, path, recordLines(vm, path, vm.readFile(path)));
    }

    /// `recordedMechanismId` over a record's already-read `recordLines`.
    /// @param vm The Vm instance for string operations.
    /// @param path The record file the lines were read from.
    /// @param lines Its `recordLines`.
    /// @return The id.
    function recordedMechanismId(Vm vm, string memory path, string[] memory lines) internal pure returns (bytes32) {
        (bool mechanismData,) = recordedMechanismShape(vm, path, lines);
        if (!mechanismData) {
            return ZOLTU_MECHANISM_ID;
        }
        uint256 line = 0;
        while (vm.indexOf(lines[line], MECHANISM_DATA_DECLARATION) != 0) {
            line++;
        }
        (, string memory value) = declarationValue(vm, lines, line, string.concat(WRAPPED_INDENT, "hex\""));
        bytes memory literal = bytes(value);
        if (literal.length < 70 || vm.indexOf(value, "hex\"") != 0) {
            revert FrozenSnapshotUnreadable(path);
        }
        bytes memory word = new bytes(66);
        word[0] = "0";
        word[1] = "x";
        for (uint256 i = 0; i < 64; i++) {
            word[i + 2] = literal[i + 4];
        }
        return vm.parseBytes32(string(word));
    }

    /// The aliased import one record file contributes.
    /// @param vm The Vm instance for file and string operations.
    /// @param path A record file, as `frozenSnapshotPaths` returns it.
    /// @return The import statement, and the blank line after it.
    function releasedImport(Vm vm, string memory path) internal view returns (string memory) {
        string memory prefix = releasedConstantPrefix(vm, path);
        (bool mechanismData, bool perNetwork) = recordedMechanismShape(vm, path);
        return string.concat(
            perNetwork
                ? string("import {\n    ")
                : string.concat("import {\n    DEPLOYED_ADDRESS as ", prefix, "_DEPLOYED_ADDRESS,\n    "),
            "BYTECODE_HASH as ",
            prefix,
            "_BYTECODE_HASH,\n    CREATION_CODE as ",
            prefix,
            "_CREATION_CODE,\n    RUNTIME_CODE as ",
            prefix,
            "_RUNTIME_CODE,\n    DEPENDENCIES as ",
            prefix,
            "_DEPENDENCIES",
            !mechanismData ? string("") : string.concat(",\n    MECHANISM_DATA as ", prefix, "_MECHANISM_DATA"),
            "\n} from \"../generated/",
            tagForRecordPath(vm, path),
            "/",
            contractForRecordPath(vm, path),
            ".sol\";\n\n"
        );
    }

    /// The import block of a generated released-suites lib.
    /// @param vm The Vm instance for file and string operations.
    /// @param paths The record's files, in the order they are emitted.
    /// @param suitesImportPath The path the emitted lib reaches the suite types by —
    /// `suitesImportPathInThisRepo` for a lib written into this repo's own `LIB_DIR`, and the
    /// consumer's remapped path otherwise.
    /// @param d The declaration whose mechanism for each record gives the import its `releasedMechanismData` needs,
    /// emitted once per distinct import.
    /// @return The import block.
    function releasedImportBlock(
        Vm vm,
        string[] memory paths,
        string memory suitesImportPath,
        DeployDeclaration memory d
    ) internal view returns (string memory) {
        return releasedImportBlock(vm, paths, recordedMechanismIds(vm, paths), suitesImportPath, d);
    }

    /// Each record file's `recordedMechanismId`.
    /// @param vm The Vm instance for file and string operations.
    /// @param paths The record's files.
    /// @return The ids, index-aligned with `paths`.
    function recordedMechanismIds(Vm vm, string[] memory paths) internal view returns (bytes32[] memory) {
        bytes32[] memory ids = new bytes32[](paths.length);
        for (uint256 i = 0; i < paths.length; i++) {
            ids[i] = recordedMechanismId(vm, paths[i]);
        }
        return ids;
    }

    /// `releasedImportBlock` over the records' already-read `recordedMechanismIds`.
    /// @param vm The Vm instance for file and string operations.
    /// @param paths The record's files, in the order they are emitted.
    /// @param ids `recordedMechanismIds` of `paths`.
    /// @param suitesImportPath The path the emitted lib reaches the suite types by.
    /// @param d The declaration whose mechanism for each record gives the import.
    /// @return The import block.
    function releasedImportBlock(
        Vm vm,
        string[] memory paths,
        bytes32[] memory ids,
        string memory suitesImportPath,
        DeployDeclaration memory d
    ) internal view returns (string memory) {
        string memory imports = string.concat(
            "import {DeployDependency, DeploySuite} from \"", suitesImportPath, "\";\n"
        );
        string memory root = importRoot(suitesImportPath);
        bytes32[] memory seen = new bytes32[](paths.length);
        uint256 seenLength = 0;
        for (uint256 i = 0; i < paths.length; i++) {
            string memory mechanismImport =
                LibRainDeployDeclaration.mechanismById(d, ids[i], paths[i]).releasedImport(d, root);
            bytes32 hash = keccak256(bytes(mechanismImport));
            bool duplicate = false;
            for (uint256 j = 0; j < seenLength; j++) {
                if (seen[j] == hash) {
                    duplicate = true;
                    break;
                }
            }
            if (!duplicate) {
                seen[seenLength] = hash;
                seenLength++;
                imports = string.concat(imports, mechanismImport);
            }
        }
        imports = string.concat(imports, "\n");
        for (uint256 i = 0; i < paths.length; i++) {
            imports = string.concat(imports, releasedImport(vm, paths[i]));
        }
        return imports;
    }

    /// `releasedImportBlock` applied to this repo's own `suitesImportPathInThisRepo`.
    /// @param vm The Vm instance for file and string operations.
    /// @param paths The record's files, in the order they are emitted.
    /// @param d The declaration whose mechanisms give the imports.
    /// @return The import block.
    function releasedImportBlock(Vm vm, string[] memory paths, DeployDeclaration memory d)
        internal
        view
        returns (string memory)
    {
        return releasedImportBlock(vm, paths, suitesImportPathInThisRepo(), d);
    }

    /// The import root of this package's source root: `suitesImportPath` less `SUITES_SOURCE_SUBPATH`.
    /// @param suitesImportPath The path the emitted lib reaches the suite types by.
    /// @return The root.
    function importRoot(string memory suitesImportPath) internal pure returns (string memory) {
        bytes memory suites = bytes(suitesImportPath);
        bytes memory root = new bytes(suites.length - bytes(SUITES_SOURCE_SUBPATH).length);
        for (uint256 i = 0; i < root.length; i++) {
            root[i] = suites[i];
        }
        return string(root);
    }

    /// One `suites[i] = DeploySuite({...});` entry of a generated released-suites lib.
    /// @param vm The Vm instance for file and string operations.
    /// @param i The entry's index.
    /// @param path The record file the entry aliases.
    /// @param template The candidate declaration the key and the artifact path come from.
    /// @param d The declaration whose mechanism for the record gives the entry its `mechanismData`.
    /// @return The entry.
    function releasedSuiteEntry(
        Vm vm,
        uint256 i,
        string memory path,
        DeploySuite memory template,
        DeployDeclaration memory d
    ) internal view returns (string memory) {
        return releasedSuiteEntry(vm, i, path, recordedMechanismId(vm, path), template, d);
    }

    /// `releasedSuiteEntry` for a record whose `recordedMechanismId` is already read.
    /// @param vm The Vm instance for file and string operations.
    /// @param i The entry's index.
    /// @param path The record file the entry aliases.
    /// @param id `recordedMechanismId` of `path`.
    /// @param template The candidate declaration the key and the artifact path come from.
    /// @param d The declaration whose mechanism for the record gives the entry its `mechanismData`.
    /// @return The entry.
    function releasedSuiteEntry(
        Vm vm,
        uint256 i,
        string memory path,
        bytes32 id,
        DeploySuite memory template,
        DeployDeclaration memory d
    ) internal view returns (string memory) {
        string memory prefix = releasedConstantPrefix(vm, path);
        string memory storedDeployedAddress;
        string memory mechanismData =
            LibRainDeployDeclaration.mechanismById(d, id, path).releasedMechanismData(d, vm, path, prefix);
        {
            (, bool perNetwork) = recordedMechanismShape(vm, path);
            storedDeployedAddress = perNetwork ? string("address(0)") : string.concat(prefix, "_DEPLOYED_ADDRESS");
        }
        string memory head = string.concat(
            "        suites[",
            vm.toString(i),
            "] = DeploySuite({\n            suite: \"",
            template.suite,
            "@",
            tagForRecordPath(vm, path),
            "\",\n            creationCode: ",
            prefix,
            "_CREATION_CODE,\n            storedDeployedAddress: ",
            storedDeployedAddress,
            ",\n            storedBytecodeHash: ",
            prefix,
            "_BYTECODE_HASH,\n            storedRuntimeCode: ",
            prefix
        );
        return string.concat(
            head,
            "_RUNTIME_CODE,\n            artifactPath: \"",
            template.artifactPath,
            "\",\n            dependencies: abi.decode(",
            prefix,
            "_DEPENDENCIES, (DeployDependency[])),\n            mechanismData: ",
            mechanismData,
            ",\n            networks: new string[](0)\n        });\n"
        );
    }

    /// The library block of a generated released-suites lib.
    /// @param vm The Vm instance for file and string operations.
    /// @param libraryName The generated library's name.
    /// @param contractName The contract the released record describes.
    /// @param paths The record's files, in the order they are emitted.
    /// @param template The candidate declaration the metadata comes from.
    /// @param d The declaration whose mechanism for each record gives its entry `mechanismData`.
    /// @return The library block.
    function releasedLibraryBlock(
        Vm vm,
        string memory libraryName,
        string memory contractName,
        string[] memory paths,
        DeploySuite memory template,
        DeployDeclaration memory d
    ) internal view returns (string memory) {
        return releasedLibraryBlock(vm, libraryName, contractName, paths, recordedMechanismIds(vm, paths), template, d);
    }

    /// `releasedLibraryBlock` over the records' already-read `recordedMechanismIds`.
    /// @param vm The Vm instance for file and string operations.
    /// @param libraryName The generated library's name.
    /// @param contractName The contract the released record describes.
    /// @param paths The record's files, in the order they are emitted.
    /// @param ids `recordedMechanismIds` of `paths`.
    /// @param template The candidate declaration the metadata comes from.
    /// @param d The declaration whose mechanism for each record gives its entry `mechanismData`.
    /// @return The library block.
    function releasedLibraryBlock(
        Vm vm,
        string memory libraryName,
        string memory contractName,
        string[] memory paths,
        bytes32[] memory ids,
        DeploySuite memory template,
        DeployDeclaration memory d
    ) internal view returns (string memory) {
        string memory entries = "";
        for (uint256 i = 0; i < paths.length; i++) {
            entries = string.concat(entries, releasedSuiteEntry(vm, i, paths[i], ids[i], template, d));
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
            " {\n    /// Every frozen release, in tag order.\n" "    /// @return The released suites.\n"
            "    function releasedSuites() internal pure returns (DeploySuite[] memory) {\n"
            "        DeploySuite[] memory suites = new DeploySuite[](",
            vm.toString(paths.length),
            ");\n",
            entries,
            "        return suites;\n    }\n}\n"
        );
    }

    /// The body of a generated released-suites lib: its import block then its library block, over one
    /// `recordedMechanismIds` read of `paths`.
    /// @param vm The Vm instance for file and string operations.
    /// @param paths The record's files, in the order they are emitted.
    /// @param libraryName The generated library's name.
    /// @param contractName The contract the released record describes.
    /// @param template The candidate declaration the metadata comes from.
    /// @param d The declaration whose mechanism for each record gives its import and entry.
    /// @param suitesImportPath The path the emitted lib reaches the suite types by.
    /// @return The body.
    function releasedLibBody(
        Vm vm,
        string[] memory paths,
        string memory libraryName,
        string memory contractName,
        DeploySuite memory template,
        DeployDeclaration memory d,
        string memory suitesImportPath
    ) internal view returns (string memory) {
        bytes32[] memory ids = recordedMechanismIds(vm, paths);
        return string.concat(
            releasedImportBlock(vm, paths, ids, suitesImportPath, d),
            releasedLibraryBlock(vm, libraryName, contractName, paths, ids, template, d)
        );
    }

    /// Generate the released-suites lib for a repo's frozen record.
    /// @param vm The Vm instance for file operations.
    /// @param libDir The directory to write the lib into — `LIB_DIR` for a repo's real tree.
    /// @param recordRoot The record root to read releases from — `LIB_FS_ROOT` for a repo's real
    /// record.
    /// @param contractName The contract the released record describes.
    /// @param spdxLicenseIdentifier The SPDX licence identifier the written lib declares.
    /// @param copyrightText The copyright text the written lib declares.
    /// @param template The candidate declaration the metadata comes from.
    /// @param d The declaration whose mechanism for each record gives its entry `mechanismData`.
    /// @param suitesImportPath The path the emitted lib reaches the suite types by.
    /// @return The path written.
    function writeReleasedSuitesLib(
        Vm vm,
        string memory libDir,
        string memory recordRoot,
        string memory contractName,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        DeploySuite memory template,
        DeployDeclaration memory d,
        string memory suitesImportPath
    ) internal returns (string memory) {
        string memory libraryName = releasedLibraryName(contractName);
        string memory path = pathForLib(libDir, libraryName);
        string memory body = releasedLibBody(
            vm,
            recordPathsForContract(vm, recordRoot, contractName),
            libraryName,
            contractName,
            template,
            d,
            suitesImportPath
        );

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(path, string.concat(LibCodeGen.filePrefix(spdxLicenseIdentifier, copyrightText), "\n", body));
        return path;
    }

    /// `writeReleasedSuitesLib` applied to `RAIN_SPDX_LICENSE_IDENTIFIER` and
    /// `RAIN_COPYRIGHT_TEXT`, for a repo this org owns.
    /// @param vm The Vm instance for file operations.
    /// @param libDir The directory to write the lib into — `LIB_DIR` for a
    /// repo's real tree.
    /// @param recordRoot The record root — `LIB_FS_ROOT` for a repo's real
    /// record.
    /// @param contractName The contract the released lib is written for.
    /// @param template The suite the released entries take their key and
    /// artifact path from.
    /// @param d The declaration whose mechanism for each record gives its entry `mechanismData`.
    /// @param suitesImportPath The path the emitted lib reaches the suite types by.
    /// @return The path written.
    function writeReleasedSuitesLib(
        Vm vm,
        string memory libDir,
        string memory recordRoot,
        string memory contractName,
        DeploySuite memory template,
        DeployDeclaration memory d,
        string memory suitesImportPath
    ) internal returns (string memory) {
        return writeReleasedSuitesLib(
            vm,
            libDir,
            recordRoot,
            contractName,
            RAIN_SPDX_LICENSE_IDENTIFIER,
            RAIN_COPYRIGHT_TEXT,
            template,
            d,
            suitesImportPath
        );
    }

    /// `writeReleasedSuitesLib` applied to `derivedSuitesImportPath`, keeping the
    /// explicit-licence arity for a repo this org does not own.
    /// @param vm The Vm instance for file operations.
    /// @param libDir The directory to write the lib into.
    /// @param recordRoot The record root to read releases from.
    /// @param contractName The contract the released record describes.
    /// @param spdxLicenseIdentifier The SPDX licence identifier the written lib
    /// declares.
    /// @param copyrightText The copyright text the written lib declares.
    /// @param template The candidate declaration the metadata comes from.
    /// @param d The declaration whose mechanism for each record gives its entry `mechanismData`.
    /// @return The path written.
    function writeReleasedSuitesLib(
        Vm vm,
        string memory libDir,
        string memory recordRoot,
        string memory contractName,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        DeploySuite memory template,
        DeployDeclaration memory d
    ) internal returns (string memory) {
        // Derived into a local before the forward, not inlined as the eighth
        // argument: eight arguments and the derivation's own temporaries alive
        // at once is stack too deep on solc 0.8.25 without `--via-ir`, the same
        // limit the full arity's body is already shaped around. Not a style
        // choice — the inlined form does not compile.
        string memory suitesImportPath = derivedSuitesImportPath(vm);
        return writeReleasedSuitesLib(
            vm, libDir, recordRoot, contractName, spdxLicenseIdentifier, copyrightText, template, d, suitesImportPath
        );
    }

    /// `writeReleasedSuitesLib` applied to `derivedSuitesImportPath` as well, so
    /// a consumer gets its own remapped path without naming it. The arity above
    /// takes an explicit path, for a tree whose layout neither case fits.
    /// @param vm The Vm instance for file operations.
    /// @param libDir The directory to write the lib into — `LIB_DIR` for a
    /// repo's real tree.
    /// @param recordRoot The record root — `LIB_FS_ROOT` for a repo's real
    /// record.
    /// @param contractName The contract the released lib is written for.
    /// @param template The suite the released entries take their key and
    /// artifact path from.
    /// @param d The declaration whose mechanism for each record gives its entry `mechanismData`.
    /// @return The path written.
    function writeReleasedSuitesLib(
        Vm vm,
        string memory libDir,
        string memory recordRoot,
        string memory contractName,
        DeploySuite memory template,
        DeployDeclaration memory d
    ) internal returns (string memory) {
        return writeReleasedSuitesLib(vm, libDir, recordRoot, contractName, template, d, derivedSuitesImportPath(vm));
    }

    /// The import block of the generated aggregate lib.
    ///
    /// One import per contract, of the released lib `writeReleasedSuitesLib`
    /// emitted for it, by sibling path — both writers emit into `LIB_DIR`, so
    /// the released libs are siblings of the aggregate wherever `LIB_DIR` is.
    /// The `DeploySuite` import above them is parent-relative, so the emitted
    /// file also compiles only from a directory whose parent holds
    /// `abstract/RainDeploySuitesBase.sol`.
    /// @param contractNames The contracts whose released libs to aggregate.
    /// @param suitesImportPath The path the emitted lib reaches `DeploySuite`
    /// by — `suitesImportPathInThisRepo` for a lib written into this repo's own
    /// `LIB_DIR`, and the consumer's remapped path otherwise.
    /// @param concatImportPath The path the emitted lib reaches
    /// `LibDeploySuiteConcat` by, on the same terms.
    /// @return The import block.
    function aggregateImportBlock(
        string[] memory contractNames,
        string memory suitesImportPath,
        string memory concatImportPath
    ) internal pure returns (string memory) {
        string memory imports = string.concat(
            "import {DeploySuite} from \"",
            suitesImportPath,
            "\";\n\nimport {LibDeploySuiteConcat} from \"",
            concatImportPath,
            "\";\n\n"
        );
        for (uint256 i = 0; i < contractNames.length; i++) {
            string memory libraryName = releasedLibraryName(contractNames[i]);
            imports = string.concat(imports, "import {", libraryName, "} from \"./", libraryName, ".sol\";\n\n");
        }
        return imports;
    }

    /// `aggregateImportBlock` applied to this repo's own
    /// `suitesImportPathInThisRepo` and `concatImportPathInThisRepo`.
    /// @param contractNames The contracts whose released libs to aggregate.
    /// @return The import block.
    function aggregateImportBlock(string[] memory contractNames) internal pure returns (string memory) {
        return aggregateImportBlock(contractNames, suitesImportPathInThisRepo(), concatImportPathInThisRepo());
    }

    /// The library block of the generated aggregate lib: every per-contract
    /// released lib read once and copied into one array, in the order given.
    ///
    /// The emitted code reads every released lib into one array of arrays and
    /// hands it to `LibDeploySuiteConcat.concat`, one line per contract, so no
    /// emitted line is wider for a repo with more contracts in it. The emitted
    /// file is committed, and both `forge fmt --check` and a byte-for-byte
    /// comparison against what this emits read it: a line wide enough for the
    /// formatter to wrap is a file that cannot satisfy them both.
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
        // One line per contract, reading its released lib into its own slot of
        // the array of arrays the sum and the copy walk.
        string memory reads = "";

        for (uint256 i = 0; i < contractNames.length; i++) {
            reads = string.concat(
                reads,
                "        released[",
                vm.toString(i),
                "] = ",
                releasedLibraryName(contractNames[i]),
                ".releasedSuites();\n"
            );
        }

        return string.concat(
            "/// @title ",
            RELEASED_SUITES_LIBRARY,
            "\n/// @notice Every frozen release this repo has cut, of every contract it\n",
            "/// deploys: the per-contract released libs concatenated, in the order the\n",
            "/// build script lists them.\n///\n",
            "/// There is one released lib per deployed contract because a release freezes\n",
            "/// every contract it names into a single tag directory, so a lib that took\n",
            "/// the record whole would give another contract's snapshot this contract's\n",
            "/// suite key and collide with its own entry for that tag. This is where\n",
            "/// those libs meet, and it is emitted from the build script's list -- so a\n",
            "/// contract that is generated, aliased and frozen cannot be missing from\n",
            "/// the declaration, and a release missing from the declaration is a release\n",
            "/// every check quietly stops asking about.\nlibrary ",
            RELEASED_SUITES_LIBRARY,
            " {\n    /// Every released suite, in the order the build script lists them.\n",
            "    /// @return The released suites.\n",
            "    function releasedSuites() internal pure returns (DeploySuite[] memory) {\n",
            string.concat(
                "        DeploySuite[][] memory released = new DeploySuite[][](",
                vm.toString(contractNames.length),
                ");\n",
                reads,
                "        return LibDeploySuiteConcat.concat(released);\n"
            ),
            "    }\n}\n"
        );
    }

    /// Generate the ONE released-suites lib a repo's declaration reads: the
    /// per-contract libs concatenated, in the order `contractNames` lists them.
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
    /// So it is emitted rather than written, from the names the caller passes,
    /// in order.
    ///
    /// Written beside the libs it imports, which is what makes those imports
    /// sibling paths.
    /// @param vm The Vm instance for file operations.
    /// @param libDir The directory the per-contract released libs were written
    /// to, which this is written into as well — `LIB_DIR` for a repo's real
    /// libs, and the only directory the emitted file COMPILES in.
    /// `writeReleasedSuitesLib` takes the same `libDir`, so a build handing
    /// both the one directory is what makes the emitted sibling
    /// `./Lib<Contract>Released.sol` imports resolve, and only `LIB_DIR` holds
    /// the rest of the tree they need; the emitted
    /// `../abstract/RainDeploySuitesBase.sol` import is parent-relative and
    /// constrains the directory further still. A parameter for the same reason
    /// `writeReleasedSuitesLib` takes a record root: a writer that can only be
    /// pointed at the committed declaration can only be tested by overwriting
    /// it, and a test that overwrites a file the rest of the suite reads is a
    /// test that fails on timing. Any other directory holds a file no build can
    /// compile, so it has to be a directory nothing compiles.
    /// @param spdxLicenseIdentifier The SPDX licence identifier the written lib
    /// declares. The calling repo's, for the reason `writeSnapshot` gives.
    /// @param copyrightText The copyright text the written lib declares.
    /// @param contractNames The contracts whose released libs to aggregate.
    /// @param suitesImportPath The path the emitted lib reaches `DeploySuite` by.
    /// @param concatImportPath The path the emitted lib reaches
    /// `LibDeploySuiteConcat` by.
    /// @return The path written.
    function writeReleasedSuitesAggregate(
        Vm vm,
        string memory libDir,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        string[] memory contractNames,
        string memory suitesImportPath,
        string memory concatImportPath
    ) internal returns (string memory) {
        string memory path = pathForLib(libDir, RELEASED_SUITES_LIBRARY);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(
            path,
            string.concat(
                LibCodeGen.filePrefix(spdxLicenseIdentifier, copyrightText),
                "\n",
                aggregateImportBlock(contractNames, suitesImportPath, concatImportPath),
                aggregateLibraryBlock(vm, contractNames)
            )
        );
        return path;
    }

    /// `writeReleasedSuitesAggregate` applied to
    /// `RAIN_SPDX_LICENSE_IDENTIFIER` and `RAIN_COPYRIGHT_TEXT`, for a repo
    /// this org owns.
    /// @param vm The Vm instance for file operations.
    /// @param libDir The directory to write into, under the constraint the
    /// arity above states — `LIB_DIR` for a repo's real libs.
    /// @param contractNames The contracts whose released libs to aggregate.
    /// @param suitesImportPath The path the emitted lib reaches `DeploySuite` by.
    /// @param concatImportPath The path the emitted lib reaches
    /// `LibDeploySuiteConcat` by.
    /// @return The path written.
    function writeReleasedSuitesAggregate(
        Vm vm,
        string memory libDir,
        string[] memory contractNames,
        string memory suitesImportPath,
        string memory concatImportPath
    ) internal returns (string memory) {
        return writeReleasedSuitesAggregate(
            vm,
            libDir,
            RAIN_SPDX_LICENSE_IDENTIFIER,
            RAIN_COPYRIGHT_TEXT,
            contractNames,
            suitesImportPath,
            concatImportPath
        );
    }

    /// `writeReleasedSuitesAggregate` applied to `derivedSuitesImportPath`,
    /// keeping the explicit-licence arity for a repo this org does not own.
    /// @param vm The Vm instance for file operations.
    /// @param libDir The directory to write into.
    /// @param spdxLicenseIdentifier The SPDX licence identifier the written lib
    /// declares.
    /// @param copyrightText The copyright text the written lib declares.
    /// @param contractNames The contracts whose released libs to aggregate.
    /// @return The path written.
    function writeReleasedSuitesAggregate(
        Vm vm,
        string memory libDir,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        string[] memory contractNames
    ) internal returns (string memory) {
        return writeReleasedSuitesAggregate(
            vm,
            libDir,
            spdxLicenseIdentifier,
            copyrightText,
            contractNames,
            derivedSuitesImportPath(vm),
            derivedConcatImportPath(vm)
        );
    }

    /// `writeReleasedSuitesAggregate` applied to `derivedSuitesImportPath` as
    /// well, so a consumer gets its own remapped path without naming it. The
    /// arity above takes an explicit path, for a layout neither case fits.
    /// @param vm The Vm instance for file operations.
    /// @param libDir The directory to write into, under the constraint the
    /// arity above states — `LIB_DIR` for a repo's real libs.
    /// @param contractNames The contracts whose released libs to aggregate.
    /// @return The path written.
    function writeReleasedSuitesAggregate(Vm vm, string memory libDir, string[] memory contractNames)
        internal
        returns (string memory)
    {
        return writeReleasedSuitesAggregate(
            vm, libDir, contractNames, derivedSuitesImportPath(vm), derivedConcatImportPath(vm)
        );
    }

    /// The newest release in a record: the greatest tag any of its files sits
    /// under, compared as a version.
    ///
    /// The empty string when the record holds no release at all. That is a real
    /// state — a repo before its first release, including this one — rather
    /// than a failure, and it cannot be confused with a release because it is
    /// not a tag `isTag` admits or a freeze could ever write.
    ///
    /// A scan rather than the last of `sortedRecordPaths`: the newest release
    /// is what this is asked for, and the path tie break that orders two files
    /// frozen under one tag has nothing to say about which tag is newest.
    /// @param vm The Vm instance for file operations.
    /// @param recordRoot The record root — `LIB_FS_ROOT` for a repo's real
    /// record.
    /// @return The newest frozen tag, or `""` if nothing is frozen.
    function newestFrozenTag(Vm vm, string memory recordRoot) internal view returns (string memory) {
        string[] memory paths = frozenSnapshotPaths(vm, recordRoot);
        if (paths.length == 0) {
            return "";
        }

        string memory newest = tagForRecordPath(vm, paths[0]);
        for (uint256 i = 1; i < paths.length; i++) {
            string memory tag = tagForRecordPath(vm, paths[i]);
            if (tagPrecedes(vm, newest, tag)) {
                newest = tag;
            }
        }
        return newest;
    }

    /// Refuse a release tag that does not strictly follow every tag already in
    /// the record.
    ///
    /// The record is APPEND-ONLY, which is what makes an out-of-order tag
    /// permanent rather than merely wrong: `releasedSuites()` is generated from
    /// the record and declares it forever, `RainDeployVerifyChain` then demands
    /// its addresses stay live on every supported network forever, and the
    /// append-only gate is exactly what stops the directory being deleted. The
    /// only exit is suspending the invariant the whole design rests on.
    ///
    /// Nothing upstream is a substitute. The version is typed by hand into
    /// `foundry.toml` before the cut, so a fat-fingered `0.1.9` cut after
    /// `0.2.0` reaches this call as the release being made.
    /// `SnapshotAlreadyFrozen` is existence-based and has no quarrel with it —
    /// its directory is absent precisely because that release never happened —
    /// and the frozen bytes are the current candidate, already live on chain,
    /// so every downstream check passes and the record simply carries a release
    /// sorted below the newest one.
    ///
    /// Strictly greater, so the newest tag itself is refused too: equality is
    /// not "follows". `SnapshotAlreadyFrozen` also refuses that one, and both
    /// must hold — dropping either one leaves cases the other does not refuse.
    ///
    /// The record root and the tag are parameters, so the refusal is reachable
    /// without a record on disk to re-cut or a `foundry.toml` to rewrite, for
    /// the same reason `frozenSnapshotPaths` takes a root and `tagForVersion`
    /// is split out of `deployTag`. A guard nobody has seen fire is a guard
    /// nobody knows works, which is the whole complaint against an unenforced
    /// rule.
    /// @param vm The Vm instance for file operations.
    /// @param recordRoot The record root — `LIB_FS_ROOT` for a repo's real
    /// record.
    /// @param tag The release tag being cut. MUST be `isTag`.
    function checkReleaseFollowsRecord(Vm vm, string memory recordRoot, string memory tag) internal view {
        string memory newest = newestFrozenTag(vm, recordRoot);
        // A repo that has released nothing has nothing for a first release to
        // follow, so there is no tag it may not be.
        if (bytes(newest).length > 0 && !tagPrecedes(vm, newest, tag)) {
            revert NonMonotonicRelease(tag, newest);
        }
    }

    /// Regenerate the rolling snapshot and freeze it as this release's record,
    /// in that order, in one call.
    ///
    /// Every guard runs, and every byte that will be written is in hand, BEFORE
    /// `<tag>/` is created. Filesystem cheatcodes are not undone by a revert,
    /// so a throw once the directory exists leaves a partial record behind —
    /// and a partial record is
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
    /// - the tag must strictly follow every release already frozen
    ///   (`checkReleaseFollowsRecord`), because the record it is appended to
    ///   cannot be reordered or removed afterwards
    /// - every named contract must have a rolling snapshot, once regenerated
    ///
    /// The frozen copy is the bytes just regenerated, read back from disk, so
    /// "the record matches the candidate" is true by construction rather than
    /// by a comparison afterwards.
    /// @param vm The Vm instance for file operations.
    /// @param root The record root to freeze into — `LIB_FS_ROOT` for a repo's
    /// real record. A parameter for the same reason `frozenSnapshotPaths` and
    /// `writeReleasedSuitesLib` take one, and required rather than defaulted
    /// for the same reason they do not default it: a freeze that can only be
    /// pointed at the real record can only be tested against it, and the real
    /// record is one a test must not leave a release in.
    ///
    /// It is the root of a whole record tree rather than an output directory
    /// to choose: the rolling snapshot is read from under it and the frozen
    /// copy written under it, so a freeze reads and writes ONE tree and there
    /// is no arrangement in which a release is cut from another repo's
    /// candidate.
    /// @param regenerate Rewrites the rolling snapshot. Run first, always.
    /// @param contractNames The contracts whose generated files form this
    /// release's record.
    function freeze(Vm vm, string memory root, function() internal regenerate, string[] memory contractNames) internal {
        string memory tag = deployTag(vm);
        string memory frozenDir = dirForSnapshot(root, tag);
        if (vm.exists(frozenDir)) {
            revert SnapshotAlreadyFrozen(tag, frozenDir);
        }
        if (contractNames.length == 0) {
            revert EmptyRelease(tag);
        }
        // The record this release is appended to is the one it is written into,
        // so the guard reads `root` — the same tree the frozen copy lands
        // under, and the same one the rolling snapshot is read from. A guard
        // pointed at any other tree is a guard pointed away from the record it
        // is protecting: it would pass on a record it is not appending to while
        // the append it is guarding lands somewhere it never looked.
        checkReleaseFollowsRecord(vm, root, tag);

        regenerate();

        // Read the whole record before writing any of it. Every reason this
        // call can fail is now behind it, so what follows is writes only.
        string[] memory records = new string[](contractNames.length);
        for (uint256 i = 0; i < contractNames.length; i++) {
            string memory rollingPath = pathForSnapshot(root, CANDIDATE, contractNames[i]);
            if (!vm.exists(rollingPath)) {
                revert NothingToFreeze(rollingPath);
            }
            records[i] = vm.readFile(rollingPath);
        }

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(frozenDir, true);
        for (uint256 i = 0; i < contractNames.length; i++) {
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.writeFile(pathForSnapshot(root, tag, contractNames[i]), records[i]);
        }
    }
}
