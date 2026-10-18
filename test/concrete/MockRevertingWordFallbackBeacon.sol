// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";

/// @title MockRevertingWordFallbackBeacon
/// @notice An upgradeable beacon that reverts any unknown call, such as `pendingOwner()`, with one nonzero word.
contract MockRevertingWordFallbackBeacon is UpgradeableBeacon {
    constructor(address beaconImplementation, address initialOwner)
        UpgradeableBeacon(beaconImplementation, initialOwner)
    {}

    fallback() external {
        assembly ("memory-safe") {
            mstore(0, 0xDEAD)
            revert(0, 0x20)
        }
    }
}
