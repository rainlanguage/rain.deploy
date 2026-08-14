// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibAddressRegistry} from "../../src/lib/LibAddressRegistry.sol";

/// @title MockResolvedOwner
/// @notice A consumer in the shape the address registry is designed for: it
/// resolves a name exactly once, in its constructor, and stores the answer in an
/// immutable. It never reads the registry again, so a later re-binding of that
/// name cannot move what this contract holds — which is the property that makes
/// verifying a deployment after deploying it meaningful.
contract MockResolvedOwner {
    /// The address the registry answered with at construction, and forever.
    address public immutable iOwner;

    /// @param name The name to resolve, once.
    constructor(bytes32 name) {
        iOwner = LibAddressRegistry.resolve(name);
    }
}
