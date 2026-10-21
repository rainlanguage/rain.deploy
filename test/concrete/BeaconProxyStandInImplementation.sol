// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICLONEABLE_V2_SUCCESS} from "rain-factory-pr271-976cd62/src/interface/ICloneableV2.sol";

/// @title BeaconProxyStandInImplementation
/// @notice The source `BEACON_PROXY_STAND_IN_IMPLEMENTATION_RUNTIME_CODE` is compiled from.
contract BeaconProxyStandInImplementation {
    /// The init data is unnamed: any data initializes.
    /// @return The `ICloneableV2` success value.
    function initialize(bytes calldata) external pure returns (bytes32) {
        return ICLONEABLE_V2_SUCCESS;
    }
}
