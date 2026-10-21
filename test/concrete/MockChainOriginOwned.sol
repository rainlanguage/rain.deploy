// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockChainOriginOwned
/// @notice Seats its deployment's origin as `owner()` when deployed under one chain id, and `0xB0B` under any other.
contract MockChainOriginOwned {
    /// The seated owner.
    address internal sOwner;

    /// @param chainId The chain id the origin is seated under.
    constructor(uint256 chainId) {
        sOwner = block.chainid == chainId ? tx.origin : address(0xB0B);
    }

    /// @return The seated owner.
    function owner() external view returns (address) {
        return sOwner;
    }
}
