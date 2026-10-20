// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockChainGatedCall
/// @notice Reads `owner()` from a contract its suite does not declare, under one chain id only, so it deploys only
/// where that contract exists.
contract MockChainGatedCall {
    /// @param chainId The chain id the read is made under.
    /// @param target The contract read.
    constructor(uint256 chainId, address target) {
        if (block.chainid == chainId) {
            MockChainGatedCall(target).owner();
        }
    }

    /// @return Nobody.
    function owner() external pure returns (address) {
        return address(0);
    }
}
