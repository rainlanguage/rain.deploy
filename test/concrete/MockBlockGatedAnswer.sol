// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockBlockGatedAnswer
/// @notice A read whose answer changes at a chosen block: from `sFrom` on it
/// returns `sAnswer`, and before it REVERTS with exactly those bytes. Only
/// whether the call succeeded separates the two sides of the transition.
contract MockBlockGatedAnswer {
    /// The first block the read returns at.
    uint256 internal sFrom;
    /// The bytes the read returns, or reverts with.
    bytes internal sAnswer;

    /// @param from The first block the read returns at.
    /// @param answer The bytes the read returns or reverts with.
    constructor(uint256 from, bytes memory answer) {
        sFrom = from;
        sAnswer = answer;
    }

    /// Returns `sAnswer` from `sFrom` on, reverts with it before.
    function read() external view {
        bytes memory answer = sAnswer;
        bool returns_ = block.number >= sFrom;
        assembly ("memory-safe") {
            switch returns_
            case 0 { revert(add(answer, 0x20), mload(answer)) }
            default { return(add(answer, 0x20), mload(answer)) }
        }
    }
}
