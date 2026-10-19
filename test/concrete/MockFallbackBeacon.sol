// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";

/// @title MockFallbackBeacon
/// @notice An upgradeable beacon that answers any unknown call, such as `pendingOwner()`, with fixed bytes, returned
/// or reverted.
contract MockFallbackBeacon is UpgradeableBeacon {
    bytes internal sAnswer;
    bool internal sReverts;

    constructor(address beaconImplementation, address initialOwner, bytes memory answer, bool reverts)
        UpgradeableBeacon(beaconImplementation, initialOwner)
    {
        sAnswer = answer;
        sReverts = reverts;
    }

    fallback() external {
        bytes memory answer = sAnswer;
        if (sReverts) {
            assembly ("memory-safe") {
                revert(add(answer, 0x20), mload(answer))
            }
        }
        assembly ("memory-safe") {
            return(add(answer, 0x20), mload(answer))
        }
    }
}
