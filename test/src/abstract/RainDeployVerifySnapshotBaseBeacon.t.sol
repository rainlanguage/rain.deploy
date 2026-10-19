// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    BeaconNamedTwice,
    BeaconOnUncheckedNetwork,
    BeaconSuiteNotReleased,
    BeaconUnnamed
} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {
    DeployCandidate,
    DeployDependency,
    DeployMechanism,
    DeploySuite
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
import {Prerequisite} from "../../../src/interface/IMigrationRegistryV2.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";

/// @title RainDeployVerifySnapshotBaseBeaconTest
/// @notice The snapshot group refuses a malformed beacon declaration without forking.
contract RainDeployVerifySnapshotBaseBeaconTest is RainDeployVerifySnapshotBase {
    address constant BEACON = address(0xBEAC0);

    ChainBeacon[] internal sBeacons;
    string[] internal sSupported;

    function implementation(string memory key) internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: key,
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode),
            storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
            storedRuntimeCode: type(MockDeployable).runtimeCode,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new DeployDependency[](0),
            mechanism: DeployMechanism.Zoltu,
            mechanismData: ""
        });
    }

    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory released = new DeploySuite[](1);
        released[0] = implementation("implementation@0_0_1");
        return released;
    }

    function candidateSuites() internal pure override returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({snapshot: implementation("implementation"), unanchorableReason: ""});
        return candidates;
    }

    function beacons() internal view override returns (ChainBeacon[] memory) {
        return sBeacons;
    }

    function supportedNetworks() internal view override returns (string[] memory) {
        return sSupported.length == 0 ? LibRainDeploy.supportedNetworks() : sSupported;
    }

    function setUp() external {
        declare(42161, valid());
    }

    function valid() internal pure returns (DeployBeacon memory) {
        return DeployBeacon({
            beaconSuite: "",
            beacon: BEACON,
            beaconCodeHash: keccak256("beacon"),
            initial: BeaconState({implementation: "implementation@0_0_1", owner: address(0xB0B)}),
            transitions: new BeaconTransition[](0)
        });
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

    function redeclare(uint256 chainId, DeployBeacon memory beacon) internal {
        delete sBeacons;
        declare(chainId, beacon);
    }

    function expectRefusedOffline(bytes memory refusal) internal {
        vm.expectRevert(refusal);
        this.testBeaconDeclarationsResolve();
        try vm.activeFork() returns (uint256) {
            fail("forked");
        } catch {}
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
        declare(42162, valid());
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

    function testBeaconsAreReadWhenDeclared() external {
        sSupported.push("not-a-catalogue-network");
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NetworkNotInCatalogue.selector, "not-a-catalogue-network"));
        this.testBeaconDeclarationsResolve();
    }
}
