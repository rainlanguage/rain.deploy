// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {IERC5313} from "@openzeppelin-contracts-5.7.0/interfaces/IERC5313.sol";
import {Prerequisite} from "../interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistry} from "./LibMigrationRegistry.sol";
import {LibRainDeploy} from "./LibRainDeploy.sol";

/// The declared suite a beacon points at, by key, and its owner.
struct BeaconState {
    string implementation;
    address owner;
}

/// The state a beacon MUST hold once `migration` is applied.
struct BeaconTransition {
    Prerequisite migration;
    BeaconState state;
}

/// An upgradeable beacon on one network: `initial` until a transition's migration is applied.
struct DeployBeacon {
    address beacon;
    bytes32 beaconCodeHash;
    BeaconState initial;
    BeaconTransition[] transitions;
}

library LibRainDeployBeacon {
    /// Zero for `initial`, else one past the latest transition the selected fork's registry reports applied.
    function appliedState(DeployBeacon memory beacon) internal view returns (uint256) {
        for (uint256 i = beacon.transitions.length; i > 0; i--) {
            Prerequisite memory migration = beacon.transitions[i - 1].migration;
            if (LibMigrationRegistry.applied(migration.writer, migration.namespace, migration.migration) != 0) {
                return i;
            }
        }
        return 0;
    }

    function stateAt(DeployBeacon memory beacon, uint256 state) internal pure returns (BeaconState memory) {
        return state == 0 ? beacon.initial : beacon.transitions[state - 1].state;
    }

    /// The selected fork MUST hold `beacon` at its declared code, `implementation` and `owner`.
    function checkBeacon(string memory network, DeployBeacon memory beacon, address implementation, address owner)
        internal
        view
    {
        LibRainDeploy.checkDeployedCode(network, beacon.beacon, beacon.beaconCodeHash);
        bytes[] memory reads = new bytes[](2);
        reads[0] = abi.encodeCall(IBeacon.implementation, ());
        reads[1] = abi.encodeCall(IERC5313.owner, ());
        address[] memory expected = new address[](2);
        expected[0] = implementation;
        expected[1] = owner;
        LibRainDeploy.checkResolvedAddresses(network, beacon.beacon, reads, expected);
    }
}
