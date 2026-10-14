// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../../../src/lib/LibRainDeployMechanism.sol";
import {PerNetworkCloneDeploys} from "../../abstract/PerNetworkCloneDeploys.sol";

/// @title RainDeployVerifyChainClonePerNetworkTest
/// @notice The chain matrix over a per-network clone release, which is at a different address on
/// each of its two networks.
contract RainDeployVerifyChainClonePerNetworkTest is PerNetworkCloneDeploys, RainDeployVerifyChain {
    /// @inheritdoc PerNetworkCloneDeploys
    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return PerNetworkCloneDeploys.supportedNetworks();
    }

    /// Puts the release's dependencies, and its clone at its address for each network, on every
    /// fork.
    function setUp() external {
        DeploySuite memory release = releasedSuites()[0];
        for (uint256 i = 0; i < release.dependencies.length; i++) {
            vm.etch(release.dependencies[i].deployedAddress, release.dependencies[i].runtimeCode);
            vm.makePersistent(release.dependencies[i].deployedAddress);
        }
        address[] memory addresses = LibRainDeployMechanism.deployedAddresses(release);
        for (uint256 i = 0; i < addresses.length; i++) {
            vm.etch(addresses[i], release.storedRuntimeCode);
            vm.makePersistent(addresses[i]);
        }
    }

    /// Without Polygon's clone, the matrix refuses on Polygon at Polygon's address, having passed
    /// Arbitrum One at Arbitrum One's.
    function testPerNetworkCloneMissingOnPolygonIsRefusedAtPolygonsAddress() external {
        DeploySuite memory release = releasedSuites()[0];
        address polygonAddress = LibRainDeployMechanism.deployedAddress(release, 137);
        vm.etch(polygonAddress, hex"");

        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.POLYGON, polygonAddress)
        );
        this.testSuitesLiveOnEverySupportedNetwork();
    }

    /// Without Arbitrum One's clone, the matrix refuses on Arbitrum One at Arbitrum One's address,
    /// though Polygon's address holds the clone.
    function testPerNetworkCloneMissingOnArbitrumIsRefusedAtArbitrumsAddress() external {
        DeploySuite memory release = releasedSuites()[0];
        address arbitrumAddress = LibRainDeployMechanism.deployedAddress(release, 42161);
        vm.etch(arbitrumAddress, hex"");

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.ARBITRUM_ONE, arbitrumAddress
            )
        );
        this.testSuitesLiveOnEverySupportedNetwork();
    }
}
