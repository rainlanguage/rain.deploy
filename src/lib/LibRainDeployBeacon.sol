// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {IERC5313} from "@openzeppelin-contracts-5.7.0/interfaces/IERC5313.sol";
import {Ownable2Step} from "@openzeppelin-contracts-5.7.0/access/Ownable2Step.sol";
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
/// @param transitions The states, each a distinct migration recorded applied after the earlier-declared applied ones.
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

    /// @notice Each transition MUST name a distinct migration.
    /// @dev Keyed by chain id, like `RainDeployVerifyChain`'s `BeaconNamedTwice` and `BeaconUnnamed`, because it is also raised while
    /// resolving `beacons()`, before any network is selected or named.
    /// @param chainId The beacon's network.
    /// @param beacon The beacon.
    /// @param transition The index in `transitions` of the one naming an earlier-declared one's migration.
    error BeaconTransitionMigrationRepeated(uint256 chainId, address beacon, uint256 transition);

    /// @notice A beacon that answers `pendingOwner()` MUST answer zero.
    /// @param network The beacon's network.
    /// @param beacon The beacon.
    /// @param pendingOwner The word `pendingOwner()` answered, raw: a word with dirty upper bits is not an address.
    error BeaconPendingOwner(string network, address beacon, uint256 pendingOwner);

    /// @notice A beacon that answers `pendingOwner()` with data MUST answer exactly one word.
    /// @param network The beacon's network.
    /// @param beacon The beacon.
    /// @param answer The answer.
    error BeaconPendingOwnerUnreadable(string network, address beacon, bytes answer);

    /// Refuses `BeaconTransitionMigrationRepeated`, reading nothing.
    /// @param chainId The beacon's network, for the refusal.
    /// @param beacon The beacon.
    function checkDistinctMigrations(uint256 chainId, DeployBeacon memory beacon) internal pure {
        bytes32[] memory migrations = new bytes32[](beacon.transitions.length);
        for (uint256 i = 0; i < migrations.length; i++) {
            migrations[i] = keccak256(abi.encode(beacon.transitions[i].migration));
            if (isAmong(migrations, i, migrations[i])) {
                revert BeaconTransitionMigrationRepeated(chainId, beacon.beacon, i);
            }
        }
    }

    /// Zero for `initial`, else one past the latest transition the selected fork's registry reports applied.
    /// Reverts `BeaconTransitionMigrationRepeated` before reading the registry, then
    /// `LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash` when a transition is declared and the registry is
    /// not deployed, the registry's own refusal of a zero writer or namespace, or of a zero or genesis migration, and
    /// `BeaconTransitionsOutOfOrder`.
    /// @param network The network's name, for the refusal.
    /// @param beacon The beacon.
    /// @return The state index, as `stateAt` takes it.
    function appliedState(string memory network, DeployBeacon memory beacon) internal view returns (uint256) {
        checkDistinctMigrations(block.chainid, beacon);
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
    /// Unbounded: one read when `later` names `earlier` as a prerequisite, else every record between them, and every
    /// record back to genesis when `earlier` is not reached.
    /// Reverts `LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash` when the registry is not deployed, and the
    /// registry's own refusal of a zero writer or namespace, or of a zero or genesis migration.
    /// @param earlier An applied migration.
    /// @param later An applied migration.
    /// @return True when the registry records `earlier` applied before `later`.
    function recordedBefore(Prerequisite memory earlier, Prerequisite memory later) internal view returns (bool) {
        bytes32 target = keccak256(abi.encode(earlier));
        Prerequisite[] memory reached = new Prerequisite[](1);
        bytes32[] memory keys = new bytes32[](1);
        reached[0] = later;
        keys[0] = keccak256(abi.encode(later));
        uint256 count = 1;
        for (uint256 next = 0; next < count; next++) {
            Prerequisite[] memory entries = LibMigrationRegistry.appliedAfter(
                reached[next].writer, reached[next].namespace, reached[next].migration
            );
            for (uint256 i = 0; i < entries.length; i++) {
                if (entries[i].migration == MIGRATION_HEAD_GENESIS) {
                    continue;
                }
                bytes32 key = keccak256(abi.encode(entries[i]));
                if (key == target) {
                    return true;
                }
                if (isAmong(keys, count, key)) {
                    continue;
                }
                if (count == keys.length) {
                    (reached, keys) = doubled(reached, keys);
                }
                reached[count] = entries[i];
                keys[count] = key;
                count++;
            }
        }
        return false;
    }

    /// @param keys The keys.
    /// @param count How many of `keys`, from the first, to search.
    /// @param key A key.
    /// @return True when `key` is among the first `count` of `keys`.
    function isAmong(bytes32[] memory keys, uint256 count, bytes32 key) private pure returns (bool) {
        for (uint256 i = 0; i < count; i++) {
            if (keys[i] == key) {
                return true;
            }
        }
        return false;
    }

    /// @param reached The records reached so far.
    /// @param keys Each of `reached`'s key.
    /// @return `reached` at twice its length.
    /// @return `keys` at twice its length.
    function doubled(Prerequisite[] memory reached, bytes32[] memory keys)
        private
        pure
        returns (Prerequisite[] memory, bytes32[] memory)
    {
        Prerequisite[] memory longerReached = new Prerequisite[](reached.length * 2);
        bytes32[] memory longerKeys = new bytes32[](keys.length * 2);
        for (uint256 i = 0; i < keys.length; i++) {
            longerReached[i] = reached[i];
            longerKeys[i] = keys[i];
        }
        return (longerReached, longerKeys);
    }

    /// @param beacon The beacon.
    /// @param state The state index, `initial` at zero, reverting past `beacon.transitions.length`.
    /// @return The state.
    function stateAt(DeployBeacon memory beacon, uint256 state) internal pure returns (BeaconState memory) {
        return state == 0 ? beacon.initial : beacon.transitions[state - 1].state;
    }

    /// The selected fork MUST hold `beacon` at its declared code, `implementation` and `owner`, and no pending owner.
    /// Reverts `LibRainDeploy.NotDeployedOnNetwork` and `LibRainDeploy.CodeHashMismatchOnNetwork` on the code,
    /// `LibRainDeploy.ResolvedAddressReadFailed` and `LibRainDeploy.UnexpectedResolvedAddress` on `implementation()`
    /// or `owner()`, and `BeaconPendingOwnerUnreadable` and `BeaconPendingOwner` on `pendingOwner()`.
    /// @param network The network's name, for the refusal.
    /// @param beacon The beacon.
    /// @param implementation The address `implementation()` MUST return.
    /// @param owner The address `owner()` MUST return; roles and any other authority are not read.
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
        // slither-disable-next-line low-level-calls
        (bool success, bytes memory pending) = beacon.beacon.staticcall(abi.encodeCall(Ownable2Step.pendingOwner, ()));
        if (success && pending.length != 0) {
            if (pending.length != 0x20) {
                revert BeaconPendingOwnerUnreadable(network, beacon.beacon, pending);
            }
            uint256 pendingOwner = abi.decode(pending, (uint256));
            if (pendingOwner != 0) {
                revert BeaconPendingOwner(network, beacon.beacon, pendingOwner);
            }
        }
    }
}
