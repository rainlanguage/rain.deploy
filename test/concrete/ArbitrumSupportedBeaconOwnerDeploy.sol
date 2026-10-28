// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {BeaconOwnerDeployScript} from "../abstract/BeaconOwnerDeployScript.sol";

/// @title ArbitrumSupportedBeaconOwnerDeploy
/// @notice A `BeaconOwnerDeployScript` supporting Arbitrum One alone.
contract ArbitrumSupportedBeaconOwnerDeploy is BeaconOwnerDeployScript {
    function declaration() internal view override returns (DeployDeclaration memory) {
        DeployDeclaration memory declared = beaconOwnerDeclaration();
        declared.networks = new string[](1);
        declared.networks[0] = LibRainDeploy.ARBITRUM_ONE;
        return declared;
    }
}
