// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ChainBeacon, DeployBeacon} from "../../src/lib/LibRainDeployBeacon.sol";

/// @title LibBeaconDeclarations
/// @notice Builds a test's `beacons()` declaration in storage.
library LibBeaconDeclarations {
    /// Appends `beacon` on `chainId` to `declarations`.
    /// @param declarations The declarations.
    /// @param chainId The beacon's network.
    /// @param beacon The beacon.
    function declare(ChainBeacon[] storage declarations, uint256 chainId, DeployBeacon memory beacon) internal {
        ChainBeacon storage chainBeacon = declarations.push();
        chainBeacon.chainId = chainId;
        DeployBeacon storage stored = chainBeacon.beacon;
        stored.beaconSuite = beacon.beaconSuite;
        stored.beacon = beacon.beacon;
        stored.beaconCodeHash = beacon.beaconCodeHash;
        stored.initial = beacon.initial;
        for (uint256 i = 0; i < beacon.transitions.length; i++) {
            stored.transitions.push(beacon.transitions[i]);
        }
    }
}
