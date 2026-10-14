// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {
    DeployCandidate,
    DeployDependency,
    DeployMechanism,
    DeploySuite,
    UnknownDeploymentSuite
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {BeaconState, BeaconTransition, DeployBeacon} from "../../../src/lib/LibRainDeployBeacon.sol";
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

    mapping(uint256 => DeployBeacon[]) internal sBeacons;
    address internal sBeacon;
    address internal sImplementation;
    address internal sUpgrade;
    address internal sRegistry;

    function suite(string memory key, bytes memory creationCode, bytes memory runtimeCode, string memory artifactPath)
        internal
        pure
        returns (DeployCandidate memory)
    {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: key,
                creationCode: creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(creationCode),
                storedBytecodeHash: keccak256(runtimeCode),
                storedRuntimeCode: runtimeCode,
                artifactPath: artifactPath,
                dependencies: new DeployDependency[](0),
                mechanism: DeployMechanism.Zoltu,
                mechanismData: ""
            }),
            unanchorableReason: ""
        });
    }

    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        return new DeploySuite[](0);
    }

    function candidateSuites() internal pure override returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](2);
        candidates[0] = suite(
            "beacon-implementation",
            type(MockDeployableV2).creationCode,
            type(MockDeployableV2).runtimeCode,
            "test/concrete/MockDeployableV2.sol:MockDeployableV2"
        );
        candidates[1] = suite(
            "beacon-upgrade",
            type(MockDeployable).creationCode,
            type(MockDeployable).runtimeCode,
            "test/concrete/MockDeployable.sol:MockDeployable"
        );
        return candidates;
    }

    function beacons(uint256 chainId) internal view override returns (DeployBeacon[] memory) {
        return sBeacons[chainId];
    }

    function setUp() external {
        sImplementation = LibRainDeploy.etchAndDeployZoltu(vm, type(MockDeployableV2).creationCode);
        sUpgrade = LibRainDeploy.etchAndDeployZoltu(vm, type(MockDeployable).creationCode);
        sBeacon = address(new UpgradeableBeacon(sImplementation, OWNER));
        sRegistry = LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
        vm.makePersistent(sImplementation, sUpgrade, sBeacon);
        vm.makePersistent(sRegistry);
    }

    function declared(string memory implementation, address owner) internal view returns (DeployBeacon memory) {
        return DeployBeacon({
            beacon: sBeacon,
            beaconCodeHash: sBeacon.codehash,
            initial: BeaconState({implementation: implementation, owner: owner}),
            transitions: new BeaconTransition[](0)
        });
    }

    function migrating(string memory implementation, address owner) internal view returns (DeployBeacon memory) {
        DeployBeacon memory beacon = declared("beacon-implementation", OWNER);
        beacon.transitions = new BeaconTransition[](1);
        beacon.transitions[0] = BeaconTransition({
            migration: Prerequisite({writer: WRITER, namespace: NAMESPACE, migration: MIGRATION}),
            state: BeaconState({implementation: implementation, owner: owner})
        });
        return beacon;
    }

    function declare(uint256 chainId, DeployBeacon memory beacon) internal {
        DeployBeacon storage stored = sBeacons[chainId].push();
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
        checkDeployedOnNetworks(networks, releasedSuites());
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
        declare(42161, declared("beacon-implementation", OWNER));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testChainGroupChecksBeaconsOnAnyNetworkWithoutSuites() external {
        declare(42161, declared("beacon-implementation", NEW_OWNER));
        expectUnexpected(1, NEW_OWNER, OWNER);
        this.externalCheckDeployedOnNetworks(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE));
    }

    function testChainGroupChecksEachNetworksOwnBeacons() external {
        declare(42161, declared("beacon-implementation", OWNER));
        DeployBeacon memory missing = declared("beacon-implementation", OWNER);
        missing.beacon = address(0xBEAC0);
        declare(8453, missing);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.BASE, address(0xBEAC0))
        );
        this.externalCheckDeployedOnNetworks(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE));
    }

    function testChainGroupChecksEveryBeaconOnANetwork() external {
        declare(42161, declared("beacon-implementation", OWNER));
        declare(42161, declared("beacon-implementation", NEW_OWNER));
        expectUnexpected(1, NEW_OWNER, OWNER);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testBeaconMustPointAtTheDeclaredSuitesAddress() external {
        declare(42161, declared("beacon-upgrade", OWNER));
        expectUnexpected(0, sUpgrade, sImplementation);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testUnknownImplementationSuiteIsRefused() external {
        declare(42161, declared("no-such-suite", OWNER));
        vm.expectRevert(
            abi.encodeWithSelector(
                UnknownDeploymentSuite.selector, "no-such-suite", "beacon-implementation, beacon-upgrade"
            )
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testImplementationSuiteWithoutCodeIsNotDeployed() external {
        declare(42161, declared("beacon-implementation", OWNER));
        vm.etch(sImplementation, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.ARBITRUM_ONE, sImplementation
            )
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testImplementationSuiteMustHaveItsDerivedCode() external {
        declare(42161, declared("beacon-implementation", OWNER));
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
        declare(42161, migrating("beacon-upgrade", NEW_OWNER));
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testChainAheadOfTheRegistryIsRefused() external {
        declare(42161, migrating("beacon-upgrade", NEW_OWNER));
        upgradeAndHandOver();
        expectUnexpected(0, sImplementation, sUpgrade);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testAppliedMigrationExpectsItsTransition() external {
        declare(42161, migrating("beacon-upgrade", NEW_OWNER));
        applyMigration();
        upgradeAndHandOver();
        vm.etch(sImplementation, hex"");
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testAppliedUpgradeMissingFromTheChainIsRefused() external {
        declare(42161, migrating("beacon-upgrade", OWNER));
        applyMigration();
        expectUnexpected(0, sUpgrade, sImplementation);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testAppliedHandOverMissingFromTheChainIsRefused() external {
        declare(42161, migrating("beacon-implementation", NEW_OWNER));
        applyMigration();
        expectUnexpected(1, NEW_OWNER, OWNER);
        this.externalCheckDeployedOnNetworks(arbitrum());
    }

    function testAppliedUpgradeChecksTheUpgradedSuiteIsLive() external {
        declare(42161, migrating("beacon-upgrade", NEW_OWNER));
        applyMigration();
        upgradeAndHandOver();
        vm.etch(sUpgrade, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.ARBITRUM_ONE, sUpgrade)
        );
        this.externalCheckDeployedOnNetworks(arbitrum());
    }
}
