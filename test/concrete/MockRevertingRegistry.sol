// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockRevertingRegistry
/// Stands at the registry address and reverts every call with the revert data
/// it was constructed with, so a reader of the registry can be shown a revert
/// the real registry never raises.
contract MockRevertingRegistry {
    /// The revert data every call is answered with.
    bytes internal sRevertData;

    constructor(bytes memory revertData) {
        sRevertData = revertData;
    }

    fallback() external {
        bytes memory revertData = sRevertData;
        assembly ("memory-safe") {
            revert(add(revertData, 0x20), mload(revertData))
        }
    }
}
