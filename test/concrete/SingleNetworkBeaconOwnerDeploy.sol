// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {DeployDeclaration} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {BeaconOwnerDeployScript} from "../abstract/BeaconOwnerDeployScript.sol";

/// @title SingleNetworkBeaconOwnerDeploy
/// @notice `BeaconOwnerDeployScript` on every Rain network with each dispatch narrowed to Arbitrum One.
contract SingleNetworkBeaconOwnerDeploy is BeaconOwnerDeployScript {
    function declaration() internal view override returns (DeployDeclaration memory) {
        return beaconOwnerDeclaration();
    }

    /// @inheritdoc RainDeployBroadcast
    function deployNetworks() internal pure override returns (string[] memory) {
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        return networks;
    }
}
