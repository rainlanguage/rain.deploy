// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, stdError} from "forge-std-1.17.0/src/Test.sol";
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
    IMigrationRegistryV4,
    MIGRATION_HEAD_GENESIS,
    Prerequisite
} from "../../../src/interface/IMigrationRegistryV4.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";
import {MockOwnable2StepBeacon} from "../../concrete/MockOwnable2StepBeacon.sol";
import {MockFallbackBeacon} from "../../concrete/MockFallbackBeacon.sol";
import {LibBeaconTest} from "../../lib/LibBeaconTest.sol";

/// @title LibRainDeployBeaconTest
/// @notice `LibRainDeployBeacon`'s expected state from the migration registry, and its check of a beacon against it.
contract LibRainDeployBeaconTest is Test {
    string constant NETWORK = "test-network";
    address constant WRITER = address(0x5AFE);
    bytes32 constant NAMESPACE = keccak256("beacons");
    bytes32 constant UPGRADE = keccak256("upgrade");
    bytes32 constant HANDOVER = keccak256("handover");
    bytes32 constant INTERIM = keccak256("interim");
    bytes32 constant ROLLBACK = keccak256("rollback");
    bytes32 constant OTHER = keccak256("other beacons");
    bytes32 constant THIRD = keccak256("third beacons");

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
        LibBeaconTest.applyMigration(vm, WRITER, NAMESPACE, migration, head);
    }

    function onto(bytes32 namespace, bytes32 head) internal pure returns (Prerequisite[] memory) {
        return LibMigrationRegistry.onto(WRITER, namespace, head);
    }

    function andAfter(Prerequisite[] memory list, bytes32 namespace, bytes32 migration)
        internal
        pure
        returns (Prerequisite[] memory)
    {
        Prerequisite[] memory longer = new Prerequisite[](list.length + 1);
        for (uint256 i = 0; i < list.length; i++) {
            longer[i] = list[i];
        }
        longer[list.length] = record(namespace, migration);
        return longer;
    }

    function record(bytes32 namespace, bytes32 migration) internal pure returns (Prerequisite memory) {
        return Prerequisite({writer: WRITER, namespace: namespace, migration: migration});
    }

    function applyIn(bytes32 namespace, bytes32 migration, Prerequisite[] memory list) internal {
        LibBeaconTest.applyMigration(vm, WRITER, namespace, migration, list);
    }

    function applyAt(bytes32 namespace, bytes32 migration, uint256 moment, Prerequisite[] memory list) internal {
        vm.prank(WRITER);
        IMigrationRegistryV4(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS)
            .applyMigrationHistoryV4(WRITER, namespace, migration, moment, list, "");
    }

    function expectOutOfOrder(uint256 index) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployBeacon.BeaconTransitionsOutOfOrder.selector, NETWORK, address(sBeacon), index
            )
        );
    }

    function externalRecordedBefore(Prerequisite memory earlier, Prerequisite memory later)
        external
        view
        returns (bool)
    {
        return LibRainDeployBeacon.recordedBefore(earlier, later);
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
            beaconSuite: "",
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
        return LibRainDeployBeacon.appliedState(NETWORK, beacon);
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

    function testTransitionsAppliedInDeclaredOrderAcrossBlocksSelectTheLatest() external {
        deployRegistry();
        applyMigration(UPGRADE, MIGRATION_HEAD_GENESIS);
        vm.warp(block.timestamp + 1);
        applyMigration(HANDOVER, UPGRADE);
        assertEq(this.externalAppliedState(declared(upgradeThenHandover())), 2);
    }

    function testTransitionsAppliedOutOfDeclaredOrderAreRefused() external {
        deployRegistry();
        applyMigration(UPGRADE, MIGRATION_HEAD_GENESIS);
        vm.warp(block.timestamp + 1);
        applyMigration(HANDOVER, UPGRADE);
        BeaconTransition[] memory transitions = upgradeThenHandover();
        (transitions[0], transitions[1]) = (transitions[1], transitions[0]);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployBeacon.BeaconTransitionsOutOfOrder.selector, NETWORK, address(sBeacon), 1
            )
        );
        this.externalAppliedState(declared(transitions));
    }

    function testTransitionsAppliedOutOfDeclaredOrderInOneBlockAreRefused() external {
        deployRegistry();
        applyMigration(UPGRADE, MIGRATION_HEAD_GENESIS);
        applyMigration(HANDOVER, UPGRADE);
        BeaconTransition[] memory transitions = upgradeThenHandover();
        (transitions[0], transitions[1]) = (transitions[1], transitions[0]);
        expectOutOfOrder(1);
        this.externalAppliedState(declared(transitions));
    }

    function testHistoryMomentsCannotFakeTransitionOrder() external {
        deployRegistry();
        vm.warp(1000);
        applyAt(OTHER, HANDOVER, 900, onto(OTHER, MIGRATION_HEAD_GENESIS));
        applyAt(NAMESPACE, UPGRADE, 100, andAfter(onto(NAMESPACE, MIGRATION_HEAD_GENESIS), OTHER, HANDOVER));
        BeaconTransition[] memory transitions = upgradeThenHandover();
        transitions[1].migration.namespace = OTHER;
        expectOutOfOrder(1);
        this.externalAppliedState(declared(transitions));
    }

    function testTransitionAppliedAfterTheEarlierAsAPrerequisiteIsInOrderWhateverTheMoments() external {
        deployRegistry();
        vm.warp(1000);
        applyAt(NAMESPACE, UPGRADE, 900, onto(NAMESPACE, MIGRATION_HEAD_GENESIS));
        applyAt(OTHER, HANDOVER, 100, andAfter(onto(OTHER, MIGRATION_HEAD_GENESIS), NAMESPACE, UPGRADE));
        BeaconTransition[] memory transitions = upgradeThenHandover();
        transitions[1].migration.namespace = OTHER;
        assertEq(this.externalAppliedState(declared(transitions)), 2);
    }

    function testTransitionsInUnrelatedLinesAreRefused() external {
        deployRegistry();
        applyMigration(UPGRADE, MIGRATION_HEAD_GENESIS);
        vm.warp(block.timestamp + 1);
        applyIn(OTHER, HANDOVER, onto(OTHER, MIGRATION_HEAD_GENESIS));
        BeaconTransition[] memory transitions = upgradeThenHandover();
        transitions[1].migration.namespace = OTHER;
        expectOutOfOrder(1);
        this.externalAppliedState(declared(transitions));
    }

    function testTransitionAppliedAfterAnUndeclaredMigrationIsInOrder() external {
        deployRegistry();
        applyMigration(UPGRADE, MIGRATION_HEAD_GENESIS);
        applyMigration(INTERIM, UPGRADE);
        applyMigration(HANDOVER, INTERIM);
        assertEq(this.externalAppliedState(declared(upgradeThenHandover())), 2);
    }

    function testOrderWalkReadsEachRecordOnce() external {
        deployRegistry();
        applyMigration(INTERIM, MIGRATION_HEAD_GENESIS);
        applyMigration(UPGRADE, INTERIM);
        applyIn(OTHER, ROLLBACK, andAfter(onto(OTHER, MIGRATION_HEAD_GENESIS), NAMESPACE, INTERIM));
        applyIn(OTHER, HANDOVER, andAfter(onto(OTHER, ROLLBACK), NAMESPACE, UPGRADE));
        applyIn(THIRD, UPGRADE, onto(THIRD, MIGRATION_HEAD_GENESIS));
        vm.expectCall(
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            abi.encodeCall(IMigrationRegistryV4.appliedAfterV4, (WRITER, NAMESPACE, INTERIM)),
            1
        );
        assertFalse(this.externalRecordedBefore(record(THIRD, UPGRADE), record(OTHER, HANDOVER)));
    }

    function testOrderWalkStillReadsEachRecordOnceAfterGrowing() external {
        deployRegistry();
        applyMigration(INTERIM, MIGRATION_HEAD_GENESIS);
        applyMigration(UPGRADE, INTERIM);
        applyIn(OTHER, ROLLBACK, andAfter(onto(OTHER, MIGRATION_HEAD_GENESIS), NAMESPACE, INTERIM));
        applyIn(THIRD, UPGRADE, onto(THIRD, MIGRATION_HEAD_GENESIS));
        applyIn(THIRD, HANDOVER, onto(THIRD, UPGRADE));
        applyIn(
            OTHER,
            HANDOVER,
            andAfter(andAfter(andAfter(onto(OTHER, ROLLBACK), NAMESPACE, INTERIM), THIRD, UPGRADE), NAMESPACE, UPGRADE)
        );
        vm.expectCall(
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            abi.encodeCall(IMigrationRegistryV4.appliedAfterV4, (WRITER, NAMESPACE, INTERIM)),
            1
        );
        assertFalse(this.externalRecordedBefore(record(THIRD, HANDOVER), record(OTHER, HANDOVER)));
    }

    /// `OTHER ROLLBACK` lists the already-reached `NAMESPACE INTERIM` before `THIRD HANDOVER`, the only way to
    /// `THIRD UPGRADE`.
    function testOrderWalkReadsPastAReachedRecordToTheEarlier() external {
        deployRegistry();
        applyIn(THIRD, UPGRADE, onto(THIRD, MIGRATION_HEAD_GENESIS));
        applyIn(THIRD, HANDOVER, onto(THIRD, UPGRADE));
        applyMigration(INTERIM, MIGRATION_HEAD_GENESIS);
        applyIn(
            OTHER,
            ROLLBACK,
            andAfter(andAfter(onto(OTHER, MIGRATION_HEAD_GENESIS), NAMESPACE, INTERIM), THIRD, HANDOVER)
        );
        applyIn(OTHER, HANDOVER, andAfter(onto(OTHER, ROLLBACK), NAMESPACE, INTERIM));
        assertTrue(this.externalRecordedBefore(record(THIRD, UPGRADE), record(OTHER, HANDOVER)));
    }

    function upgradeHandoverRollback() internal pure returns (BeaconTransition[] memory) {
        BeaconTransition[] memory transitions = new BeaconTransition[](3);
        transitions[0] = transition(UPGRADE, "upgraded", address(0xB0B));
        transitions[1] = transition(HANDOVER, "upgraded", address(0xCAFE));
        transitions[2] = transition(ROLLBACK, "initial", address(0xCAFE));
        return transitions;
    }

    function testTransitionIsHeldToTheLatestEarlierAppliedOneNotTheFirst() external {
        deployRegistry();
        applyMigration(UPGRADE, MIGRATION_HEAD_GENESIS);
        applyMigration(ROLLBACK, UPGRADE);
        applyMigration(HANDOVER, ROLLBACK);
        expectOutOfOrder(2);
        this.externalAppliedState(declared(upgradeHandoverRollback()));
    }

    function testTransitionAfterAnUnappliedOneIsHeldToTheLatestApplied() external {
        deployRegistry();
        applyMigration(UPGRADE, MIGRATION_HEAD_GENESIS);
        applyMigration(ROLLBACK, UPGRADE);
        assertEq(this.externalAppliedState(declared(upgradeHandoverRollback())), 3);
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
            beaconSuite: "",
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

    function testOutOfOrderTransitionAfterAnUnappliedOneReportsItsOwnIndex() external {
        deployRegistry();
        applyMigration(ROLLBACK, MIGRATION_HEAD_GENESIS);
        applyMigration(UPGRADE, ROLLBACK);
        expectOutOfOrder(2);
        this.externalAppliedState(declared(upgradeHandoverRollback()));
    }

    function expectRepeated(uint256 index) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployBeacon.BeaconTransitionMigrationRepeated.selector, block.chainid, address(sBeacon), index
            )
        );
    }

    function testTransitionsRepeatingAnAppliedMigrationAreRefusedAsRepeated() external {
        deployRegistry();
        applyMigration(UPGRADE, MIGRATION_HEAD_GENESIS);
        BeaconTransition[] memory transitions = upgradeThenHandover();
        transitions[1].migration.migration = UPGRADE;
        expectRepeated(1);
        this.externalAppliedState(declared(transitions));
    }

    function testTransitionsRepeatingAMigrationAreRefusedBeforeReadingTheRegistry() external {
        BeaconTransition[] memory transitions = upgradeHandoverRollback();
        transitions[2].migration.migration = HANDOVER;
        expectRepeated(2);
        this.externalAppliedState(declared(transitions));
    }

    function testTheSameMigrationIdInAnotherLineIsADistinctTransition() external {
        deployRegistry();
        applyIn(NAMESPACE, UPGRADE, onto(NAMESPACE, MIGRATION_HEAD_GENESIS));
        applyIn(OTHER, UPGRADE, andAfter(onto(OTHER, MIGRATION_HEAD_GENESIS), NAMESPACE, UPGRADE));
        BeaconTransition[] memory transitions = upgradeThenHandover();
        transitions[1].migration = record(OTHER, UPGRADE);
        assertEq(this.externalAppliedState(declared(transitions)), 2);
    }

    function testTheSameMigrationIdUnderAnotherWriterIsADistinctTransition() external {
        deployRegistry();
        applyMigration(UPGRADE, MIGRATION_HEAD_GENESIS);
        address otherWriter = address(0x0DD);
        Prerequisite[] memory list = new Prerequisite[](2);
        list[0] = Prerequisite({writer: otherWriter, namespace: NAMESPACE, migration: MIGRATION_HEAD_GENESIS});
        list[1] = record(NAMESPACE, UPGRADE);
        LibBeaconTest.applyMigration(vm, otherWriter, NAMESPACE, UPGRADE, list);
        BeaconTransition[] memory transitions = upgradeThenHandover();
        transitions[1].migration = Prerequisite({writer: otherWriter, namespace: NAMESPACE, migration: UPGRADE});
        assertEq(this.externalAppliedState(declared(transitions)), 2);
    }

    function applyInterims(bytes32 head, uint256 count) internal returns (bytes32) {
        for (uint256 i = 0; i < count; i++) {
            bytes32 interim = keccak256(abi.encode(INTERIM, i));
            applyMigration(interim, head);
            head = interim;
        }
        return head;
    }

    function testOutOfOrderRefusalAfterALongHistoryIsNamed() external {
        deployRegistry();
        applyMigration(UPGRADE, applyInterims(MIGRATION_HEAD_GENESIS, 300));
        applyMigration(HANDOVER, UPGRADE);
        BeaconTransition[] memory transitions = upgradeThenHandover();
        (transitions[0], transitions[1]) = (transitions[1], transitions[0]);
        expectOutOfOrder(1);
        this.externalAppliedState(declared(transitions));
    }

    function testTransitionsALongHistoryApartAreInOrder() external {
        deployRegistry();
        applyMigration(UPGRADE, MIGRATION_HEAD_GENESIS);
        applyMigration(HANDOVER, applyInterims(UPGRADE, 300));
        assertEq(this.externalAppliedState(declared(upgradeThenHandover())), 2);
    }

    function declaredAt(address beacon) internal view returns (DeployBeacon memory) {
        DeployBeacon memory declaration = declared(new BeaconTransition[](0));
        declaration.beacon = beacon;
        declaration.beaconCodeHash = beacon.codehash;
        return declaration;
    }

    function twoStep() internal returns (MockOwnable2StepBeacon, DeployBeacon memory) {
        MockOwnable2StepBeacon beacon = new MockOwnable2StepBeacon(sImplementation, sOwner);
        DeployBeacon memory declaration = declaredAt(address(beacon));
        return (beacon, declaration);
    }

    function testTwoStepBeaconWithoutAPendingOwnerPasses() external {
        (, DeployBeacon memory declaration) = twoStep();
        this.externalCheckBeacon(declaration, sImplementation, sOwner);
    }

    function testBeaconWithAPendingOwnerIsRefused() external {
        (MockOwnable2StepBeacon beacon, DeployBeacon memory declaration) = twoStep();
        vm.prank(sOwner);
        beacon.transferOwnership(address(0xDEAD));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployBeacon.BeaconPendingOwner.selector, NETWORK, address(beacon), uint256(uint160(0xDEAD))
            )
        );
        this.externalCheckBeacon(declaration, sImplementation, sOwner);
    }

    function testBeaconWithTheSmallestPendingOwnerIsRefused() external {
        (MockOwnable2StepBeacon beacon, DeployBeacon memory declaration) = twoStep();
        vm.prank(sOwner);
        beacon.transferOwnership(address(1));
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeployBeacon.BeaconPendingOwner.selector, NETWORK, address(beacon), 1)
        );
        this.externalCheckBeacon(declaration, sImplementation, sOwner);
    }

    function testBeaconAnsweringPendingOwnerWithoutAWordPasses() external {
        MockFallbackBeacon beacon = new MockFallbackBeacon(sImplementation, sOwner, "", false);
        DeployBeacon memory declaration = declaredAt(address(beacon));
        this.externalCheckBeacon(declaration, sImplementation, sOwner);
    }

    function testBeaconAnsweringPendingOwnerWithTwoWordsIsRefused() external {
        MockFallbackBeacon beacon =
            new MockFallbackBeacon(sImplementation, sOwner, abi.encode(uint256(0xDEAD), uint256(0)), false);
        (bool success, bytes memory answer) = address(beacon).staticcall(abi.encodeWithSignature("pendingOwner()"));
        assertTrue(success);
        assertEq(answer.length, 0x40);
        (uint256 first,) = abi.decode(answer, (uint256, uint256));
        assertEq(first, 0xDEAD);
        DeployBeacon memory declaration = declaredAt(address(beacon));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployBeacon.BeaconPendingOwnerUnreadable.selector, NETWORK, address(beacon), answer
            )
        );
        this.externalCheckBeacon(declaration, sImplementation, sOwner);
    }

    function testBeaconAnsweringPendingOwnerWithLessThanAWordIsRefused() external {
        MockFallbackBeacon beacon = new MockFallbackBeacon(sImplementation, sOwner, new bytes(0x1f), false);
        (bool success, bytes memory answer) = address(beacon).staticcall(abi.encodeWithSignature("pendingOwner()"));
        assertTrue(success);
        assertEq(answer.length, 0x1f);
        DeployBeacon memory declaration = declaredAt(address(beacon));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployBeacon.BeaconPendingOwnerUnreadable.selector, NETWORK, address(beacon), answer
            )
        );
        this.externalCheckBeacon(declaration, sImplementation, sOwner);
    }

    function externalStateAt(DeployBeacon memory beacon, uint256 state) external pure returns (BeaconState memory) {
        return LibRainDeployBeacon.stateAt(beacon, state);
    }

    function testStateAtPastTheLastTransitionReverts() external {
        DeployBeacon memory beacon = declared(upgradeThenHandover());
        vm.expectRevert(stdError.indexOOBError);
        this.externalStateAt(beacon, 3);
    }

    function testBeaconRevertingPendingOwnerWithAWordPasses() external {
        MockFallbackBeacon beacon = new MockFallbackBeacon(sImplementation, sOwner, abi.encode(uint256(0xDEAD)), true);
        (bool success, bytes memory answer) = address(beacon).staticcall(abi.encodeWithSignature("pendingOwner()"));
        assertFalse(success);
        assertEq(answer.length, 0x20);
        assertEq(abi.decode(answer, (uint256)), 0xDEAD);
        DeployBeacon memory declaration = declaredAt(address(beacon));
        this.externalCheckBeacon(declaration, sImplementation, sOwner);
    }

    function testBeaconAnsweringPendingOwnerWithADirtyWordIsRefused() external {
        MockFallbackBeacon beacon =
            new MockFallbackBeacon(sImplementation, sOwner, abi.encode(uint256(1) << 160), false);
        DeployBeacon memory declaration = declaredAt(address(beacon));
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeployBeacon.BeaconPendingOwner.selector, NETWORK, address(beacon), 1 << 160)
        );
        this.externalCheckBeacon(declaration, sImplementation, sOwner);
    }

    function expectUnnamedSecondTransition(BeaconTransition[] memory transitions) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployBeacon.BeaconTransitionMigrationUnnamed.selector, block.chainid, address(sBeacon), 1
            )
        );
        this.externalAppliedState(declared(transitions));
    }

    function testTransitionWithAZeroWriterIsRefusedBeforeReadingTheRegistry() external {
        BeaconTransition[] memory transitions = upgradeThenHandover();
        transitions[1].migration.writer = address(0);
        expectUnnamedSecondTransition(transitions);
    }

    function testTransitionWithAZeroNamespaceIsRefusedBeforeReadingTheRegistry() external {
        BeaconTransition[] memory transitions = upgradeThenHandover();
        transitions[1].migration.namespace = bytes32(0);
        expectUnnamedSecondTransition(transitions);
    }

    function testTransitionWithAZeroMigrationIsRefusedBeforeReadingTheRegistry() external {
        BeaconTransition[] memory transitions = upgradeThenHandover();
        transitions[1].migration.migration = bytes32(0);
        expectUnnamedSecondTransition(transitions);
    }

    function testTransitionWithTheGenesisMigrationIsRefusedBeforeReadingTheRegistry() external {
        BeaconTransition[] memory transitions = upgradeThenHandover();
        transitions[1].migration.migration = MIGRATION_HEAD_GENESIS;
        expectUnnamedSecondTransition(transitions);
    }
}
