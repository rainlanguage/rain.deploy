// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript} from "../../src/abstract/BuildScript.sol";
import {RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployMechanism} from "../../src/lib/LibRainDeployMechanism.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {
    PER_NETWORK_CLONE_RECORD_CONTRACT,
    PerNetworkCloneDeploys,
    perNetworkCloneChainIds,
    perNetworkCloneRelease
} from "../abstract/PerNetworkCloneDeploys.sol";

/// @title PerNetworkCloneBuildScriptHarness
/// @notice A per-network clone deploy repo's build script over a fixture
/// record root: it regenerates the `per-network-clone` release's rolling
/// snapshot through the suite writer, and the released-suites lib from the
/// record with a per-network clone template.
contract PerNetworkCloneBuildScriptHarness is PerNetworkCloneDeploys, BuildScript {
    string internal sRoot;

    string internal sLibDir;

    /// @inheritdoc PerNetworkCloneDeploys
    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return PerNetworkCloneDeploys.supportedNetworks();
    }

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
        names[0] = PER_NETWORK_CLONE_RECORD_CONTRACT;
        return names;
    }

    /// @inheritdoc BuildScript
    function regenerateSnapshots() internal override {
        LibRainDeploySnapshot.writeSnapshot(
            vm,
            recordRoot(),
            LibRainDeploySnapshot.CANDIDATE,
            PER_NETWORK_CLONE_RECORD_CONTRACT,
            LibRainDeployMechanism.cloneCandidate(perNetworkCloneRelease(), perNetworkCloneChainIds()).snapshot
        );
    }

    /// @inheritdoc BuildScript
    function regenerateLibs() internal override {
        LibRainDeploySnapshot.writeReleasedSuitesLib(
            vm, sLibDir, recordRoot(), PER_NETWORK_CLONE_RECORD_CONTRACT, candidateSuites()[0].snapshot
        );
    }

    /// @return The rolling snapshot's path.
    function rollingPath() external view returns (string memory) {
        return LibRainDeploySnapshot.pathForSnapshot(
            recordRoot(), LibRainDeploySnapshot.CANDIDATE, PER_NETWORK_CLONE_RECORD_CONTRACT
        );
    }

    /// @return The path `cutRelease()` freezes the rolling snapshot to.
    function frozenPath() external view returns (string memory) {
        return LibRainDeploySnapshot.pathForSnapshot(
            recordRoot(), LibRainDeploySnapshot.deployTag(vm), PER_NETWORK_CLONE_RECORD_CONTRACT
        );
    }

    /// @return The released-suites lib's path.
    function releasedLibPath() external view returns (string memory) {
        return LibRainDeploySnapshot.pathForLib(
            sLibDir, LibRainDeploySnapshot.releasedLibraryName(PER_NETWORK_CLONE_RECORD_CONTRACT)
        );
    }
}
