// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DeploySuite} from "../abstract/RainDeploySuitesBase.sol";

/// @title LibDeploySuiteConcat
/// @notice Flattens arrays of `DeploySuite` into one array, preserving order.
library LibDeploySuiteConcat {
    /// @param suites The arrays to flatten.
    /// @return Every suite of `suites`, outer then inner order.
    function concat(DeploySuite[][] memory suites) internal pure returns (DeploySuite[] memory) {
        uint256 total = 0;
        for (uint256 i = 0; i < suites.length; i++) {
            total += suites[i].length;
        }

        DeploySuite[] memory flat = new DeploySuite[](total);
        uint256 offset = 0;
        for (uint256 i = 0; i < suites.length; i++) {
            for (uint256 j = 0; j < suites[i].length; j++) {
                flat[offset + j] = suites[i][j];
            }
            offset += suites[i].length;
        }
        return flat;
    }
}
