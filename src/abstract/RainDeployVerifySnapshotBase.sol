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
/// code record is: `BYTECODE_HASH`, `CREATION_CODE` and `RUNTIME_CODE`.
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

    /// The index of the first of `codeRecordNames` that `path`'s file name is,
    /// plus `.sol`.
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

    /// The value of a `bytes` constant a code record declares: the `hex"..."`
    /// literal on the declaration's line, or on the line after it when the
    /// generator wrapped the declaration.
    /// @param path The record file, for the error only.
    /// @param lines The record's lines, block comments removed.
    /// @param line The declaration's line.
    /// @return The bytes.
    function declaredBytes(string memory path, string[] memory lines, uint256 line)
        internal
        pure
        returns (bytes memory)
    {
        string memory literal = lines[line];
        if (vm.indexOf(literal, "hex\"") == type(uint256).max) {
            if (line + 1 >= lines.length) {
                revert FrozenCodeRecordUnreadable(path);
            }
            literal = lines[line + 1];
        }
        string[] memory opened = vm.split(literal, "hex\"");
        if (opened.length != 2) {
            revert FrozenCodeRecordUnreadable(path);
        }
        string[] memory closed = vm.split(opened[1], "\"");
        return vm.parseBytes(string.concat("0x", closed[0]));
    }

    /// The value of the `BYTECODE_HASH` a code record declares: the
    /// `bytes32(0x...)` literal ending the declaration's line.
    /// @param lines The record's lines, block comments removed.
    /// @param line The declaration's line.
    /// @return The hash.
    function declaredBytecodeHash(string[] memory lines, uint256 line) internal pure returns (bytes32) {
        string[] memory tokens = vm.split(lines[line], " ");
        return vm.parseBytes32(
            vm.replace(vm.replace(vm.replace(tokens[tokens.length - 1], "bytes32(", ""), ")", ""), ";", "")
        );
    }

    /// Checks one frozen code record against itself.
    /// @param path The record file, for the error only.
    /// @param record The record file's contents.
    function checkFrozenCodeRecord(string memory path, string memory record) internal pure {
        string[] memory lines = vm.split(LibRainDeploySnapshot.withoutBlockComments(vm, record), "\n");
        for (uint256 i = 0; i < lines.length; i++) {
            if (
                vm.indexOf(lines[i], LibRainDeploySnapshot.DEPLOYED_ADDRESS_DECLARATION) == 0
                    || vm.indexOf(lines[i], LibRainDeploySnapshot.DEPLOYED_ADDRESS_CHAIN_DECLARATION_PREFIX) == 0
            ) {
                revert FrozenCodeRecordDeclaresDeployedAddress(path);
            }
        }
        uint256 hashLine = declarationLine(path, lines, BYTECODE_HASH_DECLARATION);
        declarationLine(path, lines, CREATION_CODE_DECLARATION);
        uint256 runtimeLine = declarationLine(path, lines, RUNTIME_CODE_DECLARATION);

        bytes32 storedBytecodeHash = declaredBytecodeHash(lines, hashLine);
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
