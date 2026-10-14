// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {IERC5313} from "@openzeppelin-contracts-5.7.0/interfaces/IERC5313.sol";
import {Prerequisite} from "../interface/IMigrationRegistryV2.sol";
import {LibMigrationRegistry} from "./LibMigrationRegistry.sol";
import {LibRainDeploy} from "./LibRainDeploy.sol";

/// The declared suite a beacon points at, by key, and its owner.
/// @param implementation The key of the released suite `implementation()` MUST return the address of.
/// @param owner The address `owner()` MUST return.
struct BeaconState {
    string implementation;
    address owner;
}

/// The state a beacon MUST hold once `migration` is applied.
/// @param migration The migration whose application moves the beacon to `state`.
/// @param state The state.
struct BeaconTransition {
    Prerequisite migration;
    BeaconState state;
}

/// An upgradeable beacon on one network: `initial` until a transition's migration is applied.
/// @param beacon The beacon's address.
/// @param beaconCodeHash The beacon's runtime code hash.
/// @param initial The state before any transition's migration is applied.
/// @param transitions The states, in migration order.
struct DeployBeacon {
    address beacon;
    bytes32 beaconCodeHash;
    BeaconState initial;
    BeaconTransition[] transitions;
}

library LibRainDeployBeacon {
    /// Zero for `initial`, else one past the latest transition the selected fork's registry reports applied.
    /// @param beacon The beacon.
    /// @return The state index, as `stateAt` takes it.
    function appliedState(DeployBeacon memory beacon) internal view returns (uint256) {
        for (uint256 i = beacon.transitions.length; i > 0; i--) {
            Prerequisite memory migration = beacon.transitions[i - 1].migration;
            if (LibMigrationRegistry.applied(migration.writer, migration.namespace, migration.migration) != 0) {
                return i;
            }
        }
        return 0;
    }

    /// @param beacon The beacon.
    /// @param state The state index, `initial` at zero, reverting past `beacon.transitions.length`.
    /// @return The state.
    function stateAt(DeployBeacon memory beacon, uint256 state) internal pure returns (BeaconState memory) {
        return state == 0 ? beacon.initial : beacon.transitions[state - 1].state;
    }

    /// The selected fork MUST hold `beacon` at its declared code, `implementation` and `owner`.
    /// @param network The network's name, for the refusal.
    /// @param beacon The beacon.
    /// @param implementation The address `implementation()` MUST return.
    /// @param owner The address `owner()` MUST return.
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
