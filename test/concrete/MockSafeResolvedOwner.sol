// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibAddressRegistry} from "../../src/lib/LibAddressRegistry.sol";

/// @title MockSafeResolvedOwner
/// @notice `MockResolvedOwner` with the freshness check the registry exists to
/// make possible: it resolves a name exactly once, in its constructor, and
/// refuses to come into existence at all if the binding has not stood for
/// `minAge`.
///
/// This is the shape the library's guidance describes, and the reason it is a
/// separate mock rather than a parameter on the other one is that the two
/// demonstrate different things. `MockResolvedOwner` shows that a resolved
/// address cannot move afterwards. This shows that a deployment can decline to
/// snapshot an address that moved just before it looked — the deploy reverts,
/// so there is no contract holding a value nobody vetted.
///
/// `minAge` is a constructor argument rather than a constant because the
/// threshold belongs to the consumer, and a mock that hardcoded one would be
/// asserting a choice this repo does not make for anybody.
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
