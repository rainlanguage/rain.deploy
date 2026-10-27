// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibConfigRegistry} from "../../src/lib/LibConfigRegistry.sol";

/// @title MockSafeResolvedOwner
/// @notice Resolves a name exactly once, in its constructor, and reverts the
/// deploy if the binding has not stood for longer than `minAge`.
contract MockSafeResolvedOwner {
    /// The address the registry answered with at construction, and forever.
    address public immutable iOwner;

    /// @param authority The authority to resolve the name under.
    /// @param nameHash The hash of the name to resolve, once, as an `address`.
    /// @param minAge The binding must have stood for longer than this for
    /// this contract to accept it.
    // The authority is read through, never stored, and nothing is bound under
    // a zero one, so the read refuses it as unbound.
    //forge-lint: disable-next-line(missing-zero-check)
    constructor(address authority, bytes32 nameHash, uint256 minAge) {
        iOwner = abi.decode(LibConfigRegistry.resolveSafe(authority, nameHash, keccak256("address"), minAge), (address));
    }
}
