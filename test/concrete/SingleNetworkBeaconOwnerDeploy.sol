// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {BeaconOwnerDeploy} from "./BeaconOwnerDeploy.sol";

/// @title SingleNetworkBeaconOwnerDeploy
/// @notice `BeaconOwnerDeploy` with each dispatch narrowed to Arbitrum One.
contract SingleNetworkBeaconOwnerDeploy is BeaconOwnerDeploy {
    /// @inheritdoc RainDeployBroadcast
    function deployNetworks() internal pure override returns (string[] memory) {
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        return networks;
    }
}
