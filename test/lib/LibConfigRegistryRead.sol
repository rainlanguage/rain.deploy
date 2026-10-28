// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IConfigRegistryV4} from "../../src/interface/IConfigRegistryV4.sol";

/// @title LibConfigRegistryRead
/// @notice Each half of `getV4`, for tests that assert on one at a time.
library LibConfigRegistryRead {
    /// The value half of `getV4`.
    /// @param registry The registry to read.
    /// @param authority The authority to read under.
    /// @param name The name to read.
    /// @return The value `authority` bound `name` to.
    function getValue(IConfigRegistryV4 registry, address authority, bytes32 name)
        internal
        view
        returns (bytes memory)
    {
        (bytes memory value,,) = registry.getV4(authority, name);
        return value;
    }

    /// The moment half of `getV4`.
    /// @param registry The registry to read.
    /// @param authority The authority to read under.
    /// @param name The name to read.
    /// @return The moment `authority` most recently bound `name`.
    function getMoment(IConfigRegistryV4 registry, address authority, bytes32 name) internal view returns (uint256) {
        (, uint256 registeredAt,) = registry.getV4(authority, name);
        return registeredAt;
    }
}
