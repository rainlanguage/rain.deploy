// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {
    DeployCandidate,
    DeployDependency,
    DeployMechanism,
    DeploySuite
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    BeaconNamedTwice,
    BeaconOnUncheckedNetwork,
    BeaconSuiteNotReleased,
    BeaconUnnamed,
    RainDeployVerifyChain
} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {BeaconState, BeaconTransition, ChainBeacon, DeployBeacon} from "../../../src/lib/LibRainDeployBeacon.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {
    IMigrationRegistryV2,
    MIGRATION_HEAD_GENESIS,
    Prerequisite
} from "../../../src/interface/IMigrationRegistryV2.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";

contract RainDeployVerifyChainBeaconTest is RainDeployVerifyChain {
    address constant OWNER = address(0xB0B);
    address constant NEW_OWNER = address(0xCAFE);
    address constant WRITER = address(0x5AFE);
    bytes32 constant NAMESPACE = keccak256("beacons");
    bytes32 constant MIGRATION = keccak256("migration");
    address constant DEPENDENCY = address(0xDE9);
    bytes constant DEPENDENCY_CODE = hex"00";
    address constant BEACON_DEPENDENCY = address(0xBDE9);
    bytes constant BEACON_DEPENDENCY_CODE = hex"02";

    ChainBeacon[] internal sBeacons;
    address internal sBeacon;
    address internal sImplementation;
    address internal sUpgrade;
    address internal sRegistry;
    address internal sSuiteBeacon;
    string[] internal sSupported;

    function suite(string memory key, bytes memory creationCode, bytes memory runtimeCode, string memory artifactPath)
        internal
        pure
        returns (DeploySuite memory)
    {
        return DeploySuite({
            suite: key,
            creationCode: creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(creationCode),
            storedBytecodeHash: keccak256(runtimeCode),
            storedRuntimeCode: runtimeCode,
            artifactPath: artifactPath,
            dependencies: new DeployDependency[](0),
            mechanism: DeployMechanism.Zoltu,
            mechanismData: ""
        });
    }

    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory released = new DeploySuite[](3);
        released[0] = suite(
            "beacon-implementation@0_0_1",
            type(MockDeployableV2).creationCode,
            type(MockDeployableV2).runtimeCode,
            "test/concrete/MockDeployableV2.sol:MockDeployableV2"
        );
        released[0].dependencies = new DeployDependency[](1);
        released[0].dependencies[0] = DeployDependency({deployedAddress: DEPENDENCY, runtimeCode: DEPENDENCY_CODE});
        released[1] = suite(
            "beacon-upgrade@0_0_1",
            type(MockDeployable).creationCode,
            type(MockDeployable).runtimeCode,
            "test/concrete/MockDeployable.sol:MockDeployable"
        );
        released[2] = suite(
            "beacon@0_0_1",
            beaconCreationCode(),
            type(UpgradeableBeacon).runtimeCode,
            "dependencies/@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol:UpgradeableBeacon"
        );
        released[2].dependencies = new DeployDependency[](1);
        released[2].dependencies[0] =
            DeployDependency({deployedAddress: BEACON_DEPENDENCY, runtimeCode: BEACON_DEPENDENCY_CODE});
        return released;
    }

    function candidateSuites() internal pure override returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({
            snapshot: suite(
                "beacon-implementation",
                type(MockDeployableV2).creationCode,
                type(MockDeployableV2).runtimeCode,
                "test/concrete/MockDeployableV2.sol:MockDeployableV2"
            ),
            unanchorableReason: ""
        });
        return candidates;
    }

    function beaconCreationCode() internal pure returns (bytes memory) {
        return abi.encodePacked(
            type(UpgradeableBeacon).creationCode,
            abi.encode(LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode), OWNER)
        );
    }

    function beacons() internal view override returns (ChainBeacon[] memory) {
        return sBeacons;
    }

    function supportedNetworks() internal view override returns (string[] memory) {
        return sSupported;
    }

    function setUp() external {
        sImplementation = LibRainDeploy.etchAndDeployZoltu(vm, type(MockDeployableV2).creationCode);
        sUpgrade = LibRainDeploy.etchAndDeployZoltu(vm, type(MockDeployable).creationCode);
        sBeacon = address(new UpgradeableBeacon(sImplementation, OWNER));
        sRegistry = LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
        vm.etch(DEPENDENCY, DEPENDENCY_CODE);
        vm.makePersistent(sImplementation, sUpgrade, sBeacon);
        vm.makePersistent(sRegistry, DEPENDENCY);
        sSuiteBeacon = LibRainDeploy.etchAndDeployZoltu(vm, beaconCreationCode());
        vm.etch(BEACON_DEPENDENCY, BEACON_DEPENDENCY_CODE);
        vm.makePersistent(sSuiteBeacon, BEACON_DEPENDENCY);
        string[] memory supported = LibRainDeploy.supportedNetworks();
        for (uint256 i = 0; i < supported.length; i++) {
            sSupported.push(supported[i]);
        }
    }

    function declared(string memory implementation, address owner) internal view returns (DeployBeacon memory) {
        return DeployBeacon({
            beaconSuite: "",
            beacon: sBeacon,
            beaconCodeHash: sBeacon.codehash,
            initial: BeaconState({implementation: implementation, owner: owner}),
            transitions: new BeaconTransition[](0)
        });
    }

    function migrating(string memory implementation, address owner) internal view returns (DeployBeacon memory) {
        DeployBeacon memory beacon = declared("beacon-implementation@0_0_1", OWNER);
        beacon.transitions = new BeaconTransition[](1);
        beacon.transitions[0] = BeaconTransition({
            migration: Prerequisite({writer: WRITER, namespace: NAMESPACE, migration: MIGRATION}),
            state: BeaconState({implementation: implementation, owner: owner})
        });
        return beacon;
    }

    function declare(uint256 chainId, DeployBeacon memory beacon) internal {
        ChainBeacon storage chainBeacon = sBeacons.push();
        chainBeacon.chainId = chainId;
        DeployBeacon storage stored = chainBeacon.beacon;
        stored.beaconSuite = beacon.beaconSuite;
        stored.beacon = beacon.beacon;
        stored.beaconCodeHash = beacon.beaconCodeHash;
        stored.initial = beacon.initial;
        for (uint256 i = 0; i < beacon.transitions.length; i++) {
            stored.transitions.push(beacon.transitions[i]);
        }
    }

    function applyMigration() internal {
        vm.prank(WRITER);
        IMigrationRegistryV2(sRegistry)
            .applyMigration(NAMESPACE, MIGRATION, LibMigrationRegistry.onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS));
    }

    function upgradeAndHandOver() internal {
        vm.startPrank(OWNER);
        UpgradeableBeacon(sBeacon).upgradeTo(sUpgrade);
        UpgradeableBeacon(sBeacon).transferOwnership(NEW_OWNER);
        vm.stopPrank();
    }

    function networksNamed(string memory first, string memory second)
        internal
        pure
        returns (SupportedNetwork[] memory)
    {
        string[] memory names = new string[](bytes(second).length == 0 ? 1 : 2);
        names[0] = first;
        if (names.length == 2) {
            names[1] = second;
        }
        return LibRainDeploy.declaredNetworkConfigs(names);
    }

    function externalCheckDeployedOnNetworks(SupportedNetwork[] memory networks) external {
        checkDeployedOnNetworks(networks, new DeploySuite[](0));
    }

    function externalResolveBeacons(SupportedNetwork[] memory networks) external {
        resolveBeacons(networks);
    }

    function externalCheckDeployedOnSupportedNetworks() external {
        checkDeployedOnSupportedNetworks(new DeploySuite[](0));
    }

    function supportOnly(string memory first, string memory second) internal {
        delete sSupported;
        sSupported.push(first);
        if (bytes(second).length > 0) {
            sSupported.push(second);
        }
    }

    function bySuite(string memory beaconSuite, address owner) internal view returns (DeployBeacon memory) {
        DeployBeacon memory beacon = declared("beacon-implementation@0_0_1", owner);
        beacon.beaconSuite = beaconSuite;
        beacon.beacon = address(0);
        beacon.beaconCodeHash = bytes32(0);
        return beacon;
    }

    function arbitrum() internal pure returns (SupportedNetwork[] memory) {
        return networksNamed(LibRainDeploy.ARBITRUM_ONE, "");
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
        declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testChainGroupChecksBeaconsOnAnyNetworkWithoutSuites() external {
        declare(42161, declared("beacon-implementation@0_0_1", NEW_OWNER));
        expectUnexpected(1, NEW_OWNER, OWNER);
        this.externalCheckDeployedOnNetworks(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE));
    }

    function testChainGroupChecksEachNetworksOwnBeacons() external {
        declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        DeployBeacon memory missing = declared("beacon-implementation@0_0_1", OWNER);
        missing.beacon = address(0xBEAC0);
        declare(8453, missing);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.BASE, address(0xBEAC0))
        );
        this.externalCheckDeployedOnNetworks(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE));
    }

    function testChainGroupChecksEveryBeaconOnANetwork() external {
        declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        declare(42161, declared("beacon-implementation@0_0_1", NEW_OWNER));
        expectUnexpected(1, NEW_OWNER, OWNER);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testEachBeaconOnANetworkIsCheckedAtItsOwnImplementation() external {
        address second = address(new UpgradeableBeacon(sUpgrade, OWNER));
        vm.makePersistent(second);
        declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        DeployBeacon memory other = declared("beacon-upgrade@0_0_1", OWNER);
        other.beacon = second;
        declare(42161, other);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconMustPointAtTheDeclaredSuitesAddress() external {
        declare(42161, declared("beacon-upgrade@0_0_1", OWNER));
        expectUnexpected(0, sUpgrade, sImplementation);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testUnknownImplementationSuiteIsRefused() external {
        declare(42161, declared("no-such-suite", OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconSuiteNotReleased.selector, "no-such-suite"));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testCandidateImplementationSuiteIsRefused() external {
        declare(42161, declared("beacon-implementation", OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconSuiteNotReleased.selector, "beacon-implementation"));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testCandidateImplementationSuiteInALaterStateIsRefused() external {
        declare(42161, migrating("beacon-implementation", OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconSuiteNotReleased.selector, "beacon-implementation"));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testImplementationSuitesMissingDependencyIsRefused() external {
        declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        vm.etch(DEPENDENCY, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, DEPENDENCY)
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testImplementationSuitesChangedDependencyIsRefused() external {
        declare(42161, declared("beacon-implementation@0_0_1", OWNER));
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
        declare(42161, beacon);
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
        declare(42161, beacon);
        vm.etch(DEPENDENCY, hex"");
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconsSharingAnImplementationPassOnEveryNetwork() external {
        declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        declare(8453, declared("beacon-implementation@0_0_1", OWNER));
        this.externalCheckDeployedOnNetworks(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE));
    }

    function testImplementationSuiteWithoutCodeIsNotDeployed() external {
        declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        vm.etch(sImplementation, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.ARBITRUM_ONE, sImplementation
            )
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testImplementationSuiteMustHaveItsDerivedCode() external {
        declare(42161, declared("beacon-implementation@0_0_1", OWNER));
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
        declare(42161, migrating("beacon-upgrade@0_0_1", NEW_OWNER));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testChainAheadOfTheRegistryIsRefused() external {
        declare(42161, migrating("beacon-upgrade@0_0_1", NEW_OWNER));
        upgradeAndHandOver();
        expectUnexpected(0, sImplementation, sUpgrade);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testAppliedMigrationExpectsItsTransition() external {
        declare(42161, migrating("beacon-upgrade@0_0_1", NEW_OWNER));
        applyMigration();
        upgradeAndHandOver();
        vm.etch(sImplementation, hex"");
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testAppliedUpgradeMissingFromTheChainIsRefused() external {
        declare(42161, migrating("beacon-upgrade@0_0_1", OWNER));
        applyMigration();
        expectUnexpected(0, sUpgrade, sImplementation);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testAppliedHandOverMissingFromTheChainIsRefused() external {
        declare(42161, migrating("beacon-implementation@0_0_1", NEW_OWNER));
        applyMigration();
        expectUnexpected(1, NEW_OWNER, OWNER);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testAppliedUpgradeChecksTheUpgradedSuiteIsLive() external {
        declare(42161, migrating("beacon-upgrade@0_0_1", NEW_OWNER));
        applyMigration();
        upgradeAndHandOver();
        vm.etch(sUpgrade, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.ARBITRUM_ONE, sUpgrade)
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testChainGroupChecksABeaconOnlyOnALaterNetworkWithoutSuites() external {
        declare(8453, declared("beacon-implementation@0_0_1", NEW_OWNER));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector, LibRainDeploy.BASE, sBeacon, 1, NEW_OWNER, OWNER
            )
        );
        this.externalCheckDeployedOnNetworks(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE));
    }

    function testBeaconOnAnUncheckedCatalogueNetworkIsRefused() external {
        supportOnly(LibRainDeploy.ARBITRUM_ONE, "");
        declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        declare(1, declared("beacon-implementation@0_0_1", OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconOnUncheckedNetwork.selector, 1, 1));
        this.externalCheckDeployedOnSupportedNetworks();
    }

    function testBeaconOnAChainIdOutsideTheCatalogueIsRefused() external {
        declare(42162, declared("beacon-implementation@0_0_1", OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconOnUncheckedNetwork.selector, 42162, 0));
        this.externalCheckDeployedOnSupportedNetworks();
    }

    function testBeaconOnAnEarlierCheckedNetworkResolves() external {
        declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        this.externalResolveBeacons(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE));
    }

    function testEachReleasedSuiteBeaconsNameIsDerivedOnce() external {
        declare(42161, migrating("beacon-upgrade@0_0_1", OWNER));
        declare(8453, declared("beacon-implementation@0_0_1", OWNER));
        declare(42161, bySuite("beacon@0_0_1", OWNER));
        declare(8453, declared("beacon-upgrade@0_0_1", OWNER));
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, type(MockDeployableV2).creationCode, 1);
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, type(MockDeployable).creationCode, 1);
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, beaconCreationCode(), 1);
        this.externalResolveBeacons(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE));
    }

    function testBeaconsOnEveryCheckedNetworkAreAccepted() external {
        supportOnly(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE);
        declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        this.externalCheckDeployedOnSupportedNetworks();
    }

    function testBeaconNamedBySuitePassesAtItsDerivedAddress() external {
        declare(42161, bySuite("beacon@0_0_1", OWNER));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconNamedBySuiteIsReadAtItsDerivedAddress() external {
        declare(42161, bySuite("beacon@0_0_1", NEW_OWNER));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector,
                LibRainDeploy.ARBITRUM_ONE,
                sSuiteBeacon,
                1,
                NEW_OWNER,
                OWNER
            )
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconSuiteMustHaveItsDerivedCode() external {
        declare(42161, bySuite("beacon@0_0_1", OWNER));
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
        declare(42161, bySuite("beacon@0_0_1", OWNER));
        vm.etch(BEACON_DEPENDENCY, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, BEACON_DEPENDENCY
            )
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testCandidateBeaconSuiteIsRefused() external {
        declare(42161, bySuite("beacon-implementation", OWNER));
        vm.expectRevert(abi.encodeWithSelector(BeaconSuiteNotReleased.selector, "beacon-implementation"));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconNamedBySuiteAndAddressIsRefused() external {
        DeployBeacon memory beacon = bySuite("beacon@0_0_1", OWNER);
        beacon.beacon = sSuiteBeacon;
        declare(42161, beacon);
        vm.expectRevert(abi.encodeWithSelector(BeaconNamedTwice.selector, 42161, 0));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconNamedBySuiteAndCodeHashIsRefused() external {
        DeployBeacon memory beacon = bySuite("beacon@0_0_1", OWNER);
        beacon.beaconCodeHash = sSuiteBeacon.codehash;
        declare(42161, beacon);
        vm.expectRevert(abi.encodeWithSelector(BeaconNamedTwice.selector, 42161, 0));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testUnnamedBeaconIsRefused() external {
        declare(42161, declared("beacon-implementation@0_0_1", OWNER));
        DeployBeacon memory unnamed = declared("beacon-implementation@0_0_1", OWNER);
        unnamed.beacon = address(0);
        unnamed.beaconCodeHash = bytes32(0);
        declare(42161, unnamed);
        vm.expectRevert(abi.encodeWithSelector(BeaconUnnamed.selector, 42161, 1));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconNamedByAddressAloneIsRefused() external {
        DeployBeacon memory beacon = declared("beacon-implementation@0_0_1", OWNER);
        beacon.beaconCodeHash = bytes32(0);
        declare(42161, beacon);
        vm.expectRevert(abi.encodeWithSelector(BeaconUnnamed.selector, 42161, 0));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconNamedByCodeHashAloneIsRefused() external {
        DeployBeacon memory beacon = declared("beacon-implementation@0_0_1", OWNER);
        beacon.beacon = address(0);
        declare(42161, beacon);
        vm.expectRevert(abi.encodeWithSelector(BeaconUnnamed.selector, 42161, 0));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }
}
