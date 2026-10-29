// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DerivedDeploy, RainDeployVerifyBase} from "./RainDeployVerifyBase.sol";
import {DeployDeclaration, DeploySuite, DerivationSnapshotRevertFailed} from "./RainDeploySuitesBase.sol";
import {LibRainDeployDescribedByMeta} from "../lib/LibRainDeployDescribedByMeta.sol";
import {LibRainDeploySnapshot} from "../lib/LibRainDeploySnapshot.sol";

/// Thrown when the deploy address recorded for a version is not the address its own mechanism
/// derives.
/// @param suite The suite that failed.
/// @param storedAddress The address the suite records.
/// @param derivedAddress The address its mechanism derives.
error StoredAddressMismatch(string suite, address storedAddress, address derivedAddress);

/// Thrown when the deployed code hash recorded for a version is not the hash its own mechanism
/// produces.
/// @param suite The suite that failed.
/// @param storedCodeHash The code hash the suite records.
/// @param derivedCodeHash The code hash its mechanism produces.
error StoredCodeHashMismatch(string suite, bytes32 storedCodeHash, bytes32 derivedCodeHash);

/// Thrown when the runtime code recorded for a version does not hash to the
/// code hash recorded beside it.
/// @param suite The suite that failed.
/// @param storedBytecodeHash The code hash the suite records.
/// @param runtimeCodeHash The hash of the runtime code the suite records.
error StoredRuntimeCodeHashMismatch(string suite, bytes32 storedBytecodeHash, bytes32 runtimeCodeHash);

/// Thrown when a file in the frozen record is declared by no released suite.
/// The record is append-only, so this never goes away by itself: a release the
/// declaration missed is a release the chain group never asks about, and the
/// chain group passing means nothing for it.
/// @param path The frozen record file no released suite declares.
error FrozenSnapshotNotReleased(string path);

/// Thrown when the frozen record holds more files recording one deploy address list than the
/// declaration holds released suites deriving it.
/// @param path The record file the record ran out of declarations at.
/// @param deployedAddresses The addresses that file declares, in file order.
/// @param records The record files declaring them, up to and including `path`.
/// @param released The released suites whose mechanism derives them.
error FrozenSnapshotsOutnumberReleases(string path, address[] deployedAddresses, uint256 records, uint256 released);
/// Thrown when a frozen code record — a parameterised contract's snapshot, which records code and
/// no deploy — names `DEPLOYED_ADDRESS` on any line outside a block comment, as `DEPLOYED_ADDRESS`, a per-network
/// `DEPLOYED_ADDRESS_<chainId>` or any other spelling. Line comments count, the SPDX header's among them, so a
/// licence identifier or copyright text naming `DEPLOYED_ADDRESS` is refused too.
/// @param path The record file.
error FrozenCodeRecordDeclaresDeployedAddress(string path);

/// Thrown when a frozen code record does not declare one of the constants a code record is, `BYTECODE_HASH`,
/// `CREATION_CODE` and `RUNTIME_CODE`, on a line starting with its declaration; declares one, on such a line, outside
/// the writer's format (`=` fourth of five space-separated tokens, or wrapped onto the next line at a four-space
/// indent); gives a `bytes` constant a value that is not one `hex"..."` literal of whole bytes, or the `bytes32`
/// constant a value that is not one `bytes32(0x...)` of `0x` and 64 hex digits; or holds a line break other than `\n`
/// that solc honours.
/// @param path The record file.
error FrozenCodeRecordUnreadable(string path);

/// Thrown when a frozen code record declares one of its constants more than
/// once, for the reason `FrozenSnapshotAmbiguous` gives.
/// @param path The record file.
error FrozenCodeRecordAmbiguous(string path);

/// Thrown when a frozen code record's runtime code does not hash to the code
/// hash recorded beside it.
/// @param path The record file.
/// @param storedBytecodeHash The hash the record declares.
/// @param runtimeCodeHash The hash of the runtime code it declares.
error FrozenCodeRecordInconsistent(string path, bytes32 storedBytecodeHash, bytes32 runtimeCodeHash);

