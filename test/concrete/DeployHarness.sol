// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Deploy} from "../../script/Deploy.sol";

/// @title DeployHarness
/// @notice An external seam onto the one thing `script/Deploy.sol` could
/// override and does not, so a plain `Test` contract can read it without
/// inheriting `Script`.
///
/// A harness rather than a change to `Deploy`: the script's whole surface is
/// the `run()` it inherits, and widening an internal reader to `public` to be
/// testable would add an entry point to a contract that deploys real money.
contract DeployHarness is Deploy {
    /// @return The networks a broadcast from this script would go to.
    function externalDeployNetworks() external view returns (string[] memory) {
        return deployNetworks();
    }
}
