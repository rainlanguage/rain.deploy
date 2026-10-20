// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IConfigRegistryV1} from "../../src/interface/IConfigRegistryV1.sol";

/// @title LibConfigRegistryRead
/// @notice Each half of `getV1`, for tests that assert on one at a time.
library LibConfigRegistryRead {
    /// The value half of `getV1`.
    /// @param registry The registry to read.
    /// @param name The name to read.
    /// @return The value bound to `name`.
    function getValue(IConfigRegistryV1 registry, bytes32 name) internal view returns (bytes memory) {
        (bytes memory value,) = registry.getV1(name);
        return value;
    }

    /// The moment half of `getV1`.
    /// @param registry The registry to read.
    /// @param name The name to read.
    /// @return The moment `name` was most recently bound.
    function getMoment(IConfigRegistryV1 registry, bytes32 name) internal view returns (uint256) {
        (, uint256 registeredAt) = registry.getV1(name);
        return registeredAt;
    }
}
