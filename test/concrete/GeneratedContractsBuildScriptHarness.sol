// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript, GeneratedContract, RetiredContract} from "../../src/abstract/BuildScript.sol";
import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";

/// @title GeneratedContractsBuildScriptHarness
/// @notice A `BuildScript` whose candidates, generated contracts and retired
/// contracts are set by the test, abi-encoded because storage cannot hold the
/// memory arrays the hooks return.
contract GeneratedContractsBuildScriptHarness is BuildScript {
    string internal sRoot;

    string internal sLibDir;

    bytes internal sCandidates;

    bytes internal sGenerated;

    bytes internal sRetired;

    /// @param root The record root, also the config root.
    /// @param libDirectory The directory the libs are written into.
    constructor(string memory root, string memory libDirectory) {
        sRoot = root;
        sLibDir = libDirectory;
        sCandidates = abi.encode(new DeployCandidate[](0));
        sGenerated = abi.encode(new GeneratedContract[](0));
        sRetired = abi.encode(new RetiredContract[](0));
    }

    /// @param candidates `abi.encode` of what `candidateSuites` declares.
    /// @param generated `abi.encode` of what `generatedContracts` returns.
    /// @param retired `abi.encode` of what `retiredContracts` returns.
    function declare(bytes memory candidates, bytes memory generated, bytes memory retired) external {
        sCandidates = candidates;
        sGenerated = generated;
        sRetired = retired;
    }

    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        return new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal view override returns (DeployCandidate[] memory) {
        return abi.decode(sCandidates, (DeployCandidate[]));
    }

    /// @inheritdoc BuildScript
    function generatedContracts() internal view override returns (GeneratedContract[] memory) {
        return abi.decode(sGenerated, (GeneratedContract[]));
    }

    /// @inheritdoc BuildScript
    function retiredContracts() internal view override returns (RetiredContract[] memory) {
        return abi.decode(sRetired, (RetiredContract[]));
    }

    /// @inheritdoc BuildScript
    function regenerateSnapshots() internal override {}

    /// @inheritdoc BuildScript
    function recordRoot() internal view override returns (string memory) {
        return sRoot;
    }

    /// @inheritdoc BuildScript
    function configRoot() internal view override returns (string memory) {
        return sRoot;
    }

    /// @inheritdoc BuildScript
    function libDir() internal view override returns (string memory) {
        return sLibDir;
    }

    function externalSnapshotContractNames() external view returns (string[] memory) {
        return snapshotContractNames();
    }

    function externalRegenerateLibs() external {
        regenerateLibs();
    }
}
