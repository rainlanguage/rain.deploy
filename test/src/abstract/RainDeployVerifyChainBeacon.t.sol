// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {
    BeaconState,
    BeaconTransition,
    ChainBeacon,
    DeployBeacon,
    LibRainDeployBeacon
} from "../../../src/lib/LibRainDeployBeacon.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {MIGRATION_HEAD_GENESIS, Prerequisite} from "../../../src/interface/IMigrationRegistryV3.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";
import {LibBeaconDeclarations} from "../../lib/LibBeaconDeclarations.sol";
import {LibBeaconTest} from "../../lib/LibBeaconTest.sol";
import {BeaconVerifyFixture} from "../../abstract/BeaconVerifyFixture.sol";
import {
    BeaconDeclaredTwice,
    BeaconNamedTwice,
    BeaconOnUncheckedNetwork,
    BeaconSeatedOwner,
    BeaconSuiteNotReleased,
    BeaconUnnamed,
    DerivedDeploy,
    ResolvedBeacon
} from "../../../src/abstract/RainDeployVerifyBase.sol";

/// @title RainDeployVerifyChainBeaconTest
/// @notice The chain group's check of each declared beacon against its network, state and implementation suite.
contract RainDeployVerifyChainBeaconTest is BeaconVerifyFixture, RainDeployVerifyChain {
    using LibBeaconDeclarations for ChainBeacon[];

    bytes32 constant ROLLBACK = keccak256("rollback");

    /// @inheritdoc RainDeploySuitesBase
    function beacons()
        internal
        view
        override(BeaconVerifyFixture, RainDeploySuitesBase)
        returns (ChainBeacon[] memory)
    {
        return BeaconVerifyFixture.beacons();
    }

    /// @inheritdoc RainDeploySuitesBase
    function supportedNetworks()
        internal
        view
        override(BeaconVerifyFixture, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return BeaconVerifyFixture.supportedNetworks();
    }

    function applyMigration() internal {
        applyMigration(MIGRATION, MIGRATION_HEAD_GENESIS);
    }

    function applyMigration(bytes32 migration, bytes32 head) internal {
        LibBeaconTest.applyMigration(vm, WRITER, NAMESPACE, migration, head);
    }

    function rollingBack() internal view returns (DeployBeacon memory) {
        DeployBeacon memory beacon = migrating("beacon-upgrade@0_0_1", OWNER);
        BeaconTransition[] memory transitions = new BeaconTransition[](2);
        transitions[0] = beacon.transitions[0];
        transitions[1] = BeaconTransition({
            migration: Prerequisite({writer: WRITER, namespace: NAMESPACE, migration: ROLLBACK}),
            state: BeaconState({implementation: "beacon-implementation@0_0_1", owner: NEW_OWNER})
        });
        beacon.transitions = transitions;
        return beacon;
    }

    function upgradeAndHandOver() internal {
        vm.startPrank(OWNER);
        UpgradeableBeacon(sBeacon).upgradeTo(sUpgrade);
        UpgradeableBeacon(sBeacon).transferOwnership(NEW_OWNER);
        vm.stopPrank();
    }

    /// External wrapper for `checkDeployedOnNetworks`, with no suites.
    /// @param networks The networks to check.
    function externalCheckDeployedOnNetworks(SupportedNetwork[] memory networks) external {
        checkDeployedOnNetworks(networks, new DeploySuite[](0));
    }

    /// External wrapper for `checkDeployedOnSupportedNetworks`, with no suites.
    function externalCheckDeployedOnSupportedNetworks() external {
        checkDeployedOnSupportedNetworks(new DeploySuite[](0));
    }

    function expectUnexpected(uint256 index, address expected, address actual) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector,
                LibRainDeploy.ARBITRUM_ONE,
                sBeacon,
                index,
                expected,
                actual
            )
        );
    }

    function testChainGroupPassesABeaconAtItsInitialState() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testChainGroupChecksABeaconOnTheFirstNetworkWithoutSuites() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", NEW_OWNER));
        expectUnexpected(1, NEW_OWNER, OWNER);
        this.externalCheckDeployedOnNetworks(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE));
    }

    function testChainGroupWithoutSuitesForksOnlyTheBeaconsNetworks() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        this.externalCheckDeployedOnNetworks(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE));
        assertEq(block.chainid, 42161);
        (bool extraFork,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(1)));
        assertFalse(extraFork);
    }

    function testBeaconNetworksKeepsTheBeaconsNetworksInOrder() external {
        sBeacons.declare(8453, declared("beacon-implementation@0_0_1", OWNER));
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        sBeacons.declare(8453, atASecondBeaconUnchecked());
        string[] memory names = new string[](3);
        names[0] = LibRainDeploy.ARBITRUM_ONE;
        names[1] = LibRainDeploy.POLYGON;
        names[2] = LibRainDeploy.BASE;
        SupportedNetwork[] memory networks = LibRainDeploy.declaredNetworkConfigs(names);
        SupportedNetwork[] memory onBeacons = beaconNetworks(networks, resolveBeacons(networks));
        assertEq(onBeacons.length, 2);
        assertEq(onBeacons[0].name, LibRainDeploy.ARBITRUM_ONE);
        assertEq(onBeacons[0].chainId, 42161);
        assertEq(onBeacons[1].name, LibRainDeploy.BASE);
        assertEq(onBeacons[1].chainId, 8453);
    }

    /// @return A second beacon at the implementation suite, owned by `OWNER`, named by address.
    function atASecondBeaconUnchecked() internal returns (DeployBeacon memory) {
        DeployBeacon memory beacon = declared("beacon-implementation@0_0_1", OWNER);
        beacon.beacon = address(new UpgradeableBeacon(sImplementation, OWNER));
        return beacon;
    }

    function testChainGroupChecksEachNetworksOwnBeacons() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        DeployBeacon memory missing = declared("beacon-implementation@0_0_1", OWNER);
        missing.beacon = address(0xBEAC0);
        sBeacons.declare(8453, missing);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.BASE, address(0xBEAC0))
        );
        this.externalCheckDeployedOnNetworks(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE));
    }

    function atASecondBeacon(address owner) internal returns (DeployBeacon memory) {
        DeployBeacon memory beacon = declared("beacon-implementation@0_0_1", owner);
        beacon.beacon = address(new UpgradeableBeacon(sImplementation, OWNER));
        vm.makePersistent(beacon.beacon);
        return beacon;
    }

    function testChainGroupChecksEveryBeaconOnANetwork() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        DeployBeacon memory second = atASecondBeacon(NEW_OWNER);
        sBeacons.declare(42161, second);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector,
                LibRainDeploy.ARBITRUM_ONE,
                second.beacon,
                1,
                NEW_OWNER,
                OWNER
            )
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testABeaconBeforeAValidOneOnItsNetworkIsChecked() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", NEW_OWNER));
        sBeacons.declare(42161, atASecondBeacon(OWNER));
        expectUnexpected(1, NEW_OWNER, OWNER);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testEachBeaconOnANetworkIsCheckedAtItsOwnImplementation() external {
        address second = address(new UpgradeableBeacon(sUpgrade, OWNER));
        vm.makePersistent(second);
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        DeployBeacon memory other = declared("beacon-upgrade@0_0_1", OWNER);
        other.beacon = second;
        sBeacons.declare(42161, other);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconMustPointAtTheDeclaredSuitesAddress() external {
        sBeacons.declare(42161, declared("beacon-upgrade@0_0_1", OWNER));
        expectUnexpected(0, sUpgrade, sImplementation);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testUnknownImplementationSuiteIsRefused() external {
        sBeacons.declare(42161, declared("no-such-suite", OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconSuiteNotReleased.selector, "no-such-suite"));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testCandidateImplementationSuiteIsRefused() external {
        sBeacons.declare(42161, declared("beacon-implementation", OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconSuiteNotReleased.selector, "beacon-implementation"));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testCandidateImplementationSuiteInALaterStateIsRefused() external {
        sBeacons.declare(42161, migrating("beacon-implementation", OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconSuiteNotReleased.selector, "beacon-implementation"));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testImplementationSuitesMissingDependencyIsRefused() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        vm.etch(DEPENDENCY, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, DEPENDENCY)
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testImplementationSuitesChangedDependencyIsRefused() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        vm.etch(DEPENDENCY, hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.DependencyChanged.selector,
                LibRainDeploy.ARBITRUM_ONE,
                DEPENDENCY,
                keccak256(DEPENDENCY_CODE),
                keccak256(hex"01")
            )
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testAppliedStatesDependencyIsChecked() external {
        DeployBeacon memory beacon = migrating("beacon-implementation@0_0_1", OWNER);
        beacon.initial.implementation = "beacon-upgrade@0_0_1";
        sBeacons.declare(42161, beacon);
        applyMigration();
        vm.etch(DEPENDENCY, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, DEPENDENCY)
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testEachImplementationIsHeldToItsOwnDependencies() external {
        DeployBeacon memory beacon = declared("beacon-upgrade@0_0_1", OWNER);
        beacon.beacon = address(new UpgradeableBeacon(sUpgrade, OWNER));
        vm.makePersistent(beacon.beacon);
        sBeacons.declare(42161, beacon);
        vm.etch(DEPENDENCY, hex"");
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconsSharingAnImplementationPassOnEveryNetwork() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        sBeacons.declare(8453, declared("beacon-implementation@0_0_1", OWNER));
        this.externalCheckDeployedOnNetworks(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE));
    }

    function testImplementationSuiteWithoutCodeIsNotDeployed() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        vm.etch(sImplementation, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.ARBITRUM_ONE, sImplementation
            )
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testImplementationSuiteMustHaveItsDerivedCode() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        bytes32 derived = sImplementation.codehash;
        vm.etch(sImplementation, type(MockDeployable).runtimeCode);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.CodeHashMismatchOnNetwork.selector,
                LibRainDeploy.ARBITRUM_ONE,
                sImplementation,
                derived,
                sUpgrade.codehash
            )
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testUnappliedMigrationExpectsTheInitialState() external {
        sBeacons.declare(42161, migrating("beacon-upgrade@0_0_1", NEW_OWNER));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testChainAheadOfTheRegistryIsRefused() external {
        sBeacons.declare(42161, migrating("beacon-upgrade@0_0_1", NEW_OWNER));
        upgradeAndHandOver();
        expectUnexpected(0, sImplementation, sUpgrade);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testAppliedMigrationExpectsItsTransition() external {
        sBeacons.declare(42161, migrating("beacon-upgrade@0_0_1", NEW_OWNER));
        applyMigration();
        upgradeAndHandOver();
        vm.etch(sImplementation, hex"");
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testAppliedUpgradeMissingFromTheChainIsRefused() external {
        sBeacons.declare(42161, migrating("beacon-upgrade@0_0_1", OWNER));
        applyMigration();
        expectUnexpected(0, sUpgrade, sImplementation);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testAppliedHandOverMissingFromTheChainIsRefused() external {
        sBeacons.declare(42161, migrating("beacon-implementation@0_0_1", NEW_OWNER));
        applyMigration();
        expectUnexpected(1, NEW_OWNER, OWNER);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testAppliedUpgradeChecksTheUpgradedSuiteIsLive() external {
        sBeacons.declare(42161, migrating("beacon-upgrade@0_0_1", NEW_OWNER));
        applyMigration();
        upgradeAndHandOver();
        vm.etch(sUpgrade, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.ARBITRUM_ONE, sUpgrade)
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testChainGroupChecksABeaconOnlyOnALaterNetworkWithoutSuites() external {
        sBeacons.declare(8453, declared("beacon-implementation@0_0_1", NEW_OWNER));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector, LibRainDeploy.BASE, sBeacon, 1, NEW_OWNER, OWNER
            )
        );
        this.externalCheckDeployedOnNetworks(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE));
    }

    function testBeaconOnAnUncheckedCatalogueNetworkIsRefused() external {
        supportOnly(LibRainDeploy.ARBITRUM_ONE, "");
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        sBeacons.declare(1, declared("beacon-implementation@0_0_1", OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconOnUncheckedNetwork.selector, 1, 1));
        this.externalCheckDeployedOnSupportedNetworks();
        LibBeaconTest.assertNoFork(vm, "forked before refusing a beacon on an unchecked network");
    }

    function testBeaconOnAChainIdOutsideTheCatalogueIsRefused() external {
        sBeacons.declare(42162, declared("beacon-implementation@0_0_1", OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconOnUncheckedNetwork.selector, 42162, 0));
        this.externalCheckDeployedOnSupportedNetworks();
        LibBeaconTest.assertNoFork(vm, "forked before refusing a beacon outside the catalogue");
    }

    function testOneDeclarationSharedByTwoChainsResolvesOnEach() external {
        sBeacons.declare(42161, bySuite("beacon@0_0_1", OWNER));
        sBeacons.declare(8453, bySuite("beacon@0_0_1", NEW_OWNER));
        sShareFirstBeacon = true;
        this.externalCheckDeployedOnNetworks(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE));
    }

    /// External wrapper for `checkDeployedOnNetworks`, with the released suites.
    /// @param networks The networks to check.
    function externalCheckReleasedOnNetworks(SupportedNetwork[] memory networks) external {
        checkDeployedOnNetworks(networks, releasedSuites());
    }

    function testReleasedSuitesBeaconsNameAreDerivedOnceInTheChainCheck() external {
        sBeacons.declare(42161, migrating("beacon-upgrade@0_0_1", OWNER));
        sBeacons.declare(42161, bySuite("beacon@0_0_1", OWNER));
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, type(MockDeployableV2).creationCode, 1);
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, type(MockDeployable).creationCode, 1);
        // One derivation, one seated-state deploy.
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, beaconCreationCode(), 2);
        this.externalCheckReleasedOnNetworks(arbitrum());
    }

    function testReleasedSuiteABeaconImplementsIsDerivedOnceInTheChainCheck() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, type(MockDeployableV2).creationCode, 1);
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, type(MockDeployable).creationCode, 1);
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, beaconCreationCode(), 1);
        this.externalCheckReleasedOnNetworks(arbitrum());
    }

    function testBeaconsOnEveryCheckedNetworkAreAccepted() external {
        supportOnly(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE);
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        sBeacons.declare(8453, declared("beacon-implementation@0_0_1", OWNER));
        this.externalCheckDeployedOnSupportedNetworks();
    }

    function testBeaconNamedBySuitePassesAtItsDerivedAddress() external {
        sBeacons.declare(42161, bySuite("beacon@0_0_1", OWNER));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconNamedBySuiteIsReadAtItsDerivedAddress() external {
        sBeacons.declare(42161, bySuite("beacon@0_0_1", OWNER));
        vm.prank(OWNER);
        UpgradeableBeacon(sSuiteBeacon).transferOwnership(NEW_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector,
                LibRainDeploy.ARBITRUM_ONE,
                sSuiteBeacon,
                1,
                OWNER,
                NEW_OWNER
            )
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconSuiteSeatingAnotherOwnerIsRefusedBeforeForking() external {
        sBeacons.declare(42161, bySuite("beacon@0_0_1", NEW_OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconSeatedOwner.selector, 42161, 0, abi.encode(OWNER)));
        this.externalCheckDeployedOnNetworks(arbitrum());
        LibBeaconTest.assertNoFork(vm, "forked before refusing a beacon suite seating another owner");
    }

    function testBeaconSuiteMustHaveItsDerivedCode() external {
        sBeacons.declare(42161, bySuite("beacon@0_0_1", OWNER));
        bytes32 derived = sSuiteBeacon.codehash;
        vm.etch(sSuiteBeacon, type(MockDeployable).runtimeCode);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.CodeHashMismatchOnNetwork.selector,
                LibRainDeploy.ARBITRUM_ONE,
                sSuiteBeacon,
                derived,
                sUpgrade.codehash
            )
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconSuitesMissingDependencyIsRefused() external {
        sBeacons.declare(42161, bySuite("beacon@0_0_1", OWNER));
        vm.etch(BEACON_DEPENDENCY, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, BEACON_DEPENDENCY
            )
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testCandidateBeaconSuiteIsRefused() external {
        sBeacons.declare(42161, bySuite("beacon-implementation", OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconSuiteNotReleased.selector, "beacon-implementation"));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconNamedBySuiteAndAddressIsRefused() external {
        DeployBeacon memory beacon = bySuite("beacon@0_0_1", OWNER);
        beacon.beacon = sSuiteBeacon;
        sBeacons.declare(42161, beacon);
        vm.expectRevert(abi.encodeWithSelector(BeaconNamedTwice.selector, 42161, 0));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconNamedBySuiteAndCodeHashIsRefused() external {
        DeployBeacon memory beacon = bySuite("beacon@0_0_1", OWNER);
        beacon.beaconCodeHash = sSuiteBeacon.codehash;
        sBeacons.declare(42161, beacon);
        vm.expectRevert(abi.encodeWithSelector(BeaconNamedTwice.selector, 42161, 0));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testUnnamedBeaconIsRefused() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        DeployBeacon memory unnamed = declared("beacon-implementation@0_0_1", OWNER);
        unnamed.beacon = address(0);
        unnamed.beaconCodeHash = bytes32(0);
        sBeacons.declare(42161, unnamed);
        vm.expectRevert(abi.encodeWithSelector(BeaconUnnamed.selector, 42161, 1));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconNamedByAddressAloneIsRefused() external {
        DeployBeacon memory beacon = declared("beacon-implementation@0_0_1", OWNER);
        beacon.beaconCodeHash = bytes32(0);
        sBeacons.declare(42161, beacon);
        vm.expectRevert(abi.encodeWithSelector(BeaconUnnamed.selector, 42161, 0));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconNamedByCodeHashAloneIsRefused() external {
        DeployBeacon memory beacon = declared("beacon-implementation@0_0_1", OWNER);
        beacon.beacon = address(0);
        sBeacons.declare(42161, beacon);
        vm.expectRevert(abi.encodeWithSelector(BeaconUnnamed.selector, 42161, 0));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconNamedTwiceBehindAValidBeaconReportsItsIndex() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        DeployBeacon memory twice = bySuite("beacon@0_0_1", OWNER);
        twice.beacon = sSuiteBeacon;
        sBeacons.declare(42161, twice);
        vm.expectRevert(abi.encodeWithSelector(BeaconNamedTwice.selector, 42161, 1));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testNarrowedCheckAcceptsABeaconOnAnotherSupportedNetwork() external {
        supportOnly(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE);
        sBeacons.declare(8453, declared("beacon-implementation@0_0_1", NEW_OWNER));
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testTransitionsAppliedInDeclaredOrderExpectTheLatest() external {
        sBeacons.declare(42161, rollingBack());
        applyMigration();
        vm.warp(block.timestamp + 1);
        applyMigration(ROLLBACK, MIGRATION);
        vm.prank(OWNER);
        UpgradeableBeacon(sBeacon).transferOwnership(NEW_OWNER);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testTransitionsAppliedInDeclaredOrderHoldTheLatestNotTheInitialState() external {
        sBeacons.declare(42161, rollingBack());
        applyMigration();
        vm.warp(block.timestamp + 1);
        applyMigration(ROLLBACK, MIGRATION);
        expectUnexpected(1, NEW_OWNER, OWNER);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testTransitionsAppliedOutOfDeclaredOrderAreRefusedOnTheNetwork() external {
        sBeacons.declare(42161, rollingBack());
        applyMigration(ROLLBACK, MIGRATION_HEAD_GENESIS);
        vm.warp(block.timestamp + 1);
        applyMigration(MIGRATION, ROLLBACK);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployBeacon.BeaconTransitionsOutOfOrder.selector, LibRainDeploy.ARBITRUM_ONE, sBeacon, 1
            )
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testNarrowedCheckWithNoBeaconOnItsNetworksForksNothing() external {
        sBeacons.declare(8453, declared("beacon-implementation@0_0_1", OWNER));
        this.externalCheckDeployedOnNetworks(arbitrum());
        LibBeaconTest.assertNoFork(vm, "forked a network with no beacon and no suite to check");
    }

    function testMalformedTransitionMigrationIsRefusedBeforeForking() external {
        DeployBeacon memory beacon = migrating("beacon-upgrade@0_0_1", OWNER);
        beacon.transitions[0].migration.writer = address(0);
        sBeacons.declare(42161, beacon);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeployBeacon.BeaconTransitionMigrationUnnamed.selector, 42161, sBeacon, 0)
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
        LibBeaconTest.assertNoFork(vm, "forked before refusing an unnamed transition migration");
    }

    function testBeaconDeclaredTwiceOnANetworkIsRefusedBeforeForking() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", NEW_OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconDeclaredTwice.selector, 42161, 1));
        this.externalCheckDeployedOnNetworks(arbitrum());
        LibBeaconTest.assertNoFork(vm, "forked before refusing a beacon declared twice");
    }

    function testBeaconNamedBySuiteAndAgainByItsAddressIsDeclaredTwice() external {
        sBeacons.declare(42161, bySuite("beacon@0_0_1", OWNER));
        DeployBeacon memory again = declared("beacon-implementation@0_0_1", OWNER);
        again.beacon = sSuiteBeacon;
        again.beaconCodeHash = sSuiteBeacon.codehash;
        sBeacons.declare(42161, again);
        vm.expectRevert(abi.encodeWithSelector(BeaconDeclaredTwice.selector, 42161, 1));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    /// External wrapper for `deriveUnlessResolved`, against the beacons resolved on `networks`.
    /// @param candidate The suite to derive.
    /// @param networks The networks whose beacons to resolve.
    /// @return The derivation.
    function externalDeriveUnlessResolved(DeploySuite memory candidate, SupportedNetwork[] memory networks)
        external
        returns (DerivedDeploy memory)
    {
        ResolvedBeacon[] memory resolved = resolveBeacons(networks);
        return deriveUnlessResolved(onSupportedNetworks(candidate), resolved);
    }

    function testSuiteWithAResolvedKeyButOtherCodeIsDerivedAfresh() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        DeploySuite memory other = LibBeaconTest.zoltuSuite(
            "beacon-implementation@0_0_1",
            type(MockDeployable).creationCode,
            type(MockDeployable).runtimeCode,
            "test/concrete/MockDeployable.sol:MockDeployable"
        );
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, type(MockDeployableV2).creationCode, 1);
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, type(MockDeployable).creationCode, 1);
        DerivedDeploy memory derived = this.externalDeriveUnlessResolved(other, arbitrum());
        assertEq(derived.bytecodeHash, keccak256(type(MockDeployable).runtimeCode));
    }

    function testSuiteWithAResolvedKeyButOtherDependenciesIsDerivedAfresh() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        DeploySuite memory other = releasedSuites()[0];
        other.dependencies[0].runtimeCode = hex"03";
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, type(MockDeployableV2).creationCode, 2);
        this.externalDeriveUnlessResolved(other, arbitrum());
    }

    function testSuiteResolvedByABeaconIsNotDerivedAgain() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, type(MockDeployableV2).creationCode, 1);
        DerivedDeploy memory derived = this.externalDeriveUnlessResolved(releasedSuites()[0], arbitrum());
        assertEq(derived.bytecodeHash, keccak256(type(MockDeployableV2).runtimeCode));
    }

    function testUnsetSuiteOfABeaconNamedByAddressIsNotReused() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        DeploySuite memory unset;
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, true, LibRainDeploy.zoltuAddress(""))
        );
        this.externalDeriveUnlessResolved(unset, arbitrum());
    }

    /// External wrapper for `checkBeaconsOnNetwork`, against the beacons resolved on `networks`, with no fork: the
    /// subjects are local and persistent, and no fork is needed to read them.
    /// @param networks The networks whose beacons to resolve.
    /// @param networkIndex The index in `networks` of the network to check.
    function externalCheckBeaconsOnNetwork(SupportedNetwork[] memory networks, uint256 networkIndex) external {
        ResolvedBeacon[] memory resolved = resolveBeacons(networks);
        checkBeaconsOnNetwork(networks[networkIndex], resolved);
    }

    function testAppliedMigrationExpectsItsTransitionOffline() external {
        sBeacons.declare(42161, migrating("beacon-upgrade@0_0_1", NEW_OWNER));
        applyMigration();
        upgradeAndHandOver();
        vm.etch(sImplementation, hex"");
        this.externalCheckBeaconsOnNetwork(arbitrum(), 0);
    }

    function testAppliedUpgradeChecksTheUpgradedSuiteIsLiveOffline() external {
        sBeacons.declare(42161, migrating("beacon-upgrade@0_0_1", NEW_OWNER));
        applyMigration();
        upgradeAndHandOver();
        vm.etch(sUpgrade, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.ARBITRUM_ONE, sUpgrade)
        );
        this.externalCheckBeaconsOnNetwork(arbitrum(), 0);
    }

    function testAppliedStatesDependencyIsCheckedOffline() external {
        DeployBeacon memory beacon = migrating("beacon-implementation@0_0_1", OWNER);
        beacon.initial.implementation = "beacon-upgrade@0_0_1";
        sBeacons.declare(42161, beacon);
        applyMigration();
        vm.etch(DEPENDENCY, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, DEPENDENCY)
        );
        this.externalCheckBeaconsOnNetwork(arbitrum(), 0);
    }

    function testAppliedUpgradeMissingFromTheChainIsRefusedOffline() external {
        sBeacons.declare(42161, migrating("beacon-upgrade@0_0_1", OWNER));
        applyMigration();
        expectUnexpected(0, sUpgrade, sImplementation);
        this.externalCheckBeaconsOnNetwork(arbitrum(), 0);
    }

    function testTransitionsAppliedInDeclaredOrderHoldTheLatestNotTheInitialStateOffline() external {
        sBeacons.declare(42161, rollingBack());
        applyMigration();
        vm.warp(block.timestamp + 1);
        applyMigration(ROLLBACK, MIGRATION);
        expectUnexpected(1, NEW_OWNER, OWNER);
        this.externalCheckBeaconsOnNetwork(arbitrum(), 0);
    }

    function testUnappliedMigrationExpectsTheInitialStateOffline() external {
        sBeacons.declare(42161, migrating("beacon-upgrade@0_0_1", NEW_OWNER));
        this.externalCheckBeaconsOnNetwork(arbitrum(), 0);
    }

    function testBeaconNamedBySuitePassesAtItsDerivedAddressOffline() external {
        sBeacons.declare(42161, bySuite("beacon@0_0_1", OWNER));
        this.externalCheckBeaconsOnNetwork(arbitrum(), 0);
    }

    function testBeaconSuitesMissingDependencyIsRefusedOffline() external {
        sBeacons.declare(42161, bySuite("beacon@0_0_1", OWNER));
        vm.etch(BEACON_DEPENDENCY, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, BEACON_DEPENDENCY
            )
        );
        this.externalCheckBeaconsOnNetwork(arbitrum(), 0);
    }

    function testABeaconOnAnotherNetworkIsNotCheckedOnThisOneOffline() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", NEW_OWNER));
        this.externalCheckBeaconsOnNetwork(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE), 1);
        expectUnexpected(1, NEW_OWNER, OWNER);
        this.externalCheckBeaconsOnNetwork(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE), 0);
    }

    function testEveryBeaconOnANetworkIsCheckedOffline() external {
        sBeacons.declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        DeployBeacon memory missing = declared("beacon-implementation@0_0_1", OWNER);
        missing.beacon = address(0xBEAC0);
        sBeacons.declare(42161, missing);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.ARBITRUM_ONE, address(0xBEAC0)
            )
        );
        this.externalCheckBeaconsOnNetwork(arbitrum(), 0);
    }

    function testBeaconSuiteResolvedByABeaconIsNotDerivedAgain() external {
        sBeacons.declare(42161, bySuite("beacon@0_0_1", OWNER));
        // One derivation, one seated-state deploy.
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, beaconCreationCode(), 2);
        DerivedDeploy memory derived = this.externalDeriveUnlessResolved(releasedSuites()[2], arbitrum());
        assertEq(derived.bytecodeHash, sSuiteBeacon.codehash);
    }
}
