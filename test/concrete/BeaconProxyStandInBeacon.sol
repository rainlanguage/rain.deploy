// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BEACON_PROXY_STAND_IN_IMPLEMENTATION} from "../../src/lib/LibRainDeployBeaconProxy.sol";

/// @title BeaconProxyStandInBeacon
/// @notice The source `BEACON_PROXY_STAND_IN_BEACON_RUNTIME_CODE` is compiled from.
contract BeaconProxyStandInBeacon {
    /// @return `BEACON_PROXY_STAND_IN_IMPLEMENTATION`.
    function implementation() external pure returns (address) {
        return BEACON_PROXY_STAND_IN_IMPLEMENTATION;
    }
}
