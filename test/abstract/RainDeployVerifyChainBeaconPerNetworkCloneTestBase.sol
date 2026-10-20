// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ResolvedBeacon} from "../../src/abstract/RainDeployVerifyBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {
    PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID,
    PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
    perNetworkCloneReleaseAddress
} from "./PerNetworkCloneDeploys.sol";
import {PerNetworkCloneBeaconVerifyChain} from "./PerNetworkCloneBeaconVerifyChain.sol";

/// @title RainDeployVerifyChainBeaconPerNetworkCloneTestBase
/// @notice The per-network clone beacon tests, run over each per-network clone release fixture.
abstract contract RainDeployVerifyChainBeaconPerNetworkCloneTestBase is PerNetworkCloneBeaconVerifyChain {
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
        sBeacon = address(new UpgradeableBeacon(addresses[1], OWNER));
        vm.makePersistent(sBeacon);
    }

    function testBeaconImplementationAtAnotherNetworksCloneIsRefused() external {
        address polygonAddress = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        address arbitrumAddress = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        vm.prank(OWNER);
        UpgradeableBeacon(sBeacon).upgradeTo(arbitrumAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector,
                LibRainDeploy.POLYGON,
                sBeacon,
                0,
                polygonAddress,
                arbitrumAddress
            )
        );
        this.testSuitesLiveOnEverySupportedNetwork();
    }

    /// External wrapper for `resolveBeacons` on one named network.
    /// @param network The network.
    /// @return The beacons resolved on it.
    function externalResolveBeacons(string memory network) external returns (ResolvedBeacon[] memory) {
        string[] memory names = new string[](1);
        names[0] = network;
        return resolveBeacons(LibRainDeploy.declaredNetworkConfigs(names));
    }

    function testBeaconNamedBySuiteIsAtItsNetworksClone() external {
        sBeaconBySuite = true;
        ResolvedBeacon[] memory resolved = this.externalResolveBeacons(LibRainDeploy.POLYGON);
        assertEq(resolved.length, 1);
        assertEq(resolved[0].beacon.beacon, perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID));
        assertTrue(resolved[0].beacon.beacon != perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID));
    }
}
