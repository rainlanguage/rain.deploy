// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {
    DeployCandidate,
    DeployDependency,
    DeploySuite,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyBase} from "../../src/abstract/RainDeployVerifyBase.sol";
import {BeaconState, BeaconTransition, ChainBeacon, DeployBeacon} from "../../src/lib/LibRainDeployBeacon.sol";
import {LibRainDeploy, SupportedNetwork} from "../../src/lib/LibRainDeploy.sol";
import {Prerequisite} from "../../src/interface/IMigrationRegistryV3.sol";
import {MigrationRegistry} from "../../src/concrete/MigrationRegistry.sol";
import {MockDeployable} from "../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../concrete/MockDeployableV2.sol";
import {LibBeaconTest} from "../lib/LibBeaconTest.sol";

/// @title BeaconVerifyFixture
/// @notice Released implementation, upgrade and beacon suites live locally, a beacon at the implementation, and the
/// declarations the beacon resolution and chain tests build from them.
abstract contract BeaconVerifyFixture is RainDeployVerifyBase {
    /// The initial owner.
    address constant OWNER = address(0xB0B);
    /// The owner a handover moves to.
    address constant NEW_OWNER = address(0xCAFE);
    /// The migration writer.
    address constant WRITER = address(0x5AFE);
    /// The migration namespace.
    bytes32 constant NAMESPACE = keccak256("beacons");
    /// The migration `migrating` names.
    bytes32 constant MIGRATION = keccak256("migration");
    /// The implementation suite's dependency.
    address constant DEPENDENCY = address(0xDE9);
    /// `DEPENDENCY`'s code.
    bytes constant DEPENDENCY_CODE = hex"00";
    /// The beacon suite's dependency.
    address constant BEACON_DEPENDENCY = address(0xBDE9);
    /// `BEACON_DEPENDENCY`'s code.
    bytes constant BEACON_DEPENDENCY_CODE = hex"02";

    /// The declarations `beacons()` returns.
    ChainBeacon[] internal sBeacons;
    /// A beacon at `sImplementation`, owned by `OWNER`.
    address internal sBeacon;
    /// The implementation suite, live.
    address internal sImplementation;
    /// The upgrade suite, live.
    address internal sUpgrade;
    /// The beacon suite, live.
    address internal sSuiteBeacon;
    /// The networks `supportedNetworks()` returns.
    string[] internal sSupported;
    /// Whether `beacons()` gives every declaration the first one's beacon.
    bool internal sShareFirstBeacon;

    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory released = new DeploySuite[](3);
        released[0] = LibBeaconTest.zoltuSuite(
            "beacon-implementation@0_0_1",
            type(MockDeployableV2).creationCode,
            type(MockDeployableV2).runtimeCode,
            "test/concrete/MockDeployableV2.sol:MockDeployableV2"
        );
        released[0].dependencies = new DeployDependency[](1);
        released[0].dependencies[0] = DeployDependency({deployedAddress: DEPENDENCY, runtimeCode: DEPENDENCY_CODE});
        released[1] = LibBeaconTest.zoltuSuite(
            "beacon-upgrade@0_0_1",
            type(MockDeployable).creationCode,
            type(MockDeployable).runtimeCode,
            "test/concrete/MockDeployable.sol:MockDeployable"
        );
        released[2] = LibBeaconTest.zoltuSuite(
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

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({
            snapshot: LibBeaconTest.zoltuSuite(
                "beacon-implementation",
                type(MockDeployableV2).creationCode,
                type(MockDeployableV2).runtimeCode,
                "test/concrete/MockDeployableV2.sol:MockDeployableV2"
            ),
            unanchorableReason: ""
        });
        return candidates;
    }

    /// @return The `beacon@0_0_1` creation code: a beacon at the implementation suite, owned by `OWNER`.
    function beaconCreationCode() internal pure returns (bytes memory) {
        return abi.encodePacked(
            type(UpgradeableBeacon).creationCode,
            abi.encode(LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode), OWNER)
        );
    }

    /// @inheritdoc RainDeploySuitesBase
    function beacons() internal view virtual override returns (ChainBeacon[] memory) {
        ChainBeacon[] memory chainBeacons = sBeacons;
        if (sShareFirstBeacon) {
            for (uint256 i = 1; i < chainBeacons.length; i++) {
                chainBeacons[i].beacon = chainBeacons[0].beacon;
            }
        }
        return chainBeacons;
    }

    /// @inheritdoc RainDeploySuitesBase
    function supportedNetworks() internal view virtual override returns (string[] memory) {
        return sSupported;
    }

    function setUp() external {
        sImplementation = LibRainDeploy.etchAndDeployZoltu(vm, type(MockDeployableV2).creationCode);
        sUpgrade = LibRainDeploy.etchAndDeployZoltu(vm, type(MockDeployable).creationCode);
        sBeacon = address(new UpgradeableBeacon(sImplementation, OWNER));
        address registry = LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
        vm.etch(DEPENDENCY, DEPENDENCY_CODE);
        vm.makePersistent(sImplementation, sUpgrade, sBeacon);
        vm.makePersistent(registry, DEPENDENCY);
        sSuiteBeacon = LibRainDeploy.etchAndDeployZoltu(vm, beaconCreationCode());
        vm.etch(BEACON_DEPENDENCY, BEACON_DEPENDENCY_CODE);
        vm.makePersistent(sSuiteBeacon, BEACON_DEPENDENCY);
        string[] memory supported = LibRainDeploy.supportedNetworks();
        for (uint256 i = 0; i < supported.length; i++) {
            sSupported.push(supported[i]);
        }
    }

    /// @param implementation The initial implementation suite key.
    /// @param owner The initial owner.
    /// @return `sBeacon`, named by address, with no transitions.
    function declared(string memory implementation, address owner) internal view returns (DeployBeacon memory) {
        return DeployBeacon({
            beaconSuite: "",
            beacon: sBeacon,
            beaconCodeHash: sBeacon.codehash,
            initial: BeaconState({implementation: implementation, owner: owner}),
            transitions: new BeaconTransition[](0)
        });
    }

    /// @param implementation The implementation suite key after `MIGRATION`.
    /// @param owner The owner after `MIGRATION`.
    /// @return `sBeacon` at the implementation suite and `OWNER`, moving to the given state on `MIGRATION`.
    function migrating(string memory implementation, address owner) internal view returns (DeployBeacon memory) {
        DeployBeacon memory beacon = declared("beacon-implementation@0_0_1", OWNER);
        beacon.transitions = new BeaconTransition[](1);
        beacon.transitions[0] = BeaconTransition({
            migration: Prerequisite({writer: WRITER, namespace: NAMESPACE, migration: MIGRATION}),
            state: BeaconState({implementation: implementation, owner: owner})
        });
        return beacon;
    }

    /// @param first The first network's name.
    /// @param second The second network's name, empty for none.
    /// @return The named networks' catalogue entries.
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

    /// Narrows `supportedNetworks()` to the named networks.
    /// @param first The first network's name.
    /// @param second The second network's name, empty for none.
    function supportOnly(string memory first, string memory second) internal {
        delete sSupported;
        sSupported.push(first);
        if (bytes(second).length > 0) {
            sSupported.push(second);
        }
    }

    /// @param beaconSuite The beacon's suite key.
    /// @param owner The initial owner.
    /// @return A beacon named by `beaconSuite`, at the implementation suite.
    function bySuite(string memory beaconSuite, address owner) internal view returns (DeployBeacon memory) {
        DeployBeacon memory beacon = declared("beacon-implementation@0_0_1", owner);
        beacon.beaconSuite = beaconSuite;
        beacon.beacon = address(0);
        beacon.beaconCodeHash = bytes32(0);
        return beacon;
    }

    /// @return Arbitrum One's catalogue entry alone.
    function arbitrum() internal pure returns (SupportedNetwork[] memory) {
        return networksNamed(LibRainDeploy.ARBITRUM_ONE, "");
    }
}
