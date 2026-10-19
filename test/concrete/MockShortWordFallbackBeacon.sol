// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";

/// @title MockShortWordFallbackBeacon
/// @notice An upgradeable beacon that answers any unknown call, such as `pendingOwner()`, with one byte short of a
/// word.
contract MockShortWordFallbackBeacon is UpgradeableBeacon {
    constructor(address beaconImplementation, address initialOwner)
        UpgradeableBeacon(beaconImplementation, initialOwner)
    {}

    fallback() external {
        assembly ("memory-safe") {
            mstore(0, 0)
            return(0, 0x1f)
        }
    }
}
