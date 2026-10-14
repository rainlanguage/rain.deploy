// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDependency, LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {CloneNetwork, CloneNetworks, CloneTarget, LibRainDeployClone} from "../../../src/lib/LibRainDeployClone.sol";
import {
    exampleCloneDependencies,
    exampleCloneFactory,
    exampleCloneImplementation
} from "../../abstract/ExampleCloneDeploys.sol";

/// @title LibRainDeployClonePerNetworkTest
/// Tests for `LibRainDeployClone`'s per-network checks and entry resolution.
contract LibRainDeployClonePerNetworkTest is Test {
    /// A salt with bytes set across the whole word.
    bytes32 constant TEST_SALT = 0x1122334455667788990011223344556677889900112233445566778899001122;

    /// A per-network clone over the given factory and implementation, with one
    /// entry per chain id, each with its own init data.
    /// @param factory The factory.
    /// @param implementation The implementation.
    /// @param chainIds The chain id of each entry.
    /// @return The per-network clone, each entry's address derived.
    function cloneNetworks(address factory, address implementation, uint256[] memory chainIds)
        internal
        pure
        returns (CloneNetworks memory)
    {
        CloneNetworks memory clones = CloneNetworks({
            factory: factory,
            implementation: implementation,
            salt: TEST_SALT,
            networks: new CloneNetwork[](chainIds.length)
        });
        for (uint256 i = 0; i < chainIds.length; i++) {
            clones.networks[i] =
                CloneNetwork({chainId: chainIds[i], data: abi.encode(chainIds[i]), deployedAddress: address(0)});
            clones.networks[i].deployedAddress =
                LibRainDeployClone.cloneDeployedAddress(LibRainDeployClone.cloneNetworkTarget(clones, i));
        }
        return clones;
    }

    /// Two chain ids, as a list.
    /// @param a The first.
    /// @param b The second.
    /// @return The list.
    function twoChainIds(uint256 a, uint256 b) internal pure returns (uint256[] memory) {
        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = a;
        chainIds[1] = b;
        return chainIds;
    }

    /// The example clone across Arbitrum One and Polygon.
    /// @return The per-network clone.
    function exampleCloneNetworks() internal pure returns (CloneNetworks memory) {
        return cloneNetworks(exampleCloneFactory(), exampleCloneImplementation(), twoChainIds(42161, 137));
    }

    /// @param clones The per-network clone.
    /// @param dependencies The dependencies declared beside it.
    function externalCheckCloneNetworks(CloneNetworks memory clones, DeployDependency[] memory dependencies)
        external
        pure
    {
        LibRainDeployClone.checkCloneNetworks(clones, dependencies);
    }

    /// @param clones The per-network clone.
    /// @param chainId The chain id to find.
    /// @return The entry's index.
    function externalCloneNetworkIndex(CloneNetworks memory clones, uint256 chainId) external pure returns (uint256) {
        return LibRainDeployClone.cloneNetworkIndex(clones, chainId);
    }

    /// Whether any fork exists. Fork ids are handed out from zero.
    /// @return Whether fork 0 can be selected.
    function anyForkExists() internal returns (bool) {
        (bool forked,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(0)));
        return forked;
    }

    /// A well-formed per-network clone passes.
    function testCheckCloneNetworksAcceptsDistinctChainIds() external view {
        this.externalCheckCloneNetworks(exampleCloneNetworks(), exampleCloneDependencies());
    }

    /// A per-network clone naming no network is refused: every check over its
    /// networks would pass having checked nothing.
    function testCheckCloneNetworksRefusesNoNetworks() external {
        CloneNetworks memory clones =
            cloneNetworks(exampleCloneFactory(), exampleCloneImplementation(), new uint256[](0));
        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.NoCloneNetworks.selector));
        this.externalCheckCloneNetworks(clones, exampleCloneDependencies());
    }

    /// A chain id named twice is refused, naming it — including when the
    /// repeat is not next to the first, and when it is the LAST entry, so a
    /// check that compared only neighbours or stopped short of the end passes
    /// it.
    function testCheckCloneNetworksRefusesADuplicateChainId() external {
        uint256[] memory chainIds = new uint256[](3);
        chainIds[0] = 137;
        chainIds[1] = 42161;
        chainIds[2] = 137;
        CloneNetworks memory clones = cloneNetworks(exampleCloneFactory(), exampleCloneImplementation(), chainIds);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.DuplicateCloneNetwork.selector, 137));
        this.externalCheckCloneNetworks(clones, exampleCloneDependencies());
    }

    /// The factory and the implementation MUST be declared dependencies, as
    /// for a uniform clone.
    function testCheckCloneNetworksRefusesAnUndeclaredDependency() external {
        DeployDependency[] memory onlyFactory = new DeployDependency[](1);
        onlyFactory[0] = exampleCloneDependencies()[0];
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeployClone.CloneDependencyUndeclared.selector, exampleCloneImplementation())
        );
        this.externalCheckCloneNetworks(exampleCloneNetworks(), onlyFactory);
    }

    /// Every entry is found by its chain id, not only the first, and a chain id
    /// with no entry is refused rather than resolved to some entry.
    function testCloneNetworkIndexFindsEveryEntryAndRefusesAnUndeclaredOne() external {
        CloneNetworks memory clones = exampleCloneNetworks();
        assertEq(this.externalCloneNetworkIndex(clones, 42161), 0);
        assertEq(this.externalCloneNetworkIndex(clones, 137), 1);

        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.CloneNetworkUndeclared.selector, 8453));
        this.externalCloneNetworkIndex(clones, 8453);
    }

    /// An entry's target is the shared factory, implementation and salt with
    /// THAT entry's data, and two entries with different data are at
    /// different addresses.
    function testCloneNetworkTargetIsTheSharedCloneWithTheEntrysData() external pure {
        CloneNetworks memory clones = exampleCloneNetworks();
        for (uint256 i = 0; i < clones.networks.length; i++) {
            CloneTarget memory target = LibRainDeployClone.cloneNetworkTarget(clones, i);
            assertEq(target.factory, clones.factory);
            assertEq(target.implementation, clones.implementation);
            assertEq(target.salt, clones.salt);
            assertEq(target.data, clones.networks[i].data);
        }
        assertNotEq(clones.networks[0].deployedAddress, clones.networks[1].deployedAddress);
    }
}
