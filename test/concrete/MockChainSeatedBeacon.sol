// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockChainSeatedBeacon
/// @notice A beacon whose constructor seats one owner on one chain and another everywhere else, as a deployment that
/// picks its owner from `block.chainid` does.
contract MockChainSeatedBeacon {
    /// The implementation.
    address internal sImplementation;
    /// The owner seated on the deploying chain.
    address internal sOwner;

    /// @param beaconImplementation The implementation.
    /// @param ownerOnChain The owner seated when deployed on `chainId`.
    /// @param ownerElsewhere The owner seated when deployed on any other chain.
    /// @param chainId The chain `ownerOnChain` is seated on.
    // Answered back verbatim, authorising nothing.
    //forge-lint: disable-next-line(missing-zero-check)
    constructor(address beaconImplementation, address ownerOnChain, address ownerElsewhere, uint256 chainId) {
        sImplementation = beaconImplementation;
        sOwner = block.chainid == chainId ? ownerOnChain : ownerElsewhere;
    }

    /// @return The implementation.
    function implementation() external view returns (address) {
        return sImplementation;
    }

    /// @return The owner seated on the deploying chain.
    function owner() external view returns (address) {
        return sOwner;
    }
}
