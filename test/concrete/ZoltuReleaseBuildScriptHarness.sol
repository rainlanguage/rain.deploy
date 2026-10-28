// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript} from "../../src/abstract/BuildScript.sol";
import {DeployMechanismHandler, DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {DeployDependency, LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {ChainDeploy} from "../../src/lib/LibRainDeployExtendedNetworks.sol";
import {MockDeployable} from "./MockDeployable.sol";

/// @title ZoltuReleaseBuildScriptHarness
/// @notice A build over one released Zoltu suite, `mock-deployable@0_0_1`, with settable extended networks.
contract ZoltuReleaseBuildScriptHarness is BuildScript {
    function mechanisms() internal pure virtual override returns (DeployMechanismHandler[] memory) {
        DeployMechanismHandler[] memory handlers = new DeployMechanismHandler[](1);
        handlers[0] = LibRainDeployZoltuMechanism.handler();
        return handlers;
    }

    string internal sRoot;

    ChainDeploy[] internal sExtendedNetworks;

    constructor(string memory root) {
        sRoot = root;
    }

    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = DeploySuite({
            networks: new string[](0),
            suite: "mock-deployable@0_0_1",
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode),
            storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
            storedRuntimeCode: type(MockDeployable).runtimeCode,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new DeployDependency[](0),
            mechanismData: ""
        });
        return suites;
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory) {
        return new DeployCandidate[](0);
    }

    /// @inheritdoc BuildScript
    function recordRoot() internal view override returns (string memory) {
        return sRoot;
    }

    /// @inheritdoc BuildScript
    function snapshotContractNames() internal pure override returns (string[] memory) {
        return new string[](0);
    }

    /// @inheritdoc BuildScript
    function regenerateSnapshots() internal override {}

    /// @inheritdoc BuildScript
    function regenerateLibs() internal override {}

    /// @param networks The extended networks every release declares.
    function setExtendedNetworks(ChainDeploy[] memory networks) external {
        delete sExtendedNetworks;
        for (uint256 i = 0; i < networks.length; i++) {
            sExtendedNetworks.push(networks[i]);
        }
    }

    /// @inheritdoc RainDeploySuitesBase
    function extendedNetworks(string memory) internal view override returns (ChainDeploy[] memory) {
        return sExtendedNetworks;
    }

    /// @inheritdoc RainDeploySuitesBase
    function extendedNetworksRoot() internal view override returns (string memory) {
        return sRoot;
    }

    function externalRegenerateExtendedNetworks() external {
        regenerateExtendedNetworks();
    }
}
