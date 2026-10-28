// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration} from "../../src/abstract/RainDeploySuitesBase.sol";
import {BeaconOwnerDeployScript} from "../abstract/BeaconOwnerDeployScript.sol";

/// @title BeaconOwnerDeploy
/// @notice `BeaconOwnerDeployScript` on every Rain network.
contract BeaconOwnerDeploy is BeaconOwnerDeployScript {
    function declaration() internal view override returns (DeployDeclaration memory) {
        return beaconOwnerDeclaration();
    }
}
