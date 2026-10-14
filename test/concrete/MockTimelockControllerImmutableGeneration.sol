// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

/// @title MockTimelockControllerImmutableGeneration
/// A generation whose runtime code embeds its constructor's `minDelay`, so its code hash depends on the arguments.
contract MockTimelockControllerImmutableGeneration is TimelockController {
    uint256 internal immutable iMinDelayAtBirth;

    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {
        iMinDelayAtBirth = minDelay;
    }

    function minDelayAtBirth() external view returns (uint256) {
        return iMinDelayAtBirth;
    }
}
