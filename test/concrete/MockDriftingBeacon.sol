// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";

/// @title MockDriftingBeacon
/// @notice An OpenZeppelin `UpgradeableBeacon` whose `upgradeTo` points it at
/// itself instead of the implementation asked for, so a caller can see the
/// implementation move. Ownership is enforced as usual.
contract MockDriftingBeacon is UpgradeableBeacon {
    /// @param implementation_ The starting implementation.
    /// @param initialOwner The owner.
    constructor(address implementation_, address initialOwner) UpgradeableBeacon(implementation_, initialOwner) {}

    /// Upgrade to this beacon's own address, whatever is asked for.
    function upgradeTo(address) public override {
        super.upgradeTo(address(this));
    }
}
