// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {
    LibCodeGen,
    RAIN_COPYRIGHT_TEXT,
    RAIN_SPDX_LICENSE_IDENTIFIER
} from "rain-sol-codegen-0.1.39/src/lib/LibCodeGen.sol";
import {GENERATED_DIR, LibFs} from "rain-sol-codegen-0.1.39/src/lib/LibFs.sol";
import {DeployDependency, DeployMechanism, DeploySuite} from "../abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "./LibRainDeploy.sol";
import {CloneNetworks} from "./LibRainDeployClone.sol";
import {LibRainDeployMechanism} from "./LibRainDeployMechanism.sol";

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

/// Thrown when the state snapshot taken around a clone snapshot's local deploy
/// could not be reverted. The deploy etches the declared factory and
/// implementation and plants the clone; left in place, they would be read by
/// whatever the calling script does next as if they were real.
/// @param suite The suite whose snapshot was being written.
/// @param snapshotId The state snapshot that could not be reverted.
error SnapshotStateRevertFailed(string suite, uint256 snapshotId);

/// Thrown when a file in the frozen record declares no deployed address,
/// declares one as `DEPLOYED_ADDRESS_<x>` where `<x>` is not a chain id in
/// decimal digits, or declares one whose value does not read as an address.
/// The record holds generated snapshots and nothing else, and
/// `DEPLOYED_ADDRESS` is what makes one the record of a deployment rather than
/// a file that happens to be in a release directory. Distinct from
/// `FrozenSnapshotNotReleased`, which is a declaration that is missing
/// something — this is a record that cannot be read at all, and reporting it as
/// undeclared would send the reader after the wrong thing.
/// @param path The record file with no `DEPLOYED_ADDRESS` or
/// `DEPLOYED_ADDRESS_<chainId>` declaration, with a `DEPLOYED_ADDRESS_<x>`
/// whose `<x>` is not decimal, or with a declared value that is not an
/// address.
error FrozenSnapshotUnreadable(string path);

/// Thrown when a file in the frozen record declares its deployed address more
/// than once: `DEPLOYED_ADDRESS` twice, one `DEPLOYED_ADDRESS_<chainId>` twice,
/// or `DEPLOYED_ADDRESS` beside any `DEPLOYED_ADDRESS_<chainId>`. Solidity
/// rejects a second file-scope constant of one name, so no compiler reads the
/// first two at all, and the third is two answers to where the release is.
/// Every rule for choosing between them — first, last, either — reads a value
/// the generator never wrote. A hand edit is what this group exists to catch and a position rule is what it
/// would aim at, so the reader refuses rather than choosing.
/// @param path The record file declaring its deployed address more than once.
error FrozenSnapshotAmbiguous(string path);

/// Thrown when a file in the frozen record declares `MECHANISM_DATA` more than
/// once. Solidity rejects a second file-scope constant of one name, so the
/// record does not compile, and which of the two a released entry carries is
/// a value the generator never wrote.
/// @param path The record file declaring `MECHANISM_DATA` more than once.
error FrozenSnapshotMechanismDataAmbiguous(string path);

