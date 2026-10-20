// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockRevertingReadBeacon
/// @notice A beacon that answers one of `owner()` and `implementation()` and reverts the other with data.
contract MockRevertingReadBeacon {
    /// The revert of the read that does not answer.
    error Unanswered();

    /// The implementation `implementation()` answers.
    address internal sImplementation;
    /// The owner `owner()` answers.
    address internal sOwner;
    /// Whether `owner()` reverts, else `implementation()` does.
    bool internal sOwnerReverts;

    /// @param beaconImplementation The implementation.
    /// @param initialOwner The owner.
    /// @param ownerReverts Whether `owner()` reverts, else `implementation()` does.
    //forge-lint: disable-next-line(missing-zero-check)
    constructor(address beaconImplementation, address initialOwner, bool ownerReverts) {
        sImplementation = beaconImplementation;
        sOwner = initialOwner;
        sOwnerReverts = ownerReverts;
    }

    /// @return The owner, unless `sOwnerReverts`.
    function owner() external view returns (address) {
        if (sOwnerReverts) {
            revert Unanswered();
        }
        return sOwner;
    }

    /// @return The implementation, when `sOwnerReverts`.
    function implementation() external view returns (address) {
        if (!sOwnerReverts) {
            revert Unanswered();
        }
        return sImplementation;
    }
}
