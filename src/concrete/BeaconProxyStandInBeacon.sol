// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @dev The implementation the stand-in beacon serves during a local deploy.
address constant BEACON_PROXY_STAND_IN_IMPLEMENTATION =
    address(uint160(uint256(keccak256("rain.deploy.beaconproxy.standin.implementation"))));

/// @title BeaconProxyStandInBeacon
/// @notice Etched over a beacon proxy's beacon during a local deploy, so the proxy initializes
/// without the beacon's real implementation, which may read storage that is empty locally.
contract BeaconProxyStandInBeacon {
    /// @return `BEACON_PROXY_STAND_IN_IMPLEMENTATION`.
    function implementation() external pure returns (address) {
        return BEACON_PROXY_STAND_IN_IMPLEMENTATION;
    }
}
