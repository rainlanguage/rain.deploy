// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IConfigRegistryV5} from "../../src/interface/IConfigRegistryV5.sol";

/// @title LibConfigRegistryRead
/// @notice Each half of `getV5`, for tests that assert on one at a time.
library LibConfigRegistryRead {
    /// The value half of `getV5`.
    /// @param registry The registry to read.
    /// @param authority The authority to read under.
    /// @param name The name to read.
    /// @return The value `authority` bound `name` to.
    function getValue(IConfigRegistryV5 registry, address authority, bytes32 name)
        internal
        view
        returns (bytes memory)
    {
        (bytes memory value,,) = registry.getV5(authority, name);
        return value;
    }

    /// The moment half of `getV5`.
    /// @param registry The registry to read.
    /// @param authority The authority to read under.
    /// @param name The name to read.
    /// @return The moment `authority` most recently bound `name`.
    function getMoment(IConfigRegistryV5 registry, address authority, bytes32 name) internal view returns (uint256) {
        (, uint256 registeredAt,) = registry.getV5(authority, name);
        return registeredAt;
    }
}
