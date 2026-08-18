// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockChainDependentOwner
/// @notice Answers the read `MockResolvedOwner` answers with one address on one
/// chain and another everywhere else.
///
/// This is the deployment the network matrix exists to find: one contract, at
/// one deterministic address, holding a different resolved value on a chain
/// nobody looked at. A deployment that answers the same thing everywhere cannot
/// tell a matrix that forked every network from one that forked the first.
contract MockChainDependentOwner {
    /// The address answered on `iChainId`.
    address public immutable iOwnerOnChain;

    /// The address answered on every other chain.
    address public immutable iOwnerElsewhere;

    /// The chain `iOwnerOnChain` is answered on.
    uint256 public immutable iChainId;

    /// @param ownerOnChain The address to answer on `chainId`.
    /// @param ownerElsewhere The address to answer everywhere else.
    /// @param chainId The chain `ownerOnChain` is answered on.
    constructor(address ownerOnChain, address ownerElsewhere, uint256 chainId) {
        iOwnerOnChain = ownerOnChain;
        iOwnerElsewhere = ownerElsewhere;
        iChainId = chainId;
    }

    /// The selector `MockResolvedOwner` answers.
    /// @return The address for the chain this is called on.
    function iOwner() external view returns (address) {
        return block.chainid == iChainId ? iOwnerOnChain : iOwnerElsewhere;
    }
}
