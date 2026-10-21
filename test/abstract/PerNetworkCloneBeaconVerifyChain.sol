// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../src/abstract/RainDeployVerifyChain.sol";
import {BeaconState, ChainBeacon} from "../../src/lib/LibRainDeployBeacon.sol";
import {PER_NETWORK_CLONE_POLYGON_CHAIN_ID, PerNetworkCloneDeploys} from "./PerNetworkCloneDeploys.sol";

/// @title PerNetworkCloneBeaconVerifyChain
/// @notice The chain group over `PerNetworkCloneDeploys` with a beacon on Polygon at the release's Polygon clone.
abstract contract PerNetworkCloneBeaconVerifyChain is PerNetworkCloneDeploys, RainDeployVerifyChain {
    /// The beacon's owner.
    address constant OWNER = address(0xB0B);

    /// The beacon declared by address when `sBeaconBySuite` is false.
    address internal sBeacon;

    /// Whether the beacon is declared by the release's suite key rather than at `sBeacon`.
    bool internal sBeaconBySuite;

    /// @inheritdoc RainDeploySuitesBase
    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return PerNetworkCloneDeploys.supportedNetworks();
    }

    /// @inheritdoc RainDeploySuitesBase
    function beacons() internal view override returns (ChainBeacon[] memory) {
        ChainBeacon[] memory chainBeacons = new ChainBeacon[](1);
        chainBeacons[0].chainId = PER_NETWORK_CLONE_POLYGON_CHAIN_ID;
        if (sBeaconBySuite) {
            chainBeacons[0].beacon.beaconSuite = "per-network-clone@0_0_1";
        } else {
            chainBeacons[0].beacon.beacon = sBeacon;
            chainBeacons[0].beacon.beaconCodeHash = sBeacon.codehash;
        }
        chainBeacons[0].beacon.initial = BeaconState({implementation: "per-network-clone@0_0_1", owner: OWNER});
        return chainBeacons;
    }
}
