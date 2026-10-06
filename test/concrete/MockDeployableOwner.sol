// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

// The address `MockDeployableOwner.iOwner` answers on every chain.
address constant MOCK_DEPLOYABLE_OWNER = address(0xf00d);

/// @title MockDeployableOwner
/// @notice A deployment target that answers the resolved-address read, so a
/// deploy and the check over it can be one test. Takes no constructor arguments
/// and holds no immutables, so its creation code — and with it the address the
/// Zoltu factory derives and the code hash it leaves behind — are fixed, which
/// is what `deployToNetworks` requires of anything it carries to a network.
/// `MockResolvedOwner` is not deployable that way: it resolves through an
/// address registry that is on none of the forked chains.
contract MockDeployableOwner {
    /// The address this deployment holds, the same on every chain.
    /// @return The owner.
    function iOwner() external pure returns (address) {
        return MOCK_DEPLOYABLE_OWNER;
    }

    /// The chain this is called on, as an address, so a check that never
    /// advances past the first fork cannot be told from one that does — and the
    /// failure names the chain it actually read.
    /// @return The chain id of the fork this is called on.
    function iChainOwner() external view returns (address) {
        // Chain ids are orders of magnitude below `type(uint160).max`, so the
        // cast keeps every bit of every id this repo forks.
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(block.chainid));
    }
}
