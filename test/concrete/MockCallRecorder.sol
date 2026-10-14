// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockCallRecorder
/// @notice Records every call it receives: caller, value and calldata.
contract MockCallRecorder {
    /// One received call.
    struct Call {
        address caller;
        uint256 value;
        bytes data;
    }

    /// Every call received, in order.
    Call[] internal sCalls;

    /// Reverts with this when called with the calldata `"revert"`.
    error Refused();

    fallback() external payable {
        if (keccak256(msg.data) == keccak256("revert")) revert Refused();
        sCalls.push(Call({caller: msg.sender, value: msg.value, data: msg.data}));
    }

    /// Records a call with empty calldata like any other.
    receive() external payable {
        sCalls.push(Call({caller: msg.sender, value: msg.value, data: ""}));
    }

    /// @return How many calls were received.
    function callCount() external view returns (uint256) {
        return sCalls.length;
    }

    /// @param i The call's index.
    /// @return The `i`th call received.
    function calls(uint256 i) external view returns (Call memory) {
        return sCalls[i];
    }
}
