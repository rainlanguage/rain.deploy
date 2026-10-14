// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {
    BeaconState,
    BeaconTransition,
    DeployBeacon,
    LibRainDeployBeacon
} from "../../../src/lib/LibRainDeployBeacon.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {
    IMigrationRegistryV2,
    MIGRATION_HEAD_GENESIS,
    Prerequisite
} from "../../../src/interface/IMigrationRegistryV2.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";

contract LibRainDeployBeaconTest is Test {
    string constant NETWORK = "test-network";
    address constant WRITER = address(0x5AFE);
    bytes32 constant NAMESPACE = keccak256("beacons");
    bytes32 constant UPGRADE = keccak256("upgrade");
    bytes32 constant HANDOVER = keccak256("handover");

    UpgradeableBeacon internal sBeacon;
    address internal sImplementation;
    address internal sOwner = address(0xB0B);

    function setUp() external {
        sImplementation = address(new MockDeployableV2());
        sBeacon = new UpgradeableBeacon(sImplementation, sOwner);
    }

    function deployRegistry() internal {
        LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
    }

    function applyMigration(bytes32 migration, bytes32 head) internal {
        vm.prank(WRITER);
        IMigrationRegistryV2(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigration(NAMESPACE, migration, LibMigrationRegistry.onto(WRITER, NAMESPACE, head));
    }

    function transition(bytes32 migration, string memory implementation, address owner)
        internal
        pure
        returns (BeaconTransition memory)
    {
        return BeaconTransition({
            migration: Prerequisite({writer: WRITER, namespace: NAMESPACE, migration: migration}),
            state: BeaconState({implementation: implementation, owner: owner})
        });
    }

    function declared(BeaconTransition[] memory transitions) internal view returns (DeployBeacon memory) {
        return DeployBeacon({
            beacon: address(sBeacon),
            beaconCodeHash: address(sBeacon).codehash,
            initial: BeaconState({implementation: "initial", owner: sOwner}),
            transitions: transitions
        });
    }

    function upgradeThenHandover() internal pure returns (BeaconTransition[] memory) {
        BeaconTransition[] memory transitions = new BeaconTransition[](2);
        transitions[0] = transition(UPGRADE, "upgraded", address(0xB0B));
        transitions[1] = transition(HANDOVER, "upgraded", address(0xCAFE));
        return transitions;
    }

    function externalAppliedState(DeployBeacon memory beacon) external view returns (uint256) {
        return LibRainDeployBeacon.appliedState(beacon);
    }

    function externalCheckBeacon(DeployBeacon memory beacon, address implementation, address owner) external view {
        LibRainDeployBeacon.checkBeacon(NETWORK, beacon, implementation, owner);
    }

    function testBeaconWithoutTransitionsIsInitialWithoutReadingTheRegistry() external view {
        assertEq(this.externalAppliedState(declared(new BeaconTransition[](0))), 0);
    }

    function testTransitionsWithoutARegistryAreRefused() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalAppliedState(declared(upgradeThenHandover()));
    }

    function testNoAppliedMigrationIsInitial() external {
        deployRegistry();
        assertEq(this.externalAppliedState(declared(upgradeThenHandover())), 0);
    }

    function testAppliedMigrationSelectsItsTransition() external {
        deployRegistry();
        applyMigration(UPGRADE, MIGRATION_HEAD_GENESIS);
        assertEq(this.externalAppliedState(declared(upgradeThenHandover())), 1);
    }

    function testLatestAppliedTransitionWins() external {
        deployRegistry();
        applyMigration(UPGRADE, MIGRATION_HEAD_GENESIS);
        applyMigration(HANDOVER, UPGRADE);
        assertEq(this.externalAppliedState(declared(upgradeThenHandover())), 2);
    }

    function testLaterAppliedTransitionWinsOverAnEarlierUnappliedOne() external {
        deployRegistry();
        applyMigration(HANDOVER, MIGRATION_HEAD_GENESIS);
        assertEq(this.externalAppliedState(declared(upgradeThenHandover())), 2);
    }

    function testMigrationAppliedByAnotherWriterIsNotApplied() external {
        deployRegistry();
        applyMigration(UPGRADE, MIGRATION_HEAD_GENESIS);
        BeaconTransition[] memory transitions = upgradeThenHandover();
        transitions[0].migration.writer = address(0xBAD);
        assertEq(this.externalAppliedState(declared(transitions)), 0);
    }

    function testMigrationAppliedInAnotherNamespaceIsNotApplied() external {
        deployRegistry();
        applyMigration(UPGRADE, MIGRATION_HEAD_GENESIS);
        BeaconTransition[] memory transitions = upgradeThenHandover();
        transitions[0].migration.namespace = keccak256("elsewhere");
        assertEq(this.externalAppliedState(declared(transitions)), 0);
    }

    function testStateAtIndexesInitialThenTransitions() external pure {
        BeaconTransition[] memory transitions = upgradeThenHandover();
        DeployBeacon memory beacon = DeployBeacon({
            beacon: address(0),
            beaconCodeHash: bytes32(0),
            initial: BeaconState({implementation: "initial", owner: address(0xB0B)}),
            transitions: transitions
        });
        assertEq(LibRainDeployBeacon.stateAt(beacon, 0).implementation, "initial");
        assertEq(LibRainDeployBeacon.stateAt(beacon, 1).implementation, "upgraded");
        assertEq(LibRainDeployBeacon.stateAt(beacon, 1).owner, address(0xB0B));
        assertEq(LibRainDeployBeacon.stateAt(beacon, 2).owner, address(0xCAFE));
    }

    function testBeaconAtTheExpectedStatePasses() external view {
        this.externalCheckBeacon(declared(new BeaconTransition[](0)), sImplementation, sOwner);
    }

    function testBeaconWithoutCodeIsNotDeployed() external {
        DeployBeacon memory beacon = declared(new BeaconTransition[](0));
        beacon.beacon = address(0xBEAC0);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, NETWORK, address(0xBEAC0)));
        this.externalCheckBeacon(beacon, sImplementation, sOwner);
    }

    function testBeaconOfAnotherBuildIsRefused() external {
        DeployBeacon memory beacon = declared(new BeaconTransition[](0));
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
        this.externalCheckBeacon(beacon, sImplementation, sOwner);
    }

    function testBeaconAtAnotherImplementationIsRefused() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector,
                NETWORK,
                address(sBeacon),
                0,
                address(0x1111),
                sImplementation
            )
        );
        this.externalCheckBeacon(declared(new BeaconTransition[](0)), address(0x1111), sOwner);
    }

    function testBeaconOfAnotherOwnerIsRefused() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector, NETWORK, address(sBeacon), 1, address(0xCAFE), sOwner
            )
        );
        this.externalCheckBeacon(declared(new BeaconTransition[](0)), sImplementation, address(0xCAFE));
    }

    function testNonBeaconAtTheDeclaredHashIsRefused() external {
        DeployBeacon memory beacon = declared(new BeaconTransition[](0));
        beacon.beacon = sImplementation;
        beacon.beaconCodeHash = sImplementation.codehash;
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.ResolvedAddressReadFailed.selector, NETWORK, sImplementation, 0, "")
        );
        this.externalCheckBeacon(beacon, sImplementation, sOwner);
    }
}
