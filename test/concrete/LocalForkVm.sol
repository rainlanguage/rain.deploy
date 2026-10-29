// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";

/// @title LocalForkVm
/// @notice Forks each catalogue alias as the local EVM at its catalogue chain id, or at `sReportedChainId` once set,
/// copying the storage set for a fork each time it is selected, and formats addresses as the cheatcodes do.
contract LocalForkVm {
    /// A storage copy made on selecting a fork.
    /// @param from The account copied.
    /// @param to The account given `from`'s storage.
    struct StorageCopy {
        address from;
        address to;
    }

    /// The cheatcodes this stands in front of.
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// The chain id every fork selected reports once set; 0 for each fork's catalogue chain id.
    uint256 public sReportedChainId;

    /// The storage copies made on selecting each fork id.
    mapping(uint256 => StorageCopy[]) internal sStorageCopies;

    /// Makes every fork selected from now on report `chainId`.
    /// @param chainId The chain id to report.
    function setReportedChainId(uint256 chainId) external {
        sReportedChainId = chainId;
    }

    /// A catalogue alias's fork id, which is its catalogue chain id.
    /// @param network The alias.
    /// @return The fork id.
    function createFork(string calldata network) external pure returns (uint256) {
        string[] memory names = new string[](1);
        names[0] = network;
        return LibRainDeploy.declaredNetworkConfigs(names)[0].chainId;
    }

    /// Makes `to` hold `from`'s storage each time fork `forkId` is selected from now on.
    /// @param forkId The fork id.
    /// @param from The account copied.
    /// @param to The account given `from`'s storage.
    function copyStorageOnSelect(uint256 forkId, address from, address to) external {
        sStorageCopies[forkId].push(StorageCopy({from: from, to: to}));
    }

    /// Sets the local EVM's chain id to the fork's, or to `sReportedChainId` once set, then makes the fork's storage
    /// copies.
    /// @param forkId The fork id.
    function selectFork(uint256 forkId) external {
        VM.chainId(sReportedChainId == 0 ? forkId : sReportedChainId);
        StorageCopy[] storage copies = sStorageCopies[forkId];
        for (uint256 i = 0; i < copies.length; i++) {
            VM.copyStorage(copies[i].from, copies[i].to);
        }
    }

    /// The address of a private key.
    /// @param privateKey The key.
    /// @return Its address.
    function rememberKey(uint256 privateKey) external pure returns (address) {
        return VM.addr(privateKey);
    }

    /// Broadcasts nothing.
    /// @param broadcaster The account that would broadcast, ignored.
    function startBroadcast(address broadcaster) external pure {
        (broadcaster);
    }

    /// Broadcasts nothing.
    function stopBroadcast() external pure {}

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
