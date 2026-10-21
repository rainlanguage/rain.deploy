// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";

/// @title LocalSnapshotForkVm
/// @notice Forks each catalogue alias as a snapshot of the local EVM, taken
/// when the fork is created and restored, at the alias's catalogue chain id,
/// whenever it is selected: so what one fork does is gone on the next, as on
/// separate chains. Formats as the cheatcodes do.
///
/// A fork id is the catalogue chain id in its high 128 bits and the snapshot
/// id in its low 128, because restoring a snapshot also restores this
/// contract's storage, so nothing written here after one is taken survives.
contract LocalSnapshotForkVm {
    /// The cheatcodes this stands in front of.
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// Snapshots the local EVM as the alias's fork.
    /// @param network The alias.
    /// @return The fork id.
    function createFork(string calldata network) external returns (uint256) {
        string[] memory names = new string[](1);
        names[0] = network;
        return (LibRainDeploy.declaredNetworkConfigs(names)[0].chainId << 128) | VM.snapshotState();
    }

    /// Restores the fork's snapshot and sets its chain id.
    /// @param forkId The fork id.
    function selectFork(uint256 forkId) external {
        VM.revertToState(uint128(forkId));
        VM.chainId(forkId >> 128);
    }

    /// The local EVM's chain id.
    /// @return The chain id.
    function getChainId() external view returns (uint256) {
        return VM.getChainId();
    }

    /// Formats an address as the cheatcode does.
    /// @param value The address.
    /// @return It, formatted.
    function toString(address value) external pure returns (string memory) {
        return VM.toString(value);
    }

    /// Formats bytes as the cheatcode does.
    /// @param value The bytes.
    /// @return They, formatted.
    function toString(bytes calldata value) external pure returns (string memory) {
        return VM.toString(value);
    }

    /// Formats a word as the cheatcode does.
    /// @param value The word.
    /// @return It, formatted.
    function toString(bytes32 value) external pure returns (string memory) {
        return VM.toString(value);
    }

    /// Formats a number as the cheatcode does.
    /// @param value The number.
    /// @return It, formatted.
    function toString(uint256 value) external pure returns (string memory) {
        return VM.toString(value);
    }
}
