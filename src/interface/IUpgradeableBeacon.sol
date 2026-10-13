// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title IUpgradeableBeacon
/// @notice The OpenZeppelin `UpgradeableBeacon` surface a Safe that owns a
/// beacon acts on.
interface IUpgradeableBeacon {
    /// @notice The implementation the beacon points at.
    /// @return The implementation address.
    function implementation() external view returns (address);

    /// @notice Owner only: point the beacon at `newImplementation`.
    /// @param newImplementation The implementation to point at.
    function upgradeTo(address newImplementation) external;
}
