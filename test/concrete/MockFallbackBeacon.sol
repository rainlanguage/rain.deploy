// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";

/// @title MockFallbackBeacon
/// @notice An upgradeable beacon that answers any unknown call, such as `pendingOwner()`, with fixed bytes, returned
/// or reverted.
contract MockFallbackBeacon is UpgradeableBeacon {
    /// The bytes every unknown call is answered with.
    bytes internal sAnswer;
    /// Whether the answer is reverted rather than returned.
    bool internal sReverts;

    /// @param beaconImplementation The initial implementation.
    /// @param initialOwner The initial owner.
    /// @param answer The bytes every unknown call is answered with.
    /// @param reverts Whether the answer is reverted rather than returned.
    constructor(address beaconImplementation, address initialOwner, bytes memory answer, bool reverts)
        UpgradeableBeacon(beaconImplementation, initialOwner)
    {
        sAnswer = answer;
        sReverts = reverts;
    }

    /// Answers any unknown call with `sAnswer`, reverted when `sReverts`.
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
