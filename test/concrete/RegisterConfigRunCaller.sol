// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RegisterConfig} from "../../script/RegisterConfig.sol";

/// @title RegisterConfigRunCaller
/// @notice Calls `run()` with its own address as `msg.sender`.
contract RegisterConfigRunCaller {
    /// @param script The script to run.
    /// @return The ids `run()` returns.
    function callRun(RegisterConfig script) external returns (uint256[] memory) {
        return script.run();
    }
}
