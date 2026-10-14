// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// The state an upgradeable beacon MUST hold on one network. The expected
/// implementation and owner are the CURRENT ones: an upgrade or an ownership
/// migration changes this declaration, and verification is red until it is
/// applied.
/// @param beacon Where the beacon is on the network.
/// @param beaconCodeHash The pinned beacon build its code MUST hash to.
/// @param implementation What `implementation()` MUST answer.
/// @param implementationCodeHash What the implementation's code MUST hash to.
/// @param owner What `owner()` MUST answer.
struct DeployBeacon {
    address beacon;
    bytes32 beaconCodeHash;
    address implementation;
    bytes32 implementationCodeHash;
    address owner;
}
