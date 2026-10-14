// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

/// @title MockTimelockControllerGeneration
/// A `TimelockController` generation other than the recorded one: the same
/// constructor and role model, different creation and runtime code.
contract MockTimelockControllerGeneration is TimelockController {
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {}

    /// @notice Present only so the runtime code differs from the recorded one.
    function generation() external pure returns (uint256) {
        return 2;
    }
}
