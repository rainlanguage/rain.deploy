// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

address constant MOCK_DEPLOYABLE_OWNER = address(0xf00d);

/// @title MockDeployableOwner
/// @notice A deployment target that answers the resolved-address read, so a
/// deploy and the check over it can be one test. No constructor arguments and
/// no immutables, so its creation code is fixed. `MockResolvedOwner` is not
/// deployable that way: it resolves through a registry on none of the forks.
contract MockDeployableOwner {
    /// @return The owner, the same on every chain.
    function iOwner() external pure returns (address) {
        return MOCK_DEPLOYABLE_OWNER;
    }

    /// The chain as an address, so a check that never advances past the first
    /// fork cannot be told from one that does.
    /// @return The chain id of the fork this is called on.
    function iChainOwner() external view returns (address) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(block.chainid));
    }
}
