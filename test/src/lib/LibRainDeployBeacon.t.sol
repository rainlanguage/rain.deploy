// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {DeployBeacon, LibRainDeployBeacon} from "../../../src/lib/LibRainDeployBeacon.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";

contract LibRainDeployBeaconTest is Test {
    string constant NETWORK = "test-network";

    UpgradeableBeacon internal sBeacon;
    address internal sImplementation;
    address internal sOwner = address(0xB0B);

    function setUp() external {
        sImplementation = address(new MockDeployableV2());
        sBeacon = new UpgradeableBeacon(sImplementation, sOwner);
    }

    function declared() internal view returns (DeployBeacon memory) {
        return DeployBeacon({
            beacon: address(sBeacon),
            beaconCodeHash: address(sBeacon).codehash,
            implementation: sImplementation,
            implementationCodeHash: sImplementation.codehash,
            owner: sOwner
        });
    }

    function externalCheckBeacon(DeployBeacon memory beacon) external view {
        LibRainDeployBeacon.checkBeacon(NETWORK, beacon);
    }

    function externalCheckBeacons(DeployBeacon[] memory beacons) external view {
        LibRainDeployBeacon.checkBeacons(NETWORK, beacons);
    }

    function testBeaconAtItsDeclaredStatePasses() external view {
        this.externalCheckBeacon(declared());
    }

    function testBeaconWithoutCodeIsNotDeployed() external {
        DeployBeacon memory beacon = declared();
        beacon.beacon = address(0xBEAC0);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, NETWORK, address(0xBEAC0)));
        this.externalCheckBeacon(beacon);
    }

    function testBeaconOfAnotherBuildIsRefused() external {
        DeployBeacon memory beacon = declared();
        beacon.beaconCodeHash = keccak256("another build");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.CodeHashMismatchOnNetwork.selector,
                NETWORK,
                address(sBeacon),
                keccak256("another build"),
                address(sBeacon).codehash
            )
        );
        this.externalCheckBeacon(beacon);
    }

    function testUpgradedBeaconIsRefusedAtThePreviousImplementation() external {
        address upgraded = address(new MockDeployable());
        vm.prank(sOwner);
        sBeacon.upgradeTo(upgraded);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector,
                NETWORK,
                address(sBeacon),
                0,
                sImplementation,
                upgraded
            )
        );
        this.externalCheckBeacon(declared());
    }

    function testUpgradedBeaconPassesAtTheCurrentImplementation() external {
        address upgraded = address(new MockDeployable());
        vm.prank(sOwner);
        sBeacon.upgradeTo(upgraded);
        DeployBeacon memory beacon = declared();
        beacon.implementation = upgraded;
        beacon.implementationCodeHash = upgraded.codehash;
        this.externalCheckBeacon(beacon);
    }

    function testMigratedOwnerIsRefusedAtThePreviousOwner() external {
        vm.prank(sOwner);
        sBeacon.transferOwnership(address(0xCAFE));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector, NETWORK, address(sBeacon), 1, sOwner, address(0xCAFE)
            )
        );
        this.externalCheckBeacon(declared());
    }

    function testMigratedOwnerPassesAtTheCurrentOwner() external {
        vm.prank(sOwner);
        sBeacon.transferOwnership(address(0xCAFE));
        DeployBeacon memory beacon = declared();
        beacon.owner = address(0xCAFE);
        this.externalCheckBeacon(beacon);
    }

    function testImplementationWithoutCodeIsNotDeployed() external {
        vm.etch(sImplementation, hex"");
        DeployBeacon memory beacon = declared();
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, NETWORK, sImplementation));
        this.externalCheckBeacon(beacon);
    }

    function testImplementationOfOtherCodeIsRefused() external {
        DeployBeacon memory beacon = declared();
        beacon.implementationCodeHash = keccak256("other code");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.CodeHashMismatchOnNetwork.selector,
                NETWORK,
                sImplementation,
                keccak256("other code"),
                sImplementation.codehash
            )
        );
        this.externalCheckBeacon(beacon);
    }

    function testNonBeaconAtTheDeclaredHashIsRefused() external {
        DeployBeacon memory beacon = declared();
        beacon.beacon = sImplementation;
        beacon.beaconCodeHash = sImplementation.codehash;
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.ResolvedAddressReadFailed.selector, NETWORK, sImplementation, 0, "")
        );
        this.externalCheckBeacon(beacon);
    }

    function testEveryBeaconIsChecked() external {
        DeployBeacon[] memory beacons = new DeployBeacon[](2);
        beacons[0] = declared();
        beacons[1] = declared();
        beacons[1].owner = address(0xCAFE);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector, NETWORK, address(sBeacon), 1, address(0xCAFE), sOwner
            )
        );
        this.externalCheckBeacons(beacons);
    }
}
