// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {IERC5313} from "@openzeppelin-contracts-5.7.0/interfaces/IERC5313.sol";
import {LibRainDeploy} from "./LibRainDeploy.sol";

/// The CURRENT state an upgradeable beacon MUST hold on one network.
struct DeployBeacon {
    address beacon;
    bytes32 beaconCodeHash;
    address implementation;
    bytes32 implementationCodeHash;
    address owner;
}

library LibRainDeployBeacon {
    /// The selected fork MUST hold `beacon` at its declared code, implementation
    /// and owner, and the implementation at its declared code.
    function checkBeacon(string memory network, DeployBeacon memory beacon) internal view {
        LibRainDeploy.checkDeployedCode(network, beacon.beacon, beacon.beaconCodeHash);
        bytes[] memory reads = new bytes[](2);
        reads[0] = abi.encodeCall(IBeacon.implementation, ());
        reads[1] = abi.encodeCall(IERC5313.owner, ());
        address[] memory expected = new address[](2);
        expected[0] = beacon.implementation;
        expected[1] = beacon.owner;
        LibRainDeploy.checkResolvedAddresses(network, beacon.beacon, reads, expected);
        LibRainDeploy.checkDeployedCode(network, beacon.implementation, beacon.implementationCodeHash);
    }

    function checkBeacons(string memory network, DeployBeacon[] memory beacons) internal view {
        for (uint256 i = 0; i < beacons.length; i++) {
            checkBeacon(network, beacons[i]);
        }
    }
}
