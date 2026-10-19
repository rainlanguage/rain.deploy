// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibResolvedReadFixture
/// @notice What the resolved-address and resolved-value tests of `LibRainDeploy`
/// share.
library LibResolvedReadFixture {
    /// Chain id of Arbitrum One.
    uint256 internal constant ARBITRUM_ONE_CHAIN_ID = 42161;

    /// The read the `iOwner` mocks answer.
    /// @return The single-element read call list.
    function ownerReadCalls() internal pure returns (bytes[] memory) {
        bytes[] memory readCalls = new bytes[](1);
        readCalls[0] = abi.encodeWithSignature("iOwner()");
        return readCalls;
    }

    /// Fork ids no fork has, so selecting one is itself an error. That is what
    /// makes "refused before anything is selected" observable from outside.
    /// @param length How many of them to make.
    /// @return The list.
    function unselectableForkIds(uint256 length) internal pure returns (uint256[] memory) {
        uint256[] memory forkIds = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            forkIds[i] = type(uint256).max;
        }
        return forkIds;
    }
}
