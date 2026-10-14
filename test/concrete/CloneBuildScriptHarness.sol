// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript} from "../../src/abstract/BuildScript.sol";
import {LibRainDeployMechanism} from "../../src/lib/LibRainDeployMechanism.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {
    EXAMPLE_CLONE_RECORD_CONTRACT,
    ExampleCloneDeploys,
    exampleCloneRelease
} from "../abstract/ExampleCloneDeploys.sol";

/// @title CloneBuildScriptHarness
/// @notice A clone deploy repo's build script over a fixture record root: it
/// regenerates the `example-clone` release's rolling snapshot through the
/// suite writer, and the released-suites lib from the record with a clone
/// template.
contract CloneBuildScriptHarness is ExampleCloneDeploys, BuildScript {
    string internal sRoot;

    string internal sLibDir;

    /// @param root The record root to regenerate and cut into.
    /// @param libDir The directory the released-suites lib is written to.
    constructor(string memory root, string memory libDir) {
        sRoot = root;
        sLibDir = libDir;
    }

    /// @inheritdoc BuildScript
    function recordRoot() internal view override returns (string memory) {
        return sRoot;
    }

    /// @inheritdoc BuildScript
    function snapshotContractNames() internal pure override returns (string[] memory) {
        string[] memory names = new string[](1);
        names[0] = EXAMPLE_CLONE_RECORD_CONTRACT;
        return names;
    }

    /// @inheritdoc BuildScript
    function regenerateSnapshots() internal override {
        LibRainDeploySnapshot.writeSnapshot(
            vm,
            recordRoot(),
            LibRainDeploySnapshot.CANDIDATE,
            EXAMPLE_CLONE_RECORD_CONTRACT,
            LibRainDeployMechanism.cloneCandidate(exampleCloneRelease(), new uint256[](0)).snapshot
        );
    }

    /// @inheritdoc BuildScript
    function regenerateLibs() internal override {
        LibRainDeploySnapshot.writeReleasedSuitesLib(
            vm, sLibDir, recordRoot(), EXAMPLE_CLONE_RECORD_CONTRACT, candidateSuites()[0].snapshot
        );
    }

    /// @return The rolling snapshot's path.
    function rollingPath() external view returns (string memory) {
        return LibRainDeploySnapshot.pathForSnapshot(
            recordRoot(), LibRainDeploySnapshot.CANDIDATE, EXAMPLE_CLONE_RECORD_CONTRACT
        );
    }

    /// @return The path `cutRelease()` freezes the rolling snapshot to.
    function frozenPath() external view returns (string memory) {
        return LibRainDeploySnapshot.pathForSnapshot(
            recordRoot(), LibRainDeploySnapshot.deployTag(vm), EXAMPLE_CLONE_RECORD_CONTRACT
        );
    }

    /// @return The released-suites lib's path.
    function releasedLibPath() external view returns (string memory) {
        return LibRainDeploySnapshot.pathForLib(
            sLibDir, LibRainDeploySnapshot.releasedLibraryName(EXAMPLE_CLONE_RECORD_CONTRACT)
        );
    }
}
