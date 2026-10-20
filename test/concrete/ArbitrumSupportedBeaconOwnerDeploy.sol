// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {BeaconOwnerDeploy} from "./BeaconOwnerDeploy.sol";

/// @title ArbitrumSupportedBeaconOwnerDeploy
/// @notice A `BeaconOwnerDeploy` supporting Arbitrum One alone.
contract ArbitrumSupportedBeaconOwnerDeploy is BeaconOwnerDeploy {
    /// @inheritdoc RainDeploySuitesBase
    function supportedNetworks() internal pure override returns (string[] memory) {
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        return networks;
    }
}
