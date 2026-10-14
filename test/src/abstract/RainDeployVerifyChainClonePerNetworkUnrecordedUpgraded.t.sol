// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {CloneDeploy, CloneNetworks} from "../../../src/lib/LibRainDeployClone.sol";
import {
    PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID,
    PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
    PerNetworkCloneDeploys,
    onlyFirstRecordedNetwork,
    perNetworkCloneReleaseAddress
} from "../../abstract/PerNetworkCloneDeploys.sol";
import {
    UpgradedPerNetworkCloneDeploys,
    upgradedPerNetworkClone,
    upgradedPerNetworkCloneAddress
} from "../../abstract/UpgradedPerNetworkCloneDeploys.sol";

/// @title RainDeployVerifyChainClonePerNetworkUnrecordedUpgradedTest
/// @notice The chain matrix over a per-network clone release cut when the repo
/// supported Arbitrum One alone, in a repo that now supports Polygon too and
/// whose candidate has since moved to another factory, implementation and
/// salt.
///
/// Polygon is checked at the address the RELEASE's factory, implementation and
/// salt derive with the candidate's Polygon init data, and nothing of the
/// candidate's is on any fork.
contract RainDeployVerifyChainClonePerNetworkUnrecordedUpgradedTest is
    UpgradedPerNetworkCloneDeploys,
    RainDeployVerifyChain
{
    /// @inheritdoc PerNetworkCloneDeploys
    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return PerNetworkCloneDeploys.supportedNetworks();
    }

    /// Puts the release's dependencies, and its clone at the release's address
    /// for each network, on every fork.
    function setUp() external {
        DeploySuite memory release = releasedSuites()[0];
        for (uint256 i = 0; i < release.dependencies.length; i++) {
            vm.etch(release.dependencies[i].deployedAddress, release.dependencies[i].runtimeCode);
            vm.makePersistent(release.dependencies[i].deployedAddress);
        }
        address[] memory addresses = new address[](2);
        addresses[0] = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        addresses[1] = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        for (uint256 i = 0; i < addresses.length; i++) {
            vm.etch(addresses[i], release.storedRuntimeCode);
            vm.makePersistent(addresses[i]);
        }
    }

    /// External wrapper for `checkDeployedOnSupportedNetworks`.
    /// @param suites The suites to check.
    function externalCheckDeployedOnSupportedNetworks(DeploySuite[] memory suites) external {
        checkDeployedOnSupportedNetworks(suites);
    }

    /// The release passes with its clone at the release-derived Polygon
    /// address, and with that address empty is refused on Polygon naming it:
    /// Polygon's address came from the release's factory, implementation and
    /// salt, each of which the candidate no longer shares, and the release's
    /// dependencies are what the matrix held Polygon to.
    function testUnrecordedNetworkIsCheckedUnderTheReleasesFactoryAndImplementation() external {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = onlyFirstRecordedNetwork(releasedSuites()[0]);
        CloneNetworks memory release = abi.decode(suites[0].mechanismData, (CloneNetworks));
        assertEq(release.networks.length, 1);
        assertEq(release.networks[0].chainId, PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        CloneDeploy memory candidate = upgradedPerNetworkClone();
        assertNotEq(candidate.factory, release.factory);
        assertNotEq(candidate.implementation, release.implementation);
        assertNotEq(candidate.salt, release.salt);

        address polygonAddress = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        assertNotEq(polygonAddress, upgradedPerNetworkCloneAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID));
        assertEq(upgradedPerNetworkCloneAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID).code.length, 0);
        assertEq(candidate.implementation.code.length, 0);
        assertEq(candidate.factory.code.length, 0);

        this.externalCheckDeployedOnSupportedNetworks(suites);

        vm.etch(polygonAddress, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.POLYGON, polygonAddress)
        );
        this.externalCheckDeployedOnSupportedNetworks(suites);
    }
}
