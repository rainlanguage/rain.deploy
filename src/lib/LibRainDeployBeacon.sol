// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {IERC5313} from "@openzeppelin-contracts-5.7.0/interfaces/IERC5313.sol";
import {MIGRATION_HEAD_GENESIS, Prerequisite} from "../interface/IMigrationRegistryV2.sol";
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
/// @param beaconSuite The key of the released suite deployed as the beacon, empty for a beacon this repo did not deploy.
/// @param beacon The address of a beacon this repo did not deploy, zero when named by `beaconSuite`.
/// @param beaconCodeHash The runtime code hash of a beacon this repo did not deploy, zero when named by `beaconSuite`.
/// @param initial The state before any transition's migration is applied.
/// @param transitions The states, each migration recorded applied after the earlier-declared applied ones.
struct DeployBeacon {
    string beaconSuite;
    address beacon;
    bytes32 beaconCodeHash;
    BeaconState initial;
    BeaconTransition[] transitions;
}

/// A beacon and the network it is on.
/// @param chainId The network's chain id.
/// @param beacon The beacon.
struct ChainBeacon {
    uint256 chainId;
    DeployBeacon beacon;
}

/// @title LibRainDeployBeacon
/// @notice The expected state of a declared upgradeable beacon on the selected fork, and the check that it holds.
library LibRainDeployBeacon {
    /// @notice A transition's migration MUST be recorded applied after the latest earlier-declared applied one's.
    /// @param network The beacon's network.
    /// @param beacon The beacon.
    /// @param transition The index in `transitions` of the one the registry does not record after it.
    error BeaconTransitionsOutOfOrder(string network, address beacon, uint256 transition);

    /// Zero for `initial`, else one past the latest transition the selected fork's registry reports applied.
    /// @param network The network's name, for the refusal.
    /// @param beacon The beacon.
    /// @return The state index, as `stateAt` takes it.
    function appliedState(string memory network, DeployBeacon memory beacon) internal view returns (uint256) {
        uint256 state = 0;
        for (uint256 i = 0; i < beacon.transitions.length; i++) {
            Prerequisite memory migration = beacon.transitions[i].migration;
            if (LibMigrationRegistry.applied(migration.writer, migration.namespace, migration.migration) == 0) {
                continue;
            }
            if (state != 0 && !recordedBefore(beacon.transitions[state - 1].migration, migration)) {
                revert BeaconTransitionsOutOfOrder(network, beacon.beacon, i);
            }
            state = i + 1;
        }
        return state;
    }

    /// Whether `earlier` is reached from `later` through what each record was applied after, reading each record once.
    /// @param earlier An applied migration.
    /// @param later An applied migration.
    /// @return True when the registry records `earlier` applied before `later`.
    function recordedBefore(Prerequisite memory earlier, Prerequisite memory later) internal view returns (bool) {
        bytes32 target = keccak256(abi.encode(earlier));
        Prerequisite[] memory reached = new Prerequisite[](1);
        reached[0] = later;
        for (uint256 next = 0; next < reached.length; next++) {
            Prerequisite[] memory entries = LibMigrationRegistry.appliedAfter(
                reached[next].writer, reached[next].namespace, reached[next].migration
            );
            for (uint256 i = 0; i < entries.length; i++) {
                if (entries[i].migration == MIGRATION_HEAD_GENESIS || isReached(reached, entries[i])) {
                    continue;
                }
                if (keccak256(abi.encode(entries[i])) == target) {
                    return true;
                }
                reached = appended(reached, entries[i]);
            }
        }
        return false;
    }

    /// @param reached The records reached so far.
    /// @param entry A record.
    /// @return True when `entry` is in `reached`.
    function isReached(Prerequisite[] memory reached, Prerequisite memory entry) private pure returns (bool) {
        bytes32 key = keccak256(abi.encode(entry));
        for (uint256 i = 0; i < reached.length; i++) {
            if (keccak256(abi.encode(reached[i])) == key) {
                return true;
            }
        }
        return false;
    }

    /// @param reached The records reached so far.
    /// @param entry A record not in `reached`.
    /// @return `reached` followed by `entry`.
    function appended(Prerequisite[] memory reached, Prerequisite memory entry)
        private
        pure
        returns (Prerequisite[] memory)
    {
        Prerequisite[] memory grown = new Prerequisite[](reached.length + 1);
        for (uint256 i = 0; i < reached.length; i++) {
            grown[i] = reached[i];
        }
        grown[reached.length] = entry;
        return grown;
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
    /// @param owner The address `owner()` MUST return; no other authority, such as a pending owner or a role, is read.
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
