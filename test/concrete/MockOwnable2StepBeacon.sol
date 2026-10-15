// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin-contracts-5.7.0/access/Ownable2Step.sol";

/// @title MockOwnable2StepBeacon
/// @notice An upgradeable beacon whose ownership moves in two steps.
contract MockOwnable2StepBeacon is UpgradeableBeacon, Ownable2Step {
    constructor(address beaconImplementation, address initialOwner)
        UpgradeableBeacon(beaconImplementation, initialOwner)
    {}

    function transferOwnership(address newOwner) public override(Ownable, Ownable2Step) {
        super.transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal override(Ownable, Ownable2Step) {
        super._transferOwnership(newOwner);
    }
}
