// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibConfigRegistry} from "../../src/lib/LibConfigRegistry.sol";

/// @title MockResolvedOwner
/// @notice A consumer in the shape the config registry is designed for: it
/// resolves a name exactly once, in its constructor, decodes the value as the
/// type it expects, and stores the answer in an immutable. It never reads the
/// registry again, so a later re-binding of that name cannot move what this
/// contract holds — which is the property that makes verifying a deployment
/// after deploying it meaningful.
contract MockResolvedOwner {
    /// The address the registry answered with at construction, and forever.
    address public immutable iOwner;

    /// @param name The name to resolve, once.
    constructor(bytes32 name) {
        // The moment the name was bound is discarded: this mock exists to show
        // that the VALUE cannot move afterwards, and a consumer that wanted to
        // refuse a freshly bound answer would read it here instead.
        (bytes memory value,) = LibConfigRegistry.resolve(name);
        iOwner = abi.decode(value, (address));
    }
}
