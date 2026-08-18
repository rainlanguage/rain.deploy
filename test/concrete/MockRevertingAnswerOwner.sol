// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockRevertingAnswerOwner
/// @notice Answers the read `MockResolvedOwner` answers by REVERTING with
/// exactly the bytes a successful answer would have carried.
///
/// Nothing about the returned bytes distinguishes it from a real answer — same
/// length, same word, same address — so only whether the call SUCCEEDED
/// separates the two. A revert carrying an ABI-encoded address is ordinary: a
/// custom error whose one argument is an address is that shape, and so is any
/// `require` that bubbles a callee's return data.
contract MockRevertingAnswerOwner {
    /// The bytes this contract reverts every read with.
    bytes internal sAnswer;

    /// @param answer The bytes to revert with.
    constructor(bytes memory answer) {
        sAnswer = answer;
    }

    /// The selector `MockResolvedOwner` answers, reverting with `sAnswer` as
    /// the whole of the revert data.
    function iOwner() external view {
        bytes memory answer = sAnswer;
        assembly ("memory-safe") {
            revert(add(answer, 0x20), mload(answer))
        }
    }
}
