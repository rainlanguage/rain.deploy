// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IConfigRegistryV4} from "../../src/interface/IConfigRegistryV4.sol";

/// @title LibConfigRegistryRead
/// @notice Each part of `getV4`, for tests that assert on one at a time.
library LibConfigRegistryRead {
    /// The value part of `getV4`.
    /// @param registry The registry to read.
    /// @param authority The authority to read under.
    /// @param nameHash The hash of the name to read.
    /// @return The value `authority` bound the name to.
    function getValue(IConfigRegistryV4 registry, address authority, bytes32 nameHash)
        internal
        view
        returns (bytes memory)
    {
        (bytes memory value,,) = registry.getV4(authority, nameHash);
        return value;
    }

    /// The moment part of `getV4`.
    /// @param registry The registry to read.
    /// @param authority The authority to read under.
    /// @param nameHash The hash of the name to read.
    /// @return The moment `authority` most recently bound the name.
    function getMoment(IConfigRegistryV4 registry, address authority, bytes32 nameHash)
        internal
        view
        returns (uint256)
    {
        (, uint256 registeredAt,) = registry.getV4(authority, nameHash);
        return registeredAt;
    }

    /// The type part of `getV4`.
    /// @param registry The registry to read.
    /// @param authority The authority to read under.
    /// @param nameHash The hash of the name to read.
    /// @return The hash of the type `authority` most recently bound the name as.
    function getValueTypeHash(IConfigRegistryV4 registry, address authority, bytes32 nameHash)
        internal
        view
        returns (bytes32)
    {
        (,, bytes32 valueTypeHash) = registry.getV4(authority, nameHash);
        return valueTypeHash;
    }
}