/// @title RainDeployVerifySnapshotBase
/// @notice Every deploy-pin assertion that needs no network, for every suite a repo declares.
abstract contract RainDeployVerifySnapshotBase is RainDeployVerifyBase {
    /// Checks one suite against itself.
    /// @param suite The suite to check.
    function checkInternallyConsistent(DeployDeclaration memory d, DeploySuite memory suite) internal {
        DerivedDeploy memory derived = deriveDeployment(d, suite);

        address[] memory recorded = recordedAddresses(d, suite);
        for (uint256 i = 0; i < recorded.length; i++) {
            if (recorded[i] != derived.deployedAddresses[i]) {
                revert StoredAddressMismatch(suite.suite, recorded[i], derived.deployedAddresses[i]);
            }
        }

        if (suite.storedBytecodeHash != derived.bytecodeHash) {
            revert StoredCodeHashMismatch(suite.suite, suite.storedBytecodeHash, derived.bytecodeHash);
        }

        bytes32 runtimeCodeHash = keccak256(suite.storedRuntimeCode);
        if (suite.storedBytecodeHash != runtimeCodeHash) {
            revert StoredRuntimeCodeHashMismatch(suite.suite, suite.storedBytecodeHash, runtimeCodeHash);
        }

        checkDescribedByMeta(d, suite);
    }

    /// A suite carrying a described-by meta MUST name a `metaBoard()`, and every nonzero address its local deployment
    /// returns MUST answer `describedByMetaV1()` with the meta's hash.
    /// @param d The declaration.
    /// @param suite The suite to check.
    function checkDescribedByMeta(DeployDeclaration memory d, DeploySuite memory suite) internal {
        checkedMetaBoard(d, suite);
        if (suite.describedByMeta.length == 0) {
            return;
        }
        uint256 snapshotId = vm.snapshotState();
        address[] memory deployed = deployLocally(d, vm, suite);
        for (uint256 i = 0; i < deployed.length; i++) {
            if (deployed[i] != address(0)) {
                LibRainDeployDescribedByMeta.checkDescribes(suite.suite, deployed[i], suite.describedByMeta);
            }
        }
        if (!vm.revertToState(snapshotId)) {
            revert DerivationSnapshotRevertFailed(suite.suite, snapshotId);
        }
    }

    string constant BYTECODE_HASH_DECLARATION = "bytes32 constant BYTECODE_HASH =";
    string constant CREATION_CODE_DECLARATION = "bytes constant CREATION_CODE =";
    string constant RUNTIME_CODE_DECLARATION = "bytes constant RUNTIME_CODE =";

    /// Checks the frozen record against the released declaration. A record matches a release when each address it
    /// records is the release's derived address on that chain: on every one of its `networks` for a record of one
    /// address, on each recorded chain for a per-network record.
    /// @param paths The frozen record's files.
    /// @param released The declared released suites.
    function checkFrozenSnapshotsReleased(
        DeployDeclaration memory d,
        string[] memory paths,
        DeploySuite[] memory released
    ) internal view {
        uint256[][] memory releasedChainIds = new uint256[][](released.length);
        address[][] memory releasedAddresses = new address[][](released.length);
        for (uint256 j = 0; j < released.length; j++) {
            releasedChainIds[j] = suiteChainIds(released[j]);
            releasedAddresses[j] = deployedAddresses(d, released[j]);
        }

        bytes32[] memory recorded = new bytes32[](paths.length);
        for (uint256 i = 0; i < paths.length; i++) {
            (uint256[] memory chainIds, address[] memory addresses) =
                LibRainDeploySnapshot.recordedDeployedAddresses(vm, paths[i], vm.readFile(paths[i]));
            recorded[i] = keccak256(abi.encode(chainIds, addresses));

            uint256 declarations = 0;
            for (uint256 j = 0; j < released.length; j++) {
                if (recordMatches(chainIds, addresses, releasedChainIds[j], releasedAddresses[j])) {
                    declarations++;
                }
            }

            if (declarations == 0) {
                revert FrozenSnapshotNotReleased(paths[i]);
            }

            uint256 records = 1;
            for (uint256 k = 0; k < i; k++) {
                if (recorded[k] == recorded[i]) {
                    records++;
                }
            }

            if (records > declarations) {
                revert FrozenSnapshotsOutnumberReleases(paths[i], addresses, records, declarations);
            }
        }
    }

    /// @param chainIds The record's chain ids, none for one address on every network.
    /// @param addresses The record's addresses.
    /// @param releaseChainIds The release's chain ids.
    /// @param releaseAddresses The release's derived address on each of `releaseChainIds`.
    /// @return Whether the record is the release's.
    function recordMatches(
        uint256[] memory chainIds,
        address[] memory addresses,
        uint256[] memory releaseChainIds,
        address[] memory releaseAddresses
    ) internal pure returns (bool) {
        if (releaseChainIds.length == 0) {
            return false;
        }
        if (chainIds.length == 0) {
            for (uint256 m = 0; m < releaseAddresses.length; m++) {
                if (releaseAddresses[m] != addresses[0]) {
                    return false;
                }
            }
            return true;
        }
        for (uint256 k = 0; k < chainIds.length; k++) {
            bool found = false;
            for (uint256 m = 0; m < releaseChainIds.length; m++) {
                if (releaseChainIds[m] == chainIds[k]) {
                    found = releaseAddresses[m] == addresses[k];
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }
        return true;
    }

    /// The index of the first name in `codeRecordNames` that, plus `.sol`, is
    /// `path`'s file name.
    /// @param path A frozen record file.
    /// @param codeRecordNames The code records' names.
    /// @return The index, or `codeRecordNames.length` when none matches.
    function codeRecordIndex(string memory path, string[] memory codeRecordNames) internal pure returns (uint256) {
        string[] memory components = vm.split(path, "/");
        bytes32 file = keccak256(bytes(components[components.length - 1]));
        for (uint256 i = 0; i < codeRecordNames.length; i++) {
            if (file == keccak256(bytes(string.concat(codeRecordNames[i], ".sol")))) {
                return i;
            }
        }
        return codeRecordNames.length;
    }

    /// `paths` split into the deploy records and the code records, each in
    /// the order given. A path is a code record when its file name is one of
    /// `codeRecordNames` plus `.sol`.
    /// @param paths The frozen record's files.
    /// @param codeRecordNames The code records' names.
    /// @return The deploy records.
    /// @return The code records.
    function partitionFrozenRecords(string[] memory paths, string[] memory codeRecordNames)
        internal
        pure
        returns (string[] memory, string[] memory)
    {
        bool[] memory isCode = new bool[](paths.length);
        uint256 codeCount = 0;
        for (uint256 i = 0; i < paths.length; i++) {
            if (codeRecordIndex(paths[i], codeRecordNames) < codeRecordNames.length) {
                isCode[i] = true;
                codeCount++;
            }
        }
        string[] memory deployRecords = new string[](paths.length - codeCount);
        string[] memory codeRecords = new string[](codeCount);
        uint256 deployIndex = 0;
        uint256 codeIndex = 0;
        for (uint256 i = 0; i < paths.length; i++) {
            if (isCode[i]) {
                codeRecords[codeIndex] = paths[i];
                codeIndex++;
            } else {
                deployRecords[deployIndex] = paths[i];
                deployIndex++;
            }
        }
        return (deployRecords, codeRecords);
    }

    /// The line, among `lines`, that starts with `declaration`: exactly one.
    /// @param path The record file, for the error only.
    /// @param lines The record's lines, block comments removed.
    /// @param declaration The declaration text a line must start with.
    /// @return The line's index.
    function declarationLine(string memory path, string[] memory lines, string memory declaration)
        internal
        pure
        returns (uint256)
    {
        bool found = false;
        uint256 index = 0;
        for (uint256 i = 0; i < lines.length; i++) {
            if (vm.indexOf(lines[i], declaration) != 0) {
                continue;
            }
            if (found) {
                revert FrozenCodeRecordAmbiguous(path);
            }
            index = i;
            found = true;
        }
        if (!found) {
            revert FrozenCodeRecordUnreadable(path);
        }
        return index;
    }

    /// The value a code record's declaration on `lines[line]` gives, read by `LibRainDeploySnapshot.declarationValue`
    /// at the writer's `LibRainDeploySnapshot.WRAPPED_INDENT`. An unreadable declaration gives an empty token, which
    /// splits into one part, so `declaredBytes` and `declaredBytes32` refuse it at their opened-count check.
    /// @param lines The record's lines, block comments removed.
    /// @param line The declaration's line.
    /// @return The value's token, empty when not readable.
    function declaredValue(string[] memory lines, uint256 line) internal pure returns (string memory) {
        (, string memory value) =
            LibRainDeploySnapshot.declarationValue(vm, lines, line, LibRainDeploySnapshot.WRAPPED_INDENT);
        return value;
    }

    /// The value of a `bytes` constant a code record declares: its `hex"..."` literal, read by `declaredValue`, with
    /// nothing after the closing quote but the writer's `;`.
    /// @param path The record file, for the error only.
    /// @param lines The record's lines, block comments removed.
    /// @param line The declaration's line.
    /// @return The bytes.
    function declaredBytes(string memory path, string[] memory lines, uint256 line)
        internal
        pure
        returns (bytes memory)
    {
        string[] memory opened = vm.split(declaredValue(lines, line), "hex\"");
        if (opened.length != 2 || bytes(opened[0]).length != 0) {
            revert FrozenCodeRecordUnreadable(path);
        }
        string[] memory closed = vm.split(opened[1], "\"");
        if (closed.length != 2 || keccak256(bytes(closed[1])) != keccak256(";")) {
            revert FrozenCodeRecordUnreadable(path);
        }
        try vm.parseBytes(string.concat("0x", closed[0])) returns (bytes memory declared) {
            return declared;
        } catch {
            revert FrozenCodeRecordUnreadable(path);
        }
    }

    /// The value of the `bytes32` constant a code record declares: its `bytes32(0x...)` wrapper, read by
    /// `declaredValue`, holding `0x` and exactly 64 hex digits, with nothing after the closing parenthesis but the
    /// writer's `;`. `vm.parseBytes32` refuses any other digit count but reads digits without `0x`, so only the
    /// prefix is checked here.
    /// @param path The record file, for the error only.
    /// @param lines The record's lines, block comments removed.
    /// @param line The declaration's line.
    /// @return The bytes32.
    function declaredBytes32(string memory path, string[] memory lines, uint256 line) internal pure returns (bytes32) {
        string[] memory opened = vm.split(declaredValue(lines, line), "bytes32(");
        if (opened.length != 2 || bytes(opened[0]).length != 0) {
            revert FrozenCodeRecordUnreadable(path);
        }
        string[] memory closed = vm.split(opened[1], ")");
        if (closed.length != 2 || keccak256(bytes(closed[1])) != keccak256(";") || vm.indexOf(closed[0], "0x") != 0) {
            revert FrozenCodeRecordUnreadable(path);
        }
        try vm.parseBytes32(closed[0]) returns (bytes32 declared) {
            return declared;
        } catch {
            revert FrozenCodeRecordUnreadable(path);
        }
    }

    /// Checks one frozen code record against itself.
    /// @param path The record file, for the error only.
    /// @param record The record file's contents.
    function checkFrozenCodeRecord(string memory path, string memory record) internal pure {
        if (LibRainDeploySnapshot.hasForeignLineBreak(vm, record)) {
            revert FrozenCodeRecordUnreadable(path);
        }
        string[] memory lines = LibRainDeploySnapshot.splitRecordLines(vm, record);
        for (uint256 i = 0; i < lines.length; i++) {
            if (vm.contains(lines[i], LibRainDeploySnapshot.DEPLOYED_ADDRESS_NAME)) {
                revert FrozenCodeRecordDeclaresDeployedAddress(path);
            }
        }
        uint256 hashLine = declarationLine(path, lines, BYTECODE_HASH_DECLARATION);
        declaredBytes(path, lines, declarationLine(path, lines, CREATION_CODE_DECLARATION));
        uint256 runtimeLine = declarationLine(path, lines, RUNTIME_CODE_DECLARATION);

        bytes32 storedBytecodeHash = declaredBytes32(path, lines, hashLine);
        bytes32 runtimeCodeHash = keccak256(declaredBytes(path, lines, runtimeLine));
        if (runtimeCodeHash != storedBytecodeHash) {
            revert FrozenCodeRecordInconsistent(path, storedBytecodeHash, runtimeCodeHash);
        }
    }

    /// Every declared suite MUST be internally consistent.
    function testSnapshotInternallyConsistent() external {
        DeployDeclaration memory d = declaration();
        DeploySuite[] memory suites = allSuites(d);
        for (uint256 i = 0; i < suites.length; i++) {
            checkInternallyConsistent(d, suites[i]);
        }
    }

    /// Every declared mechanism MUST accept the declaration.
    function testMechanismDeclarationsResolve() external {
        DeployDeclaration memory d = declaration();
        for (uint256 i = 0; i < d.mechanisms.length; i++) {
            d.mechanisms[i].checkDeclaration(d);
        }
    }

    /// EVERY candidate MUST be a snapshot of the contract it NAMES, as this
    /// repo currently compiles it, not of some other contract that happens to
    /// be internally consistent.
    ///
    /// The check itself is `RainDeploySuitesBase.checkCandidatesAnchoredToSource`
    /// rather than anything here, because `RainDeployBroadcast` runs the same
    /// definition before it broadcasts. A second spelling on this side is a
    /// spelling the deploy does not run, which is exactly the state this test
    /// would otherwise be reporting green about.
    function testSnapshotMatchesSource() external view {
        checkCandidatesAnchoredToSource(declaration());
    }
}
