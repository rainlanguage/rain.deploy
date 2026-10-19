// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DerivedDeploy, RainDeployVerifyBase} from "./RainDeployVerifyBase.sol";
import {DeploySuite} from "./RainDeploySuitesBase.sol";
import {LibRainDeployMechanism} from "../lib/LibRainDeployMechanism.sol";
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
/// no deploy — declares a deployed address, either `DEPLOYED_ADDRESS` or a per-network
/// `DEPLOYED_ADDRESS_<chainId>`.
/// @param path The record file.
error FrozenCodeRecordDeclaresDeployedAddress(string path);

/// Thrown when a frozen code record does not declare one of the constants a
/// code record is: `BYTECODE_HASH`, `CREATION_CODE` and `RUNTIME_CODE`; declares one outside the
/// writer's format (`=` fourth of five space-separated tokens, or wrapped onto the next line at a
/// four-space indent); gives a `bytes` constant a value that is not one `hex"..."` literal; or holds
/// a line break other than `\n` that solc honours.
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
    function checkInternallyConsistent(DeploySuite memory suite) internal {
        DerivedDeploy memory derived = deriveDeployment(suite);

        address[] memory recorded = LibRainDeployMechanism.recordedAddresses(suite);
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
    }

    string constant BYTECODE_HASH_DECLARATION = "bytes32 constant BYTECODE_HASH =";
    string constant CREATION_CODE_DECLARATION = "bytes constant CREATION_CODE =";
    string constant RUNTIME_CODE_DECLARATION = "bytes constant RUNTIME_CODE =";

    /// Checks the frozen record against the released declaration.
    /// @param paths The frozen record's files.
    /// @param released The declared released suites.
    function checkFrozenSnapshotsReleased(string[] memory paths, DeploySuite[] memory released) internal view {
        bytes32[] memory releasedIdentities = new bytes32[](released.length);
        for (uint256 j = 0; j < released.length; j++) {
            releasedIdentities[j] = keccak256(
                abi.encode(
                    LibRainDeployMechanism.addressChainIds(released[j]),
                    LibRainDeployMechanism.deployedAddresses(released[j])
                )
            );
        }

        bytes32[] memory recorded = new bytes32[](paths.length);
        for (uint256 i = 0; i < paths.length; i++) {
            (uint256[] memory chainIds, address[] memory addresses) =
                LibRainDeploySnapshot.recordedDeployedAddresses(vm, paths[i], vm.readFile(paths[i]));
            recorded[i] = keccak256(abi.encode(chainIds, addresses));

            uint256 declarations = 0;
            for (uint256 j = 0; j < released.length; j++) {
                if (recorded[i] == releasedIdentities[j]) {
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

    /// The frozen code records' names: the contracts whose code a release
    /// freezes without deploying them as suites — parameterised contracts,
    /// recorded as `BYTECODE_HASH`, `CREATION_CODE` and `RUNTIME_CODE` and no
    /// deploy address. A frozen file with one of these names is checked as a
    /// code record by `checkFrozenCodeRecord`; every other frozen file is a
    /// deploy record and goes through `checkFrozenSnapshotsReleased`.
    ///
    /// Matched by name, unlike a deploy record, because a code record has
    /// nothing else to match on: no address to derive, and bytes that
    /// legitimately differ between releases — a compiler-profile or dependency
    /// change regenerates them, and the frozen copy is what keeps the
    /// generation each release shipped. The name cannot silence anything: a
    /// deploy record named here is refused for its address, and a code record
    /// not named here reaches the deploy check and is refused as unreadable.
    ///
    /// Empty by default: a repo that freezes only deploy suites names none.
    /// @return The names, e.g. `TimelockController`.
    function frozenCodeRecordNames() internal view virtual returns (string[] memory) {
        return new string[](0);
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
            string[] memory components = vm.split(paths[i], "/");
            bytes32 file = keccak256(bytes(components[components.length - 1]));
            for (uint256 j = 0; j < codeRecordNames.length; j++) {
                if (file == keccak256(bytes(string.concat(codeRecordNames[j], ".sol")))) {
                    isCode[i] = true;
                    codeCount++;
                    break;
                }
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
    /// at the writer's `LibRainDeploySnapshot.WRAPPED_INDENT`.
    /// @param path The record file, for the error only.
    /// @param lines The record's lines, block comments removed.
    /// @param line The declaration's line.
    /// @return The value's token.
    function declaredValue(string memory path, string[] memory lines, uint256 line)
        internal
        pure
        returns (string memory)
    {
        (bool readable, string memory value) =
            LibRainDeploySnapshot.declarationValue(vm, lines, line, LibRainDeploySnapshot.WRAPPED_INDENT);
        if (!readable) {
            revert FrozenCodeRecordUnreadable(path);
        }
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
        string[] memory opened = vm.split(declaredValue(path, lines, line), "hex\"");
        if (opened.length != 2 || bytes(opened[0]).length != 0) {
            revert FrozenCodeRecordUnreadable(path);
        }
        string[] memory closed = vm.split(opened[1], "\"");
        if (closed.length != 2 || keccak256(bytes(closed[1])) != keccak256(";")) {
            revert FrozenCodeRecordUnreadable(path);
        }
        return vm.parseBytes(string.concat("0x", closed[0]));
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
            if (
                vm.indexOf(lines[i], LibRainDeploySnapshot.DEPLOYED_ADDRESS_DECLARATION) == 0
                    || vm.indexOf(lines[i], LibRainDeploySnapshot.DEPLOYED_ADDRESS_CHAIN_DECLARATION_PREFIX) == 0
            ) {
                revert FrozenCodeRecordDeclaresDeployedAddress(path);
            }
        }
        uint256 hashLine = declarationLine(path, lines, BYTECODE_HASH_DECLARATION);
        declaredBytes(path, lines, declarationLine(path, lines, CREATION_CODE_DECLARATION));
        uint256 runtimeLine = declarationLine(path, lines, RUNTIME_CODE_DECLARATION);

        string memory literal = declaredValue(path, lines, hashLine);
        bytes32 storedBytecodeHash =
            vm.parseBytes32(vm.replace(vm.replace(vm.replace(literal, "bytes32(", ""), ")", ""), ";", ""));
        bytes32 runtimeCodeHash = keccak256(declaredBytes(path, lines, runtimeLine));
        if (runtimeCodeHash != storedBytecodeHash) {
            revert FrozenCodeRecordInconsistent(path, storedBytecodeHash, runtimeCodeHash);
        }
    }

    /// Every declared suite MUST be internally consistent.
    function testSnapshotInternallyConsistent() external {
        DeploySuite[] memory suites = allSuites();
        for (uint256 i = 0; i < suites.length; i++) {
            checkInternallyConsistent(suites[i]);
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
        checkCandidatesAnchoredToSource();
    }
}
