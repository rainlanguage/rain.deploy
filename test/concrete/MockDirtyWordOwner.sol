// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockDirtyWordOwner
/// @notice Answers the same read `MockResolvedOwner` answers, but with an
/// arbitrary 32-byte word rather than an address. Nothing on the wire
/// distinguishes the two until the upper 96 bits are looked at, and contracts
/// that answer a read with a word rather than an address are ordinary: a getter
/// whose declared return type is `bytes32` or `uint256`, or one written in
/// assembly, hands back whatever word it holds.
contract MockDirtyWordOwner {
    /// The word this contract answers every read with.
    bytes32 public immutable iWord;

    /// @param word The word to answer with.
    constructor(bytes32 word) {
        iWord = word;
    }

    /// The selector `MockResolvedOwner` answers, returning a raw word.
    /// @return The word.
    function iOwner() external view returns (bytes32) {
        return iWord;
    }
}
