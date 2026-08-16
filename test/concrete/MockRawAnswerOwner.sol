// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockRawAnswerOwner
/// @notice Answers the read `MockResolvedOwner` answers, with an arbitrary byte
/// string rather than with one ABI-encoded address. A call answers with as many
/// bytes as the callee likes, and contracts whose answer is not exactly one word
/// are ordinary: a getter declared `returns (address, address)`, or returning a
/// dynamic type, answers with more than a word, and one that returns in assembly
/// answers with whatever it holds — the Zoltu factory itself answers with the
/// twenty raw bytes of an address and nothing else.
///
/// Assembly, and no declared return type, because the LENGTH is the whole point:
/// every Solidity return type ABI-encodes to a whole number of words, so nothing
/// declared can answer with twenty bytes.
contract MockRawAnswerOwner {
    /// The bytes this contract answers every read with, verbatim.
    bytes internal sAnswer;

    /// @param answer The bytes to answer with.
    constructor(bytes memory answer) {
        sAnswer = answer;
    }

    /// The selector `MockResolvedOwner` answers, returning `sAnswer` as the
    /// whole of the return data.
    function iOwner() external view {
        bytes memory answer = sAnswer;
        assembly ("memory-safe") {
            return(add(answer, 0x20), mload(answer))
        }
    }
}
