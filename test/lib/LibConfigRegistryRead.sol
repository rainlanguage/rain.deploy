// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IConfigRegistryV3} from "../../src/interface/IConfigRegistryV3.sol";

/// @title LibConfigRegistryRead
/// @notice Each half of `getV3`, for tests that assert on one at a time.
library LibConfigRegistryRead {
    /// The value half of `getV3`.
    /// @param registry The registry to read.
    /// @param authority The authority to read under.
    /// @param name The name to read.
    /// @return The value `authority` bound `name` to.
    function getValue(IConfigRegistryV3 registry, address authority, bytes32 name)
        internal
        view
        returns (bytes memory)
    {
        (bytes memory value,) = registry.getV3(authority, name);
        return value;
    }

    /// The moment half of `getV3`.
    /// @param registry The registry to read.
    /// @param authority The authority to read under.
    /// @param name The name to read.
    /// @return The moment `authority` most recently bound `name`.
    function getMoment(IConfigRegistryV3 registry, address authority, bytes32 name) internal view returns (uint256) {
        (, uint256 registeredAt) = registry.getV3(authority, name);
        return registeredAt;
    }
}
