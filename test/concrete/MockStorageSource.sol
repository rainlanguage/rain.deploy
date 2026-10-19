// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockStorageSource
/// @notice One storage word, at slot 1, another contract's `initialize` reads or writes.
contract MockStorageSource {
    /// Holds slot 0, so a read of `sValue` is not at the zero slot.
    uint256 internal sPadding;

    /// The word read or written.
    uint256 public sValue;

    /// Sets `sValue`.
    /// @param value The new value.
    function set(uint256 value) external {
        sValue = value;
    }

    /// Sets `sPadding`, then reads `sValue`.
    /// @param value The new padding.
    /// @return The value.
    function setPaddingThenRead(uint256 value) external returns (uint256) {
        sPadding = value;
        return sValue;
    }
}
