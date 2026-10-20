// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeployDependency, LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {MockDeployableOwner} from "../concrete/MockDeployableOwner.sol";

/// @title LibResolvedReadFixture
/// @notice What the resolved-address and resolved-value tests of `LibRainDeploy`
/// share.
library LibResolvedReadFixture {
    /// Chain id of Arbitrum One.
    uint256 internal constant ARBITRUM_ONE_CHAIN_ID = 42161;

    /// Chain id of Base.
    uint256 internal constant BASE_CHAIN_ID = 8453;

    /// The read the `iOwner` mocks answer.
    /// @return The single-element read call list.
    function ownerReadCalls() internal pure returns (bytes[] memory) {
        bytes[] memory readCalls = new bytes[](1);
        readCalls[0] = abi.encodeWithSignature("iOwner()");
        return readCalls;
    }

    /// The calldata for reading the chain `MockDeployableOwner` is read on.
    /// @return The single-element read call list.
    function chainOwnerReadCalls() internal pure returns (bytes[] memory) {
        bytes[] memory readCalls = new bytes[](1);
        readCalls[0] = abi.encodeWithSignature("iChainOwner()");
        return readCalls;
    }

    /// The address `MockDeployableOwner.iChainOwner` answers on a given chain.
    /// @param chainId The chain id.
    /// @return The chain id as an address.
    function chainOwner(uint256 chainId) internal pure returns (address) {
        // The low 160 bits are the whole of any chain id this repo forks.
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(chainId));
    }

    /// Deploys `MockDeployableOwner` to each network through `deployToNetworks`:
    /// a first-time deployment of a target that answers the resolved-address
    /// read. Nothing is made persistent, so it exists on the returned forks and
    /// nowhere else, which is the state a deploy script is in when it returns.
    /// @param vm The Vm instance to fork and broadcast with.
    /// @param networks The network names to deploy to.
    /// @param deployer The account that deploys.
    /// @return The deterministic address it landed at.
    /// @return The fork each network was deployed on.
    function deployMockDeployableOwner(Vm vm, string[] memory networks, address deployer)
        internal
        returns (address, uint256[] memory)
    {
        return LibRainDeploy.deployToNetworks(
            vm,
            networks,
            deployer,
            type(MockDeployableOwner).creationCode,
            "test/concrete/MockDeployableOwner.sol:MockDeployableOwner",
            LibRainDeploy.zoltuAddress(type(MockDeployableOwner).creationCode),
            keccak256(type(MockDeployableOwner).runtimeCode),
            new DeployDependency[](0)
        );
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
