// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {BuildScript} from "../../src/abstract/BuildScript.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ChainDeploy} from "../../src/lib/LibRainDeployExtendedNetworks.sol";
import {MockCreate2DeploySuites} from "../abstract/MockCreate2DeploySuites.sol";

contract MockCreate2BuildScriptHarness is MockCreate2DeploySuites, BuildScript {
    function recordRoot() internal view override returns (string memory) {
        return sMockExtendedNetworksRoot;
    }

    function snapshotContractNames() internal pure override returns (string[] memory) {
        return new string[](0);
    }

    function regenerateSnapshots() internal override {}

    function regenerateLibs() internal override {}

    function externalRegenerateExtendedNetworks() external {
        regenerateExtendedNetworks();
    }

    function externalExtendedNetworksPaths() external view returns (string[] memory) {
        return extendedNetworksPaths();
    }
}
