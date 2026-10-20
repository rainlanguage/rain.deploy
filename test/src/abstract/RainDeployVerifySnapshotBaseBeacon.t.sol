// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    BeaconDeclaredTwice,
    BeaconNamedTwice,
    BeaconOnUncheckedNetwork,
    BeaconSeatedOwner,
    BeaconSuiteNotReleased,
    BeaconUnnamed
} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {
    DeployCandidate,
    DeployDependency,
    DeploySuite,
    RainDeploySuitesBase
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifySnapshotBase} from "../../../src/abstract/RainDeployVerifySnapshotBase.sol";
import {
    BeaconState,
    BeaconTransition,
    ChainBeacon,
    DeployBeacon,
    LibRainDeployBeacon
} from "../../../src/lib/LibRainDeployBeacon.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibBeaconDeclarations} from "../../lib/LibBeaconDeclarations.sol";
import {LibBeaconTest} from "../../lib/LibBeaconTest.sol";
import {MIGRATION_HEAD_GENESIS, Prerequisite} from "../../../src/interface/IMigrationRegistryV3.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";

/// @title RainDeployVerifySnapshotBaseBeaconTest
/// @notice The snapshot group refuses a malformed beacon declaration without forking.
contract RainDeployVerifySnapshotBaseBeaconTest is RainDeployVerifySnapshotBase {
    using LibBeaconDeclarations for ChainBeacon[];

    address constant BEACON = address(0xBEAC0);

    address constant OWNER = address(0xB0B);

    address constant DEPLOY_KEY = address(0xDE9107);

    /// The declarations `beacons()` returns.
    ChainBeacon[] internal sBeacons;
    /// The networks `supportedNetworks()` returns, every catalogue network when empty.
    string[] internal sSupported;

    function implementation(string memory key) internal pure returns (DeploySuite memory) {
        return LibBeaconTest.zoltuSuite(
            key,
            type(MockDeployable).creationCode,
            type(MockDeployable).runtimeCode,
            "test/concrete/MockDeployable.sol:MockDeployable"
        );
    }

    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory released = new DeploySuite[](3);
        released[0] = implementation("implementation@0_0_1");
        address implementationAddress = released[0].storedDeployedAddress;
        released[1] = LibBeaconTest.beaconSuite("beacon@0_0_1", implementationAddress, OWNER);
        released[1].dependencies = new DeployDependency[](1);
        released[1].dependencies[0] =
            DeployDependency({deployedAddress: implementationAddress, runtimeCode: type(MockDeployable).runtimeCode});
        released[2] = LibBeaconTest.beaconSuite("deploy-key-beacon@0_0_1", implementationAddress, DEPLOY_KEY);
        released[2].dependencies = released[1].dependencies;
        return released;
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({snapshot: implementation("implementation"), unanchorableReason: ""});
        return candidates;
    }

    /// @inheritdoc RainDeploySuitesBase
    function beacons() internal view override returns (ChainBeacon[] memory) {
        return sBeacons;
    }

    /// @inheritdoc RainDeploySuitesBase
    function supportedNetworks() internal view override returns (string[] memory) {
        return sSupported.length == 0 ? LibRainDeploy.supportedNetworks() : sSupported;
    }

    function setUp() external {
        sBeacons.declare(42161, valid());
    }

    function valid() internal pure returns (DeployBeacon memory) {
        return DeployBeacon({
            beaconSuite: "",
            beacon: BEACON,
            beaconCodeHash: keccak256("beacon"),
            initial: BeaconState({implementation: "implementation@0_0_1", owner: OWNER}),
            transitions: new BeaconTransition[](0)
        });
    }

    function redeclare(uint256 chainId, DeployBeacon memory beacon) internal {
        delete sBeacons;
        sBeacons.declare(chainId, beacon);
    }

    function expectRefusedOffline(bytes memory refusal) internal {
        vm.expectRevert(refusal);
        this.testBeaconDeclarationsResolve();
        LibBeaconTest.assertNoFork(vm, "forked");
    }

    function testUnreleasedImplementationIsRefusedOffline() external {
        DeployBeacon memory beacon = valid();
        beacon.initial.implementation = "no-such-suite";
        redeclare(42161, beacon);
        expectRefusedOffline(abi.encodeWithSelector(BeaconSuiteNotReleased.selector, "no-such-suite"));
    }

    function testBeaconNamedTwiceIsRefusedOffline() external {
        DeployBeacon memory beacon = valid();
        beacon.beaconSuite = "implementation@0_0_1";
        redeclare(42161, beacon);
        expectRefusedOffline(abi.encodeWithSelector(BeaconNamedTwice.selector, 42161, 0));
    }

    function testUnnamedBeaconIsRefusedOffline() external {
        DeployBeacon memory beacon = valid();
        beacon.beaconCodeHash = bytes32(0);
        redeclare(42161, beacon);
        expectRefusedOffline(abi.encodeWithSelector(BeaconUnnamed.selector, 42161, 0));
    }

    function testBeaconOnAnUncheckedNetworkIsRefusedOffline() external {
        sBeacons.declare(42162, valid());
        expectRefusedOffline(abi.encodeWithSelector(BeaconOnUncheckedNetwork.selector, 42162, 1));
    }

    function testRepeatedMigrationIsRefusedOffline() external {
        DeployBeacon memory beacon = valid();
        Prerequisite memory migration =
            Prerequisite({writer: address(0x5AFE), namespace: keccak256("beacons"), migration: keccak256("migration")});
        beacon.transitions = new BeaconTransition[](2);
        beacon.transitions[0] = BeaconTransition({migration: migration, state: beacon.initial});
        beacon.transitions[1] = BeaconTransition({migration: migration, state: beacon.initial});
        redeclare(42161, beacon);
        expectRefusedOffline(
            abi.encodeWithSelector(LibRainDeployBeacon.BeaconTransitionMigrationRepeated.selector, 42161, BEACON, 1)
        );
    }

    function testNoBeaconsResolveWithoutReadingSupportedNetworks() external {
        delete sBeacons;
        sSupported.push("not-a-catalogue-network");
        this.testBeaconDeclarationsResolve();
    }

    function testSupportedNetworksAreReadWhenABeaconIsDeclared() external {
        sSupported.push("not-a-catalogue-network");
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NetworkNotInCatalogue.selector, "not-a-catalogue-network"));
        this.testBeaconDeclarationsResolve();
    }

    function expectUnnamedMigrationOffline(Prerequisite memory migration) internal {
        DeployBeacon memory beacon = valid();
        beacon.transitions = new BeaconTransition[](2);
        beacon.transitions[0] = BeaconTransition({
            migration: Prerequisite({
                writer: address(0x5AFE), namespace: keccak256("beacons"), migration: keccak256("migration")
            }),
            state: beacon.initial
        });
        beacon.transitions[1] = BeaconTransition({migration: migration, state: beacon.initial});
        redeclare(42161, beacon);
        expectRefusedOffline(
            abi.encodeWithSelector(LibRainDeployBeacon.BeaconTransitionMigrationUnnamed.selector, 42161, BEACON, 1)
        );
    }

    function testMigrationWithAZeroWriterIsRefusedOffline() external {
        expectUnnamedMigrationOffline(
            Prerequisite({writer: address(0), namespace: keccak256("beacons"), migration: keccak256("later")})
        );
    }

    function testMigrationWithAZeroNamespaceIsRefusedOffline() external {
        expectUnnamedMigrationOffline(
            Prerequisite({writer: address(0x5AFE), namespace: bytes32(0), migration: keccak256("later")})
        );
    }

    function testZeroMigrationIsRefusedOffline() external {
        expectUnnamedMigrationOffline(
            Prerequisite({writer: address(0x5AFE), namespace: keccak256("beacons"), migration: bytes32(0)})
        );
    }

    function testGenesisMigrationIsRefusedOffline() external {
        expectUnnamedMigrationOffline(
            Prerequisite({writer: address(0x5AFE), namespace: keccak256("beacons"), migration: MIGRATION_HEAD_GENESIS})
        );
    }

    function testBeaconDeclaredTwiceIsRefusedOffline() external {
        sBeacons.declare(42161, valid());
        expectRefusedOffline(abi.encodeWithSelector(BeaconDeclaredTwice.selector, 42161, 1));
    }

    function testBeaconDeclaredTwiceWithAnotherOwnerIsRefusedOffline() external {
        DeployBeacon memory beacon = valid();
        beacon.initial.owner = address(0xCAFE);
        sBeacons.declare(42161, beacon);
        expectRefusedOffline(abi.encodeWithSelector(BeaconDeclaredTwice.selector, 42161, 1));
    }

    function testOneBeaconAddressOnTwoNetworksIsNotDeclaredTwice() external {
        sBeacons.declare(8453, valid());
        this.testBeaconDeclarationsResolve();
    }

    function bySuite(address owner) internal pure returns (DeployBeacon memory) {
        DeployBeacon memory beacon = valid();
        beacon.beaconSuite = "beacon@0_0_1";
        beacon.beacon = address(0);
        beacon.beaconCodeHash = bytes32(0);
        beacon.initial.owner = owner;
        return beacon;
    }

    function testBeaconSuiteSeatingAnotherOwnerIsRefusedOffline() external {
        redeclare(42161, bySuite(address(0xCAFE)));
        expectRefusedOffline(abi.encodeWithSelector(BeaconSeatedOwner.selector, 42161, 0, abi.encode(OWNER)));
    }

    function testBeaconSuiteSeatingItsInitialStateResolvesOffline() external {
        redeclare(42161, bySuite(OWNER));
        this.testBeaconDeclarationsResolve();
        LibBeaconTest.assertNoFork(vm, "forked");
    }

    function testBeaconSuiteThatSeatedTheDeployKeyDeclaredByItsSuiteAfterHandoverIsRefusedOffline() external {
        DeployBeacon memory beacon = bySuite(OWNER);
        beacon.beaconSuite = "deploy-key-beacon@0_0_1";
        redeclare(42161, beacon);
        expectRefusedOffline(abi.encodeWithSelector(BeaconSeatedOwner.selector, 42161, 0, abi.encode(DEPLOY_KEY)));
    }

    function testBeaconSuiteThatSeatedTheDeployKeyDeclaredByAddressAfterHandoverResolvesOffline() external {
        DeployBeacon memory beacon = valid();
        DeploySuite memory seated = releasedSuites()[2];
        beacon.beacon = seated.storedDeployedAddress;
        beacon.beaconCodeHash = seated.storedBytecodeHash;
        redeclare(42161, beacon);
        this.testBeaconDeclarationsResolve();
        LibBeaconTest.assertNoFork(vm, "forked");
    }
}
