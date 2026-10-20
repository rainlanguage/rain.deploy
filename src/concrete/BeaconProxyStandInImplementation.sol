// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICLONEABLE_V2_SUCCESS} from "rain-factory-pr271-0477c05/src/interface/ICloneableV2.sol";

/// @title BeaconProxyStandInImplementation
/// @notice What the stand-in beacon serves during a local deploy: initializes to success with any
/// data and reads no storage.
contract BeaconProxyStandInImplementation {
    /// @return The `ICloneableV2` success value.
    function initialize(bytes calldata) external pure returns (bytes32) {
        return ICLONEABLE_V2_SUCCESS;
    }
}
