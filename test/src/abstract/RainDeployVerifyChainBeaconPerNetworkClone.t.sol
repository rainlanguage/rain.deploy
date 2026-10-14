// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {BeaconState, ChainBeacon} from "../../../src/lib/LibRainDeployBeacon.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../../../src/lib/LibRainDeployMechanism.sol";
import {PerNetworkCloneDeploys} from "../../abstract/PerNetworkCloneDeploys.sol";

contract RainDeployVerifyChainBeaconPerNetworkCloneTest is PerNetworkCloneDeploys, RainDeployVerifyChain {
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

    function beacons() internal view override returns (ChainBeacon[] memory) {
        ChainBeacon[] memory chainBeacons = new ChainBeacon[](1);
        chainBeacons[0].chainId = 137;
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
        address[] memory addresses = LibRainDeployMechanism.deployedAddresses(release);
        for (uint256 i = 0; i < addresses.length; i++) {
            vm.etch(addresses[i], release.storedRuntimeCode);
            vm.makePersistent(addresses[i]);
        }
        sBeacon = address(new UpgradeableBeacon(LibRainDeployMechanism.deployedAddress(release, 137), OWNER));
        vm.makePersistent(sBeacon);
    }

    function testBeaconImplementationIsTheSuitesAddressOnTheBeaconsNetwork() external {
        this.testSuitesLiveOnEverySupportedNetwork();
    }

    function testBeaconImplementationOnAnotherNetworksAddressIsRefused() external {
        DeploySuite memory release = releasedSuites()[0];
        address polygonAddress = LibRainDeployMechanism.deployedAddress(release, 137);
        address arbitrumAddress = LibRainDeployMechanism.deployedAddress(release, 42161);
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
