// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockResolvedBytes
/// @notice A deployment holding a resolved `bytes` value.
contract MockResolvedBytes {
    /// The resolved value.
    bytes internal sData;

    /// @param value The value to hold.
    constructor(bytes memory value) {
        sData = value;
    }

    /// @return The value.
    function data() external view returns (bytes memory) {
        return sData;
    }
}
