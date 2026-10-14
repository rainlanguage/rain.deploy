// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {BeaconState, ChainBeacon} from "../../../src/lib/LibRainDeployBeacon.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID,
    PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
    PerNetworkCloneDeploys,
    onlyFirstRecordedNetwork,
    perNetworkCloneReleaseAddress
} from "../../abstract/PerNetworkCloneDeploys.sol";

contract RainDeployVerifyChainBeaconPerNetworkCloneUnrecordedTest is PerNetworkCloneDeploys, RainDeployVerifyChain {
    address constant OWNER = address(0xB0B);

    address internal sBeacon;

    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return PerNetworkCloneDeploys.supportedNetworks();
    }

    function releasedSuites()
        internal
        pure
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (DeploySuite[] memory)
    {
        DeploySuite[] memory suites = PerNetworkCloneDeploys.releasedSuites();
        suites[0] = onlyFirstRecordedNetwork(suites[0]);
        return suites;
    }

    function beacons() internal view override returns (ChainBeacon[] memory) {
        ChainBeacon[] memory chainBeacons = new ChainBeacon[](1);
        chainBeacons[0].chainId = PER_NETWORK_CLONE_POLYGON_CHAIN_ID;
        chainBeacons[0].beacon.beacon = sBeacon;
        chainBeacons[0].beacon.beaconCodeHash = sBeacon.codehash;
        chainBeacons[0].beacon.initial = BeaconState({implementation: "per-network-clone@0_0_1", owner: OWNER});
        return chainBeacons;
    }

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

    function testBeaconImplementationOnAnUnrecordedNetworkIsItsInitDataAddress() external {
        this.testSuitesLiveOnEverySupportedNetwork();
    }

    function testBeaconImplementationOnAnUnrecordedNetworkAtTheRecordedAddressIsRefused() external {
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
}
