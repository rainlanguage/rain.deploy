// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript, GeneratedContract, RetiredContract} from "../../src/abstract/BuildScript.sol";
import {DeployCandidate, DeployDeclaration} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";

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

    /// @param candidates `abi.encode` of the candidates `declaration` adds.
    /// @param generated `abi.encode` of what `generatedContracts` returns.
    /// @param retired `abi.encode` of what `retiredContracts` returns.
    function declare(bytes memory candidates, bytes memory generated, bytes memory retired) external {
        sCandidates = candidates;
        sGenerated = generated;
        sRetired = retired;
    }

    function declaration() internal view override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        LibRainDeployDeclaration.addCandidates(d, abi.decode(sCandidates, (DeployCandidate[])));
        return d;
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
        return snapshotContractNames(checkedGeneratedContracts(declaration()));
    }

    function externalRegenerateLibs() external {
        DeployDeclaration memory d = declaration();
        regenerateLibs(d, checkedGeneratedContracts(d));
    }
}
