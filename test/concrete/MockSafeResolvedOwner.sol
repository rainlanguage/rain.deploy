// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibAddressRegistry} from "../../src/lib/LibAddressRegistry.sol";

/// @title MockSafeResolvedOwner
/// @notice Resolves a name exactly once, in its constructor, and reverts the
/// deploy if the binding has not stood for `minAge`.
contract MockSafeResolvedOwner {
    /// The address the registry answered with at construction, and forever.
    address public immutable iOwner;

    /// @param name The name to resolve, once.
    /// @param minAge The least time the binding must have stood for this
    /// contract to accept it.
    constructor(bytes32 name, uint256 minAge) {
        iOwner = LibAddressRegistry.resolveSafe(name, minAge);
    }
}
