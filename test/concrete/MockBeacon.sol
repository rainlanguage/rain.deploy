// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {IUpgradeableBeacon} from "../../src/interface/IUpgradeableBeacon.sol";

/// @title MockBeacon
/// @notice An owned beacon. With `iDrift` set, `upgradeTo` lands one address
/// past the one asked for, so a caller can see the implementation move.
contract MockBeacon is IUpgradeableBeacon {
    /// Only the owner may upgrade.
    error NotOwner(address caller);

    /// The owner.
    address public immutable iOwner;

    /// Whether `upgradeTo` misses its target.
    bool public immutable iDrift;

    /// How many times `upgradeTo` ran.
    uint256 public sUpgrades;

    /// @inheritdoc IUpgradeableBeacon
    address public implementation;

    /// @param owner The owner.
    /// @param initialImplementation The starting implementation.
    /// @param drift Whether `upgradeTo` misses its target.
    constructor(address owner, address initialImplementation, bool drift) {
        iOwner = owner;
        implementation = initialImplementation;
        iDrift = drift;
    }

    /// @inheritdoc IUpgradeableBeacon
    function upgradeTo(address newImplementation) external {
        if (msg.sender != iOwner) revert NotOwner(msg.sender);
        sUpgrades++;
        implementation = iDrift ? address(uint160(newImplementation) + 1) : newImplementation;
    }
}
