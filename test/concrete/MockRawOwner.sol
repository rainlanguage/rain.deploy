// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockRawOwner
/// @notice Answers `owner()` with an arbitrary byte string, verbatim, as the whole of the return data.
contract MockRawOwner {
    /// The bytes `owner()` answers with.
    bytes internal sAnswer;

    /// @param answer The bytes to answer with.
    constructor(bytes memory answer) {
        sAnswer = answer;
    }

    /// Returns `sAnswer` as the whole of the return data.
    function owner() external view {
        bytes memory answer = sAnswer;
        assembly ("memory-safe") {
            return(add(answer, 0x20), mload(answer))
        }
    }
}
