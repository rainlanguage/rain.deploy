// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

/// @title MockTimelockControllerAdminGeneration
/// A generation whose constructor leaves the role model: the first proposer also holds `DEFAULT_ADMIN_ROLE`.
contract MockTimelockControllerAdminGeneration is TimelockController {
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, proposers[0]);
    }
}
