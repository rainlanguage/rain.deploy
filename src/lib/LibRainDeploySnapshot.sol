// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.16.2/src/Vm.sol";
import {
    LibCodeGen,
    RAIN_COPYRIGHT_TEXT,
    RAIN_SPDX_LICENSE_IDENTIFIER
} from "rain-sol-codegen-0.1.36/src/lib/LibCodeGen.sol";
import {GENERATED_DIR, LibFs} from "rain-sol-codegen-0.1.36/src/lib/LibFs.sol";
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

/// Thrown when a release tag does not strictly follow every tag already frozen
/// in the record. The record is append-only, so a tag frozen out of order can
/// never be removed: `releasedSuites()` declares it forever and the chain group
/// then demands it be live on every supported network forever. Refused at the
/// one place a release identity is minted, rather than discovered afterwards by
/// whoever reads the record and finds a release nobody cut.
/// @param tag The tag being cut.
/// @param newestFrozenTag The newest tag already in the record.
error NonMonotonicRelease(string tag, string newestFrozenTag);

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
    /// `candidate/ 0_1_6/ 0_1_7/` and "which one is current" is answered by
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

    /// Whether `subject` is three numbers joined by exactly two `separator`s,
    /// each written without a leading zero.
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

    /// The directory holding a snapshot, rolling or frozen, under a record
    /// root.
    ///
    /// Refuses a directory name `LibFs` would refuse to write into, through
    /// `LibFs.requireTag` rather than through a rule restated here. A reader
    /// that admitted a name the writer refuses is a reader pointed at a path
    /// nothing can ever have written, and a fixture record that admitted one
    /// would be a fixture of a layout the real record cannot hold.
    /// @param root The record root — `LIB_FS_ROOT` for a repo's real record.
    /// @param dir The snapshot directory name — a release tag, or `CANDIDATE`.
    /// MUST be drawn from `LibFs`'s tag alphabet.
    /// @return The directory path.
    function dirForSnapshot(string memory root, string memory dir) internal pure returns (string memory) {
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
    /// There is no output root to choose. `LibFs.buildFileForTaggedContract`
    /// derives its directory from `LIB_FS_ROOT` and the snapshot directory it is
    /// handed, and this is the repo's real deploy record, which belongs under
    /// that root and nowhere else. This is the one place a snapshot's bytes come
    /// into existence, and they come from the compiler rather than from another
    /// tree, so there is nothing for a root to select between.
    ///
    /// `freeze` does take a root and that is not the same freedom: it COPIES,
    /// within one record tree, reading a rolling snapshot under the root it is
    /// handed and writing the frozen copy under that same root. Pointing a
    /// copier at a tree of its own is a thing a test genuinely needs, exactly
    /// as pointing `frozenSnapshotPaths` at one is; GENERATING this repo's
    /// record anywhere but under `LIB_FS_ROOT` remains something nothing here
    /// can express.
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
    /// A snapshot lands in the calling repo's own tree, so the header is that
    /// repo's statement. Repos outside this org call this overload; repos
    /// inside it call the one that defaults to the org's values.
    /// @param vm The Vm instance for file operations.
    /// @param dir The snapshot directory name — a release tag, or `CANDIDATE`.
    /// @param contractName The contract the snapshot describes.
    /// @param spdxLicenseIdentifier The SPDX licence identifier the written
    /// snapshot declares.
    /// @param copyrightText The copyright text the written snapshot declares.
    /// @param creationCode That contract's creation code.
    /// @param dependencies The addresses that must already have code on a
    /// network before this contract can be broadcast there.
    /// @return The path written.
    function writeSnapshot(
        Vm vm,
        string memory dir,
        string memory contractName,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        bytes memory creationCode,
        address[] memory dependencies
    ) internal returns (string memory) {
        LibRainDeploy.etchZoltuFactory(vm);

        address deployed = LibRainDeploy.deployZoltu(creationCode);
        string memory constants = snapshotConstants(vm, deployed, creationCode, dependencies);

        // The directory is created by the writer, from the same tag this path is
        // derived from, so there is no `createDir` here to disagree with it.
        LibFs.buildFileForTaggedContract(
            vm, deployed, dir, contractName, spdxLicenseIdentifier, copyrightText, constants
        );

        return pathForSnapshot(dir, contractName);
    }

    /// `writeSnapshot` applied to `RAIN_SPDX_LICENSE_IDENTIFIER` and
    /// `RAIN_COPYRIGHT_TEXT`, for a repo this org owns.
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
        return writeSnapshot(
            vm, dir, contractName, RAIN_SPDX_LICENSE_IDENTIFIER, RAIN_COPYRIGHT_TEXT, creationCode, dependencies
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
    /// problem, to save a caller one short string. The library name and output
    /// path ARE derived, because `Lib<Contract>Deploy` at `src/lib/` is
    /// mechanical.
    ///
    /// The header comes from `LibCodeGen.filePrefix`, the same one `LibFs`
    /// gives a snapshot, so an alias lib and a snapshot say they are generated
    /// in identical words and neither restates the other. The licence and the
    /// copyright holder are the calling repo's, for the reason `writeSnapshot`
    /// gives, and reach `filePrefix` from here unchanged.
    /// @param vm The Vm instance for file operations.
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
        string memory contractName,
        string memory constantPrefix,
        string memory dir,
        string memory spdxLicenseIdentifier,
        string memory copyrightText
    ) internal returns (string memory) {
        string memory libraryName = string.concat("Lib", contractName, "Deploy");
        string memory path = string.concat("src/lib/", libraryName, ".sol");

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
    /// @param contractName The contract the alias lib is written for.
    /// @param constantPrefix The prefix for the emitted constants.
    /// @param dir The snapshot directory to alias.
    /// @return The path written.
    function writeAliasLib(Vm vm, string memory contractName, string memory constantPrefix, string memory dir)
        internal
        returns (string memory)
    {
        return writeAliasLib(vm, contractName, constantPrefix, dir, RAIN_SPDX_LICENSE_IDENTIFIER, RAIN_COPYRIGHT_TEXT);
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
    /// @param spdxLicenseIdentifier The SPDX licence identifier the written lib
    /// declares. The calling repo's, for the reason `writeSnapshot` gives.
    /// @param copyrightText The copyright text the written lib declares.
    /// @param template The candidate declaration the metadata comes from.
    /// @return The path written.
    function writeReleasedSuitesLib(
        Vm vm,
        string memory recordRoot,
        string memory contractName,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        DeploySuite memory template
    ) internal returns (string memory) {
        string memory libraryName = string.concat("Lib", contractName, "Released");
        string memory path = string.concat("src/lib/", libraryName, ".sol");
        string[] memory paths = recordPathsForContract(vm, recordRoot, contractName);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(
            path,
            string.concat(
                LibCodeGen.filePrefix(spdxLicenseIdentifier, copyrightText),
                "\n",
                releasedImportBlock(vm, paths),
                releasedLibraryBlock(vm, libraryName, contractName, paths, template)
            )
        );
        return path;
    }

    /// `writeReleasedSuitesLib` applied to `RAIN_SPDX_LICENSE_IDENTIFIER` and
    /// `RAIN_COPYRIGHT_TEXT`, for a repo this org owns.
    /// @param vm The Vm instance for file operations.
    /// @param recordRoot The record root — `LIB_FS_ROOT` for a repo's real
    /// record.
    /// @param contractName The contract the released lib is written for.
    /// @param template The suite the released entries take their key and
    /// artifact path from.
    /// @return The path written.
    function writeReleasedSuitesLib(
        Vm vm,
        string memory recordRoot,
        string memory contractName,
        DeploySuite memory template
    ) internal returns (string memory) {
        return writeReleasedSuitesLib(
            vm, recordRoot, contractName, RAIN_SPDX_LICENSE_IDENTIFIER, RAIN_COPYRIGHT_TEXT, template
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
    /// @return newest The newest frozen tag, or `""` if nothing is frozen.
    function newestFrozenTag(Vm vm, string memory recordRoot) internal view returns (string memory newest) {
        string[] memory paths = frozenSnapshotPaths(vm, recordRoot);
        for (uint256 i = 0; i < paths.length; i++) {
            string memory tag = tagForRecordPath(vm, paths[i]);
            if (bytes(newest).length == 0 || tagPrecedes(vm, newest, tag)) {
                newest = tag;
            }
        }
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
    /// must hold — neither guard is load bearing alone.
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
