// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {MockStorageSource} from "./MockStorageSource.sol";

/// @title MockStorageSourceFactory
/// @notice Creates a `MockStorageSource` for its caller, as a dependency that predates a clone's deploy.
contract MockStorageSourceFactory {
    /// Creates a source.
    /// @return The new source.
    function create() external returns (MockStorageSource) {
        return new MockStorageSource();
    }
}
