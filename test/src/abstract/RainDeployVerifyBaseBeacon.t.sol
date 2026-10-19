// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    BeaconOnUncheckedNetwork,
    BeaconSeatedImplementation,
    BeaconSeatedOwner,
    DerivedDeploy
} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {
    BeaconTransition,
    ChainBeacon,
    DeployBeacon,
    LibRainDeployBeacon
} from "../../../src/lib/LibRainDeployBeacon.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";
import {LibBeaconDeclarations} from "../../lib/LibBeaconDeclarations.sol";
import {BeaconVerifyFixture} from "../../abstract/BeaconVerifyFixture.sol";

/// @title RainDeployVerifyBaseBeaconTest
/// @notice `RainDeployVerifyBase`'s resolution of each declared beacon, before any network is read.
contract RainDeployVerifyBaseBeaconTest is BeaconVerifyFixture {
    using LibBeaconDeclarations for ChainBeacon[];

    /// External wrapper for `resolveBeacons`.
    /// @param networks The networks whose beacons to resolve.
    function externalResolveBeacons(SupportedNetwork[] memory networks) external {
        resolveBeacons(networks);
    }

    /// External wrapper for `resolveBeacons`, counting what it resolves.
    /// @param networks The networks whose beacons to resolve.
    /// @return How many beacons resolved.
    function externalResolvedCount(SupportedNetwork[] memory networks) external returns (uint256) {
        return resolveBeacons(networks).length;
    }

    /// External wrapper for `resolveBeacon` on Arbitrum One.
    /// @param declaration The beacon.
    /// @return `declaration`, as `resolveBeacon` left it.
    function externalResolveBeaconLeavesDeclaration(DeployBeacon memory declaration)
        external
        returns (DeployBeacon memory)
    {
        DeploySuite[] memory released = releasedSuites();
        resolveBeacon(declaration, 42161, 0, released, new DerivedDeploy[](released.length));
        return declaration;
    }

    function repeating(DeployBeacon memory beacon) internal pure returns (DeployBeacon memory) {
        BeaconTransition[] memory transitions = new BeaconTransition[](2);
        transitions[0] = beacon.transitions[0];
        transitions[1] = beacon.transitions[0];
        beacon.transitions = transitions;
        return beacon;
    }

    function testBeaconOnAnUncheckedNetworkIsRefusedBeforeAnEarlierBeaconResolves() external {
        supportOnly(LibRainDeploy.ARBITRUM_ONE, "");
        sBeacons.declare(42161, declared("no-such-suite", OWNER));
        sBeacons.declare(1, declared("beacon-implementation@0_0_1", OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconOnUncheckedNetwork.selector, 1, 1));
        this.externalResolveBeacons(arbitrum());
    }

    function testBeaconOnACheckedNetworkOffTheSupportedNetworksIsRefused() external {
        supportOnly(LibRainDeploy.ARBITRUM_ONE, "");
        sBeacons.declare(8453, declared("beacon-implementation@0_0_1", OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconOnUncheckedNetwork.selector, 8453, 0));
        this.externalResolveBeacons(networksNamed(LibRainDeploy.BASE, ""));
    }

    function testResolvingABeaconLeavesItsDeclarationUnwritten() external {
        DeployBeacon memory declaration = this.externalResolveBeaconLeavesDeclaration(bySuite("beacon@0_0_1", OWNER));
        assertEq(declaration.beacon, address(0));
        assertEq(declaration.beaconCodeHash, bytes32(0));
    }

    function testBeaconOnAnEarlierCheckedNetworkResolves() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        assertEq(this.externalResolvedCount(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE)), 1);
    }

    function testEachReleasedSuiteBeaconsNameIsDerivedOnce() external {
        sBeacons.declare(42161, migrating("beacon-upgrade@0_0_1", OWNER));
        sBeacons.declare(8453, declared("beacon-implementation@0_0_1", OWNER));
        sBeacons.declare(42161, bySuite("beacon@0_0_1", OWNER));
        DeployBeacon memory other = declared("beacon-upgrade@0_0_1", OWNER);
        other.beacon = address(0xBEAC0);
        sBeacons.declare(8453, other);
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, type(MockDeployableV2).creationCode, 1);
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, type(MockDeployable).creationCode, 1);
        // One derivation, one seated-state deploy.
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, beaconCreationCode(), 2);
        this.externalResolveBeacons(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE));
    }

    function testRepeatedMigrationIsRefusedWhileResolving() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        sBeacons.declare(42161, repeating(migrating("beacon-upgrade@0_0_1", OWNER)));
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeployBeacon.BeaconTransitionMigrationRepeated.selector, 42161, sBeacon, 1)
        );
        this.externalResolveBeacons(arbitrum());
    }

    function testRepeatedMigrationOnASuiteBeaconNamesItsDerivedAddress() external {
        DeployBeacon memory beacon = migrating("beacon-upgrade@0_0_1", OWNER);
        beacon.beaconSuite = "beacon@0_0_1";
        beacon.beacon = address(0);
        beacon.beaconCodeHash = bytes32(0);
        sBeacons.declare(42161, repeating(beacon));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployBeacon.BeaconTransitionMigrationRepeated.selector, 42161, sSuiteBeacon, 1
            )
        );
        this.externalResolveBeacons(arbitrum());
    }

    function testNarrowedCheckResolvesOnlyTheBeaconsOnItsNetworks() external {
        sBeacons.declare(8453, declared("beacon-upgrade@0_0_1", OWNER));
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, type(MockDeployable).creationCode, 0);
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, type(MockDeployableV2).creationCode, 1);
        this.externalResolveBeacons(arbitrum());
    }

    function testNarrowedResolveCountsOnlyTheBeaconsOnItsNetworks() external {
        sBeacons.declare(8453, declared("beacon-implementation@0_0_1", OWNER));
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        DeployBeacon memory other = declared("beacon-upgrade@0_0_1", OWNER);
        other.beacon = address(0xBEAC0);
        sBeacons.declare(8453, other);
        assertEq(this.externalResolvedCount(arbitrum()), 1);
        assertEq(this.externalResolvedCount(networksNamed(LibRainDeploy.BASE, "")), 2);
        assertEq(this.externalResolvedCount(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE)), 3);
    }

    function testNarrowedResolveWithNoBeaconOnItsNetworksIsEmpty() external {
        sBeacons.declare(8453, declared("beacon-implementation@0_0_1", OWNER));
        assertEq(this.externalResolvedCount(arbitrum()), 0);
    }

    function testNoBeaconsResolveWithoutReadingSupportedNetworks() external {
        supportOnly("not-a-catalogue-network", "");
        assertEq(this.externalResolvedCount(arbitrum()), 0);
    }

    function testBeaconSuiteSeatingAnotherImplementationIsRefused() external {
        DeployBeacon memory beacon = bySuite("beacon@0_0_1", OWNER);
        beacon.initial.implementation = "beacon-upgrade@0_0_1";
        sBeacons.declare(42161, beacon);
        vm.expectRevert(
            abi.encodeWithSelector(BeaconSeatedImplementation.selector, 42161, 0, abi.encode(sImplementation))
        );
        this.externalResolveBeacons(arbitrum());
    }

    function testBeaconSuiteSeatingItsInitialStateResolves() external {
        sBeacons.declare(42161, bySuite("beacon@0_0_1", OWNER));
        assertEq(this.externalResolvedCount(arbitrum()), 1);
    }

    function testSeatedStateDeployIsReverted() external {
        sBeacons.declare(42161, bySuite("beacon@0_0_1", OWNER));
        vm.prank(OWNER);
        UpgradeableBeacon(sSuiteBeacon).transferOwnership(NEW_OWNER);
        this.externalResolveBeacons(arbitrum());
        assertEq(UpgradeableBeacon(sSuiteBeacon).owner(), NEW_OWNER);
    }

    function testBeaconSuiteSeatingItsInitialStateBeforeATransitionResolves() external {
        DeployBeacon memory beacon = bySuite("beacon@0_0_1", OWNER);
        beacon.transitions = migrating("beacon-upgrade@0_0_1", NEW_OWNER).transitions;
        sBeacons.declare(42161, beacon);
        assertEq(this.externalResolvedCount(arbitrum()), 1);
    }

    function testBeaconSuiteSeatingAnotherOwnerIsRefusedAtItsIndex() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        sBeacons.declare(42161, bySuite("beacon@0_0_1", NEW_OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconSeatedOwner.selector, 42161, 1, abi.encode(OWNER)));
        this.externalResolveBeacons(arbitrum());
    }

    function testAReadThatRevertsSeatsNothing() external pure {
        assertFalse(seatsOther(false, abi.encode(NEW_OWNER), OWNER));
    }

    function testAReadAnsweringNothingSeatsNothing() external pure {
        assertFalse(seatsOther(true, "", OWNER));
    }

    function testAReadAnsweringAnotherAddressSeatsIt() external pure {
        assertTrue(seatsOther(true, abi.encode(NEW_OWNER), OWNER));
        assertFalse(seatsOther(true, abi.encode(OWNER), OWNER));
    }
}