/// Thrown when a file in the frozen record declares its deployed addresses per
/// network, as `DEPLOYED_ADDRESS_<chainId>`, and declares no `MECHANISM_DATA`.
/// Only a per-network clone records an address per network, and its entry
/// reads them from the `CloneNetworks` its `MECHANISM_DATA` encodes, so the
/// record is no mechanism's record.
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
        return string.concat("../", SUITES_SOURCE_SUBPATH);
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
        // Unquoted, hyphen and all: a quoted path component is a path error
        // rather than a lookup, and TOML has already normalised the quoted key
        // a consumer spells this pin with.
        string memory key = string.concat(".dependencies.", PACKAGE_NAME);
        if (!vm.keyExistsToml(toml, key)) {
            return suitesImportPathInThisRepo();
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
        return string.concat(PACKAGE_NAME, "-", version, "/", SOURCE_ROOT, "/", SUITES_SOURCE_SUBPATH);
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

    /// The constants a CLONE snapshot declares below `BYTECODE_HASH`: the
    /// Zoltu snapshot's four, with the deploy address described as the clone's,
    /// and `MECHANISM_DATA` — the `abi.encode`d `CloneTarget` the release was
    /// cut with, so a frozen clone is broadcast and derived with the factory,
    /// implementation, init data and salt it was recorded with.
    ///
    /// A per-network clone declares `DEPLOYED_ADDRESS_<chainId>` per network,
    /// in its address order, in place of the one `DEPLOYED_ADDRESS`, and its
    /// `MECHANISM_DATA` is its `CloneNetworks` — see
    /// `perNetworkAddressConstants`.
    /// @param vm The Vm instance for string operations.
    /// @param deployed Where the local deploy put the clone, in the suite's
    /// address order.
    /// @param suite The clone suite.
    /// @return The constants, as Solidity source.
    function cloneSnapshotConstants(Vm vm, address[] memory deployed, DeploySuite memory suite)
        internal
        view
        returns (string memory)
    {
        string memory addressConstants;
        string memory mechanismDataComment;
        bytes memory mechanismData;
        if (suite.mechanism == DeployMechanism.ClonePerNetwork) {
            (addressConstants, mechanismData) = perNetworkAddressConstants(vm, deployed, suite);
            mechanismDataComment = "/// @dev The clone factory call this release was cut with: the\n"
                "/// `abi.encode`d `CloneNetworks` a released suite carries as its\n" "/// `mechanismData`.";
        } else {
            addressConstants = LibCodeGen.addressConstantString(
                vm,
                "/// @dev The deterministic deploy address of the EIP-1167 clone, through its\n"
                "/// factory's open salt.",
                "DEPLOYED_ADDRESS",
                deployed[0]
            );
            mechanismData = suite.mechanismData;
            mechanismDataComment = "/// @dev The clone factory call this release was cut with: the\n"
                "/// `abi.encode`d `CloneTarget` a released suite carries as its\n" "/// `mechanismData`.";
        }
        return string.concat(
            addressConstants,
            LibCodeGen.bytesConstantString(
                vm, "/// @dev The creation bytecode of the contract.", "CREATION_CODE", suite.creationCode
            ),
            LibCodeGen.bytesConstantString(
                vm, "/// @dev The runtime bytecode of the contract.", "RUNTIME_CODE", deployed[0].code
            ),
            LibCodeGen.bytesConstantString(
                vm,
                "/// @dev What MUST already be on a network before this release can be\n"
                "/// broadcast there: an address, and the runtime code that belongs at it.\n"
                "/// `abi.encode`d as a `DeployDependency[]` because Solidity has no\n"
                "/// file-scope constant of dynamic array type.",
                "DEPENDENCIES",
                abi.encode(suite.dependencies)
            ),
            LibCodeGen.bytesConstantString(vm, mechanismDataComment, "MECHANISM_DATA", mechanismData)
        );
    }

    /// A per-network clone's `DEPLOYED_ADDRESS_<chainId>` constants, one per
    /// network in its address order, and the `CloneNetworks` its record
    /// carries as `MECHANISM_DATA`.
    ///
    /// Both record the LOCAL deploy's addresses, never the suite's: the suite's
    /// recorded addresses are a claim the record is what checks, so writing
    /// them back would record a claim as its own evidence.
    /// @param vm The Vm instance for string operations.
    /// @param deployed Where the local deploy put the clone on each network, in
    /// the suite's address order.
    /// @param suite The per-network clone suite.
    /// @return The constants, as Solidity source.
    /// @return The `abi.encode`d `CloneNetworks`, carrying the local deploy's
    /// addresses.
    function perNetworkAddressConstants(Vm vm, address[] memory deployed, DeploySuite memory suite)
        internal
        pure
        returns (string memory, bytes memory)
    {
        CloneNetworks memory clones = LibRainDeployMechanism.cloneNetworks(suite);
        string memory addressConstants = "";
        for (uint256 i = 0; i < clones.networks.length; i++) {
            clones.networks[i].deployedAddress = deployed[i];
            string memory chainId = vm.toString(clones.networks[i].chainId);
            addressConstants = string.concat(
                addressConstants,
                LibCodeGen.addressConstantString(
                    vm,
                    string.concat(
                        "/// @dev The deterministic deploy address of the EIP-1167 clone on chain id\n/// ",
                        chainId,
                        ", through its factory's open salt with that network's init data."
                    ),
                    string.concat("DEPLOYED_ADDRESS_", chainId),
                    deployed[i]
                )
            );
        }
        return (addressConstants, abi.encode(clones));
    }

    /// Generate one snapshot for one SUITE, by the mechanism it declares.
    ///
    /// A Zoltu suite is the `(creationCode, dependencies)` writer above, and its
    /// output is byte-for-byte that writer's.
    ///
    /// A clone suite is deployed through `LibRainDeployMechanism.deployLocally`
    /// — the same local deploy every verification group derives through, so a
    /// written record and a derivation of it agree by construction — inside a
    /// state snapshot that is reverted once the file is written. The file is
    /// built BEFORE the revert because `LibFs` reads the code hash from the
    /// deployed instance.
    /// @param vm The Vm instance for file operations.
    /// @param root The record root — `LIB_FS_ROOT` for a repo's real record.
    /// MUST be a path of record root segments.
    /// @param dir The snapshot directory name — a release tag, or `CANDIDATE`.
    /// @param contractName The contract the snapshot describes.
    /// @param spdxLicenseIdentifier The SPDX licence identifier the written
    /// snapshot declares.
    /// @param copyrightText The copyright text the written snapshot declares.
    /// @param suite The suite to snapshot.
    /// @return The path written.
    function writeSnapshot(
        Vm vm,
        string memory root,
        string memory dir,
        string memory contractName,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        DeploySuite memory suite
    ) internal returns (string memory) {
        if (suite.mechanism == DeployMechanism.Zoltu) {
            LibRainDeployMechanism.checkZoltuMechanismData(suite);
            return writeSnapshot(
                vm,
                root,
                dir,
                contractName,
                spdxLicenseIdentifier,
                copyrightText,
                suite.creationCode,
                suite.dependencies
            );
        }

        uint256 snapshotId = vm.snapshotState();
        writeCloneSnapshotFile(vm, dirForSnapshot(root, dir), contractName, spdxLicenseIdentifier, copyrightText, suite);
        if (!vm.revertToState(snapshotId)) {
            revert SnapshotStateRevertFailed(suite.suite, snapshotId);
        }

        return pathForSnapshot(root, dir, contractName);
    }

    /// Deploy a clone suite locally and write its record into `snapshotDir`.
    /// The caller owns the state snapshot around it: the file is built while
    /// the clone is still deployed because `LibFs` reads the code hash from
    /// the deployed instance. Split out of `writeSnapshot` because the deploy,
    /// the constants and `LibFs`'s seven arguments alongside that function's
    /// own seven parameters are stack too deep on solc 0.8.25 without
    /// `--via-ir`.
    /// @param vm The Vm instance for file operations.
    /// @param snapshotDir The checked directory to write into.
    /// @param contractName The contract the snapshot describes.
    /// @param spdxLicenseIdentifier The SPDX licence identifier the written
    /// snapshot declares.
    /// @param copyrightText The copyright text the written snapshot declares.
    /// @param suite The clone suite to snapshot.
    function writeCloneSnapshotFile(
        Vm vm,
        string memory snapshotDir,
        string memory contractName,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        DeploySuite memory suite
    ) internal {
        address[] memory deployed = LibRainDeployMechanism.deployLocally(vm, suite);
        string memory constants = cloneSnapshotConstants(vm, deployed, suite);
        LibFs.buildFileForContract(
            vm, deployed[0], snapshotDir, contractName, spdxLicenseIdentifier, copyrightText, constants
        );
    }

    /// `writeSnapshot` for a suite, applied to `RAIN_SPDX_LICENSE_IDENTIFIER`
    /// and `RAIN_COPYRIGHT_TEXT`, for a repo this org owns.
    /// @param vm The Vm instance for file operations.
    /// @param root The record root — `LIB_FS_ROOT` for a repo's real record.
    /// MUST be a path of record root segments.
    /// @param dir The snapshot directory name — a release tag, or `CANDIDATE`.
    /// @param contractName The contract the snapshot describes.
    /// @param suite The suite to snapshot.
    /// @return The path written.
    function writeSnapshot(
        Vm vm,
        string memory root,
        string memory dir,
        string memory contractName,
        DeploySuite memory suite
    ) internal returns (string memory) {
        return writeSnapshot(vm, root, dir, contractName, RAIN_SPDX_LICENSE_IDENTIFIER, RAIN_COPYRIGHT_TEXT, suite);
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
        string memory libraryName = string.concat("Lib", contractName, "Deploy");
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

    /// @dev The declaration a generated snapshot records its deploy address in.
    /// Matched whole and from the START of its line, so what is being looked
    /// for is the DECLARATION: it cannot be satisfied by characters that happen
    /// to occur inside a hex payload, nor by a line that merely CONTAINS the
    /// declaration text — a commented-out copy carrying some other address is
    /// exactly the hand edit this whole group exists to catch, and it is at
    /// file scope in every generated snapshot, so there is no indentation to
    /// allow for.
    ///
    /// The start of a line is what makes a `//` copy unreachable, because `//`
    /// has to sit in front of the text it comments out. It does nothing to a
    /// `/* ... */` copy, whose delimiters are on their own lines and whose
    /// contents therefore start their lines exactly as the real declaration
    /// does. Block comments come out of the record before this rule runs, so
    /// that what it runs on is what the compiler would see.
    string constant DEPLOYED_ADDRESS_DECLARATION = "address constant DEPLOYED_ADDRESS =";

    /// @dev The start of the declaration a per-network snapshot records one
    /// network's deploy address in: `DEPLOYED_ADDRESS_<chainId> =`. Matched
    /// from the start of its line for the reasons `DEPLOYED_ADDRESS_DECLARATION`
    /// is.
    string constant DEPLOYED_ADDRESS_CHAIN_DECLARATION_PREFIX = "address constant DEPLOYED_ADDRESS_";

    /// @dev The declaration a clone snapshot records its `mechanismData` in.
    /// Matched from the start of its line for the reasons
    /// `DEPLOYED_ADDRESS_DECLARATION` is.
    string constant MECHANISM_DATA_DECLARATION = "bytes constant MECHANISM_DATA =";

    /// The addresses a frozen record declares as its deploy addresses, and the
    /// chain id each is for.
    ///
    /// A record declares either ONE `DEPLOYED_ADDRESS`, the address on every
    /// network, or one `DEPLOYED_ADDRESS_<chainId>` per network, which is what
    /// a per-network clone records. The first reads as one address and no
    /// chain ids; the second as each declaration's chain id and address, in
    /// file order — the order the writer emits them, which is the suite's
    /// address order.
    ///
    /// `LibCodeGen` emits an address constant on ONE line — wrapping needs 120
    /// characters, `DEPLOYED_ADDRESS` occupies 88 and `DEPLOYED_ADDRESS_<chainId>`
    /// would need a chain id of more than 31 digits — so a declaration is a
    /// line, and its value is that line's last token with the
    /// type wrapper and the terminator stripped. `address(0x...);` and a bare
    /// `0x...;` read the same, so which wrapper the generator chose is not
    /// something this has to know.
    ///
    /// That every generated snapshot HAS this declaration, second, of type
    /// `address`, is pinned by `GeneratedSnapshotShapeTest` against the
    /// compiler's own AST. Read from the text here rather than from that AST
    /// because a record is reached by its PATH, which is what the walk returns,
    /// while its artifact path is not something a caller can name — foundry
    /// disambiguates those by whatever else happens to share the basename.
    ///
    /// The whole record is scanned before a match is read, so a record
    /// carrying `DEPLOYED_ADDRESS` twice, one chain id twice, or both forms is
    /// refused rather than resolved by position. A per-network declaration's
    /// chain id is read by `declaredChainId`, and every declaration's address
    /// by `declaredAddress`.
    /// @param vm The Vm instance for string operations.
    /// @param path The record file, for the error only.
    /// @param record The record file's contents.
    /// @return The chain id each address is for: empty for a record declaring
    /// `DEPLOYED_ADDRESS`.
    /// @return The addresses the record declares, in file order.
    function recordedDeployedAddresses(Vm vm, string memory path, string memory record)
        internal
        pure
        returns (uint256[] memory, address[] memory)
    {
        string[] memory lines = vm.split(withoutBlockComments(vm, record), "\n");
        uint256[] memory chainIds = new uint256[](lines.length);
        address[] memory addresses = new address[](lines.length);
        uint256 perNetwork = 0;
        bool everyNetwork = false;
        for (uint256 i = 0; i < lines.length; i++) {
            bool isEveryNetwork = vm.indexOf(lines[i], DEPLOYED_ADDRESS_DECLARATION) == 0;
            if (!isEveryNetwork && vm.indexOf(lines[i], DEPLOYED_ADDRESS_CHAIN_DECLARATION_PREFIX) != 0) {
                continue;
            }
            if (everyNetwork || (isEveryNetwork && perNetwork != 0)) {
                revert FrozenSnapshotAmbiguous(path);
            }
            string[] memory tokens = vm.split(lines[i], " ");
            address declared = declaredAddress(vm, path, tokens[tokens.length - 1]);
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

    /// The address a declaration line's value names: its last token with the
    /// `address(` wrapper and the terminator stripped.
    ///
    /// A value `vm.parseAddress` cannot read is not one the generator writes,
    /// and the record is refused as `FrozenSnapshotUnreadable` rather than by
    /// the cheatcode's untyped revert.
    /// @param vm The Vm instance for string operations.
    /// @param path The record file, for the error only.
    /// @param value The declaration line's last token.
    /// @return The address.
    function declaredAddress(Vm vm, string memory path, string memory value) internal pure returns (address) {
        string memory bare = vm.replace(vm.replace(vm.replace(value, "address(", ""), ")", ""), ";", "");
        try vm.parseAddress(bare) returns (address declared) {
            return declared;
        } catch {
            revert FrozenSnapshotUnreadable(path);
        }
    }

    /// The chain id a per-network declaration line names: the characters from
    /// the end of `DEPLOYED_ADDRESS_CHAIN_DECLARATION_PREFIX` to the next space,
    /// read as a decimal number.
    ///
    /// Every one of them MUST be a decimal digit, there MUST be at least one,
    /// and the number MUST fit in a `uint256`. Anything else is not a name the
    /// generator writes, and the record is refused as
    /// `FrozenSnapshotUnreadable`. Read here rather than by `vm.parseUint`,
    /// which reverts untyped on a non-number and reads a `0x` suffix as
    /// hexadecimal, so `DEPLOYED_ADDRESS_0x89` would read as chain 137.
    /// @param path The record file, for the error only.
    /// @param line A line starting with
    /// `DEPLOYED_ADDRESS_CHAIN_DECLARATION_PREFIX`.
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
        if (end == start) {
            revert FrozenSnapshotUnreadable(path);
        }
        return chainId;
    }

    /// A record's text with every block comment removed, so that a declaration
    /// found in it is one the compiler would read.
    ///
    /// `/*` opens a comment that the first following `*/` closes, and Solidity
    /// does not nest them, so what survives is the text before the first `/*`
    /// plus, for each one after it, the text after its `*/`. An unclosed `/*`
    /// is comment to the end of the file, so nothing after it survives.
    ///
    /// A comment is removed rather than blanked, which joins the text either
    /// side of it into one line exactly as the compiler joins it. A declaration
    /// the compiler reads on the tail of a `*/` is therefore still found, and
    /// one interrupted mid-line by a comment is not — that leaves the record
    /// unreadable, never read as some other address.
    /// @param vm The Vm instance for string operations.
    /// @param record The record file's contents.
    /// @return The contents with every block comment removed.
    function withoutBlockComments(Vm vm, string memory record) internal pure returns (string memory) {
        string[] memory opened = vm.split(record, "/*");
        string memory stripped = opened[0];
        for (uint256 i = 1; i < opened.length; i++) {
            string[] memory closed = vm.split(opened[i], "*/");
            if (closed.length == 1) {
                break;
            }
            stripped = string.concat(stripped, closed[1]);
            for (uint256 j = 2; j < closed.length; j++) {
                stripped = string.concat(stripped, "*/", closed[j]);
            }
        }
        return stripped;
    }

    /// The mechanism a frozen record was cut with, read from the declarations
    /// the record carries:
    ///
    /// - no `MECHANISM_DATA`: `Zoltu`;
    /// - `MECHANISM_DATA` and `DEPLOYED_ADDRESS`: `Clone`;
    /// - `MECHANISM_DATA` and `DEPLOYED_ADDRESS_<chainId>`: `ClonePerNetwork`.
    ///
    /// Each release is read on its own, so a suite whose mechanism changed
    /// between releases still has every release read as the mechanism it was
    /// cut with.
    ///
    /// The address declarations are read by `recordedDeployedAddresses`, the
    /// reader the record check matches releases with, so a record with no
    /// deployed address is refused as `FrozenSnapshotUnreadable` and one
    /// declaring both forms as `FrozenSnapshotAmbiguous`, here as there. A
    /// record declaring `MECHANISM_DATA` more than once is refused as
    /// `FrozenSnapshotMechanismDataAmbiguous`, and one declaring per-network
    /// addresses without it as `FrozenSnapshotMechanismDataMissing`.
    /// `MECHANISM_DATA_DECLARATION` is matched in the text block comments are
    /// removed from, as the address declarations are.
    /// @param vm The Vm instance for file and string operations.
    /// @param path A record file, as `frozenSnapshotPaths` returns it.
    /// @return The mechanism the record was cut with.
    function recordedMechanism(Vm vm, string memory path) internal view returns (DeployMechanism) {
        string memory record = vm.readFile(path);
        (uint256[] memory chainIds,) = recordedDeployedAddresses(vm, path, record);
        string[] memory lines = vm.split(withoutBlockComments(vm, record), "\n");
        uint256 mechanismData = 0;
        for (uint256 i = 0; i < lines.length; i++) {
            if (vm.indexOf(lines[i], MECHANISM_DATA_DECLARATION) == 0) {
                mechanismData++;
            }
        }
        if (mechanismData > 1) {
            revert FrozenSnapshotMechanismDataAmbiguous(path);
        }
        if (mechanismData == 0) {
            if (chainIds.length != 0) {
                revert FrozenSnapshotMechanismDataMissing(path);
            }
            return DeployMechanism.Zoltu;
        }
        return chainIds.length == 0 ? DeployMechanism.Clone : DeployMechanism.ClonePerNetwork;
    }

    /// The aliased import one record file contributes: all four consensus
    /// fields and the frozen dependency list, under that release's prefix —
    /// and, for a clone, its `MECHANISM_DATA`. A per-network clone imports no
    /// `DEPLOYED_ADDRESS`: its record declares one per network, and its entry
    /// reads them from its `MECHANISM_DATA`.
    ///
    /// Which of these the import is comes from the record itself, by
    /// `recordedMechanism`, so every name imported is one the record declares.
    ///
    /// Split per file rather than inlined into the block for the same reason
    /// `snapshotConstants` is split out of `writeSnapshot`: the aliases and
    /// the path they come from are more live values than the legacy codegen has
    /// stack for.
    /// @param vm The Vm instance for file and string operations.
    /// @param path A record file, as `frozenSnapshotPaths` returns it.
    /// @return The import statement, and the blank line after it.
    function releasedImport(Vm vm, string memory path) internal view returns (string memory) {
        string memory prefix = releasedConstantPrefix(vm, path);
        DeployMechanism mechanism = recordedMechanism(vm, path);
        return string.concat(
            mechanism == DeployMechanism.ClonePerNetwork
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
            mechanism == DeployMechanism.Zoltu
                ? string("")
                : string.concat(",\n    MECHANISM_DATA as ", prefix, "_MECHANISM_DATA"),
            "\n} from \"../generated/",
            tagForRecordPath(vm, path),
            "/",
            contractForRecordPath(vm, path),
            ".sol\";\n\n"
        );
    }

    /// The import block of a generated released-suites lib.
    ///
    /// One aliased import per record file, carrying all four consensus fields
    /// and the frozen dependency list, plus the `MECHANISM_DATA` of each record
    /// `recordedMechanism` reads as a clone. A released entry can therefore
    /// only say what its own frozen snapshot says — there is no path by which a
    /// released address, code hash, creation code, runtime code, dependency
    /// list or mechanism is written anywhere but into the immutable record.
    /// @param vm The Vm instance for file and string operations.
    /// @param paths The record's files, in the order they are emitted.
    /// @param suitesImportPath The path the emitted lib reaches the suite types
    /// by — `suitesImportPathInThisRepo` for a lib written into this repo's own
    /// `LIB_DIR`, and the consumer's remapped path otherwise.
    /// @return The import block.
    function releasedImportBlock(Vm vm, string[] memory paths, string memory suitesImportPath)
        internal
        view
        returns (string memory)
    {
        string memory imports = string.concat(
            "import {DeployDependency, DeployMechanism, DeploySuite} from \"", suitesImportPath, "\";\n\n"
        );
        for (uint256 i = 0; i < paths.length; i++) {
            imports = string.concat(imports, releasedImport(vm, paths[i]));
        }
        return imports;
    }

    /// `releasedImportBlock` applied to this repo's own `suitesImportPathInThisRepo`.
    /// @param vm The Vm instance for file and string operations.
    /// @param paths The record's files, in the order they are emitted.
    /// @return The import block.
    function releasedImportBlock(Vm vm, string[] memory paths) internal view returns (string memory) {
        return releasedImportBlock(vm, paths, suitesImportPathInThisRepo());
    }

    /// One `suites[i] = DeploySuite({...});` entry of a generated
    /// released-suites lib. `releasedLibraryBlock` says where each field comes
    /// from. The mechanism kind is the record's own, by `recordedMechanism`.
    /// Two `string.concat`s rather than one, to stay inside the stack.
    /// @param vm The Vm instance for file and string operations.
    /// @param i The entry's index.
    /// @param path The record file the entry aliases.
    /// @param template The candidate declaration the key and the artifact path
    /// come from.
    /// @return The entry.
    function releasedSuiteEntry(Vm vm, uint256 i, string memory path, DeploySuite memory template)
        internal
        view
        returns (string memory)
    {
        string memory prefix = releasedConstantPrefix(vm, path);
        string memory storedDeployedAddress;
        string memory mechanism;
        {
            DeployMechanism kind = recordedMechanism(vm, path);
            storedDeployedAddress = kind == DeployMechanism.ClonePerNetwork
                ? string("address(0)")
                : string.concat(prefix, "_DEPLOYED_ADDRESS");
            mechanism = kind == DeployMechanism.Zoltu
                ? string("DeployMechanism.Zoltu,\n            mechanismData: \"\"")
                : string.concat(
                    kind == DeployMechanism.Clone ? "DeployMechanism.Clone" : "DeployMechanism.ClonePerNetwork",
                    ",\n            mechanismData: ",
                    prefix,
                    "_MECHANISM_DATA"
                );
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
            "_DEPENDENCIES, (DeployDependency[])),\n            mechanism: ",
            mechanism,
            "\n        });\n"
        );
    }

    /// The library block of a generated released-suites lib.
    ///
    /// FIVE fields per entry alias the frozen snapshot: the four consensus
    /// fields and the dependency list. The dependency list is aliased rather
    /// than rebuilt from `template` because it is a precondition of the
    /// deployment and not metadata — `RainDeployBroadcast.run` passes it to
    /// `LibRainDeploy.deployToNetworks`, which refuses to broadcast on a
    /// network where one of them has no code, or holds code other than the
    /// `runtimeCode` the entry declares. Broadcasting a
    /// past release onto a newly supported chain therefore has to check the
    /// list that release was cut with, so it is read from that release's own
    /// frozen snapshot.
    ///
    /// The key and the artifact path come from `template`, the candidate
    /// declaration, and are regenerated from it on every build: they are
    /// explorer and ordering metadata rather than anything a broadcast acts on,
    /// and preserving what a previous generation wrote would mean parsing
    /// generated Solidity back in.
    ///
    /// The mechanism comes from the record, kind and data both. The kind is
    /// what `recordedMechanism` reads from each record on its own, so a suite
    /// whose mechanism changed between releases emits every entry as its
    /// release was cut, whatever `template` declares now. The data is `""` for
    /// Zoltu and the release's own `MECHANISM_DATA` for a clone, so a frozen
    /// clone is broadcast with the `CloneTarget` or `CloneNetworks` it was cut
    /// with. A per-network clone's entry records `storedDeployedAddress` as
    /// zero, since its `CloneNetworks` records its address on each network.
    ///
    /// The key is the template's with the tag appended, so every entry is
    /// unique and `allSuites`'s duplicate check is satisfied by construction
    /// rather than by whoever writes the declaration.
    /// @param vm The Vm instance for file and string operations.
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
    ) internal view returns (string memory) {
        string memory entries = "";
        for (uint256 i = 0; i < paths.length; i++) {
            entries = string.concat(entries, releasedSuiteEntry(vm, i, paths[i], template));
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
    /// Named `Lib<Contract>Released`, the same `Lib<Contract>` shape the alias
    /// lib is named with, into the directory it is handed.
    ///
    /// Every field of an entry but two comes from the frozen snapshot, the
    /// mechanism kind included, which `recordedMechanism` reads from each
    /// release's own record. The other two come from `template`. Those two — the key and the artifact path — are explorer and
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
    /// @param libDir The directory to write the lib into — `LIB_DIR` for a
    /// repo's real tree. A parameter for the same reason `recordRoot` is one,
    /// and the directory MUST already exist.
    /// @param recordRoot The record root to read releases from — `LIB_FS_ROOT`
    /// for a repo's real record. A parameter for the same reason
    /// `frozenSnapshotPaths` takes one: a writer that can only be pointed at
    /// the real record can only be tested against it, and a repo that has cut
    /// no release has nothing there to test against.
    /// @param contractName The contract the released record describes.
    /// @param spdxLicenseIdentifier The SPDX licence identifier the written lib
    /// declares. The calling repo's, for the reason `writeSnapshot` gives.
    /// @param copyrightText The copyright text the written lib declares.
    /// @param template The candidate declaration the metadata comes from.
    /// @return The path written.
    function writeReleasedSuitesLib(
        Vm vm,
        string memory libDir,
        string memory recordRoot,
        string memory contractName,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        DeploySuite memory template,
        string memory suitesImportPath
    ) internal returns (string memory) {
        string memory libraryName = releasedLibraryName(contractName);
        string memory path = pathForLib(libDir, libraryName);
        // `paths` is scoped away before the write, and the body built first,
        // because `libDir` is one local past what this function's stack frame
        // holds: inlined into the `writeFile` call the way the other writers
        // spell it, solc 0.8.25 without `--via-ir` refuses it as stack too
        // deep. Not a style choice — the flat form does not compile.
        string memory body;
        {
            string[] memory paths = recordPathsForContract(vm, recordRoot, contractName);
            body = string.concat(
                releasedImportBlock(vm, paths, suitesImportPath),
                releasedLibraryBlock(vm, libraryName, contractName, paths, template)
            );
        }

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
    /// @return The path written.
    function writeReleasedSuitesLib(
        Vm vm,
        string memory libDir,
        string memory recordRoot,
        string memory contractName,
        DeploySuite memory template,
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
    /// @return The path written.
    function writeReleasedSuitesLib(
        Vm vm,
        string memory libDir,
        string memory recordRoot,
        string memory contractName,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        DeploySuite memory template
    ) internal returns (string memory) {
        // Derived into a local before the forward, not inlined as the eighth
        // argument: eight arguments and the derivation's own temporaries alive
        // at once is stack too deep on solc 0.8.25 without `--via-ir`, the same
        // limit the full arity's body is already shaped around. Not a style
        // choice — the inlined form does not compile.
        string memory suitesImportPath = derivedSuitesImportPath(vm);
        return writeReleasedSuitesLib(
            vm, libDir, recordRoot, contractName, spdxLicenseIdentifier, copyrightText, template, suitesImportPath
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
    /// @return The path written.
    function writeReleasedSuitesLib(
        Vm vm,
        string memory libDir,
        string memory recordRoot,
        string memory contractName,
        DeploySuite memory template
    ) internal returns (string memory) {
        return writeReleasedSuitesLib(vm, libDir, recordRoot, contractName, template, derivedSuitesImportPath(vm));
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
    /// @return The import block.
    function aggregateImportBlock(string[] memory contractNames, string memory suitesImportPath)
        internal
        pure
        returns (string memory)
    {
        string memory imports = string.concat("import {DeploySuite} from \"", suitesImportPath, "\";\n\n");
        for (uint256 i = 0; i < contractNames.length; i++) {
            string memory libraryName = releasedLibraryName(contractNames[i]);
            imports = string.concat(imports, "import {", libraryName, "} from \"./", libraryName, ".sol\";\n\n");
        }
        return imports;
    }

    /// `aggregateImportBlock` applied to this repo's own `suitesImportPathInThisRepo`.
    /// @param contractNames The contracts whose released libs to aggregate.
    /// @return The import block.
    function aggregateImportBlock(string[] memory contractNames) internal pure returns (string memory) {
        return aggregateImportBlock(contractNames, suitesImportPathInThisRepo());
    }

    /// The library block of the generated aggregate lib: every per-contract
    /// released lib read once and copied into one array, in declaration order.
    ///
    /// It emits the concatenation rather than computing one, because the
    /// entries are only known when the emitted source RUNS: a released lib
    /// declares its own releases, and how many it has is not a thing this
    /// emitter can see or should have to. So the emitted code reads every
    /// released lib into one array of arrays, sums their lengths at runtime,
    /// and copies each one in at the offset the libs before it end at.
    ///
    /// That sum and that copy are loops over the array of arrays rather than
    /// expressions naming every contract, so no emitted line is wider for a
    /// repo with more contracts in it. The emitted file is committed, and both
    /// `forge fmt --check` and a byte-for-byte comparison against what this
    /// emits read it: a line wide enough for the formatter to wrap is a file
    /// that cannot satisfy them both.
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
            "    /// @return The released suites.\n",
            "    function releasedSuites() internal pure returns (DeploySuite[] memory) {\n",
            contractNames.length == 0
                ? "        return new DeploySuite[](0);\n"
                : string.concat(
                    "        DeploySuite[][] memory released = new DeploySuite[][](",
                    vm.toString(contractNames.length),
                    ");\n",
                    reads,
                    "\n        uint256 total = 0;\n",
                    "        for (uint256 i = 0; i < released.length; i++) {\n",
                    "            total += released[i].length;\n",
                    "        }\n\n",
                    "        DeploySuite[] memory suites = new DeploySuite[](total);\n\n",
                    "        uint256 offset = 0;\n",
                    "        for (uint256 i = 0; i < released.length; i++) {\n",
                    "            for (uint256 j = 0; j < released[i].length; j++) {\n",
                    "                suites[offset + j] = released[i][j];\n",
                    "            }\n",
                    "            offset += released[i].length;\n",
                    "        }\n\n",
                    "        return suites;\n"
                ),
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
    /// @return The path written.
    function writeReleasedSuitesAggregate(
        Vm vm,
        string memory libDir,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        string[] memory contractNames,
        string memory suitesImportPath
    ) internal returns (string memory) {
        string memory path = pathForLib(libDir, RELEASED_SUITES_LIBRARY);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(
            path,
            string.concat(
                LibCodeGen.filePrefix(spdxLicenseIdentifier, copyrightText),
                "\n",
                aggregateImportBlock(contractNames, suitesImportPath),
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
    /// @return The path written.
    function writeReleasedSuitesAggregate(
        Vm vm,
        string memory libDir,
        string[] memory contractNames,
        string memory suitesImportPath
    ) internal returns (string memory) {
        return writeReleasedSuitesAggregate(
            vm, libDir, RAIN_SPDX_LICENSE_IDENTIFIER, RAIN_COPYRIGHT_TEXT, contractNames, suitesImportPath
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
            vm, libDir, spdxLicenseIdentifier, copyrightText, contractNames, derivedSuitesImportPath(vm)
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
        return writeReleasedSuitesAggregate(vm, libDir, contractNames, derivedSuitesImportPath(vm));
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
    /// Nothing upstream is a substitute. The tag is a human-typed `sol-v*` that
    /// `rainix-tag-release` seds straight into `foundry.toml` after checking
    /// only that it is on `main` and shaped `X.Y.Z`, so a fat-fingered `0.1.9`
    /// cut after `0.2.0` reaches this call as the release being made.
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
