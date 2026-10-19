// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";

/// @title LocalForkVm
/// @notice Forks each catalogue alias as the local EVM at its catalogue chain id, or at `sReportedChainId` once set, and formats addresses as the cheatcodes do.
contract LocalForkVm {
    /// The cheatcodes this stands in front of.
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// The chain id every fork selected reports once set; 0 for each fork's catalogue chain id.
    uint256 public sReportedChainId;

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

    /// Sets the local EVM's chain id to the fork's, or to `sReportedChainId` once set.
    /// @param forkId The fork id.
    function selectFork(uint256 forkId) external {
        VM.chainId(sReportedChainId == 0 ? forkId : sReportedChainId);
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

    /// Formats an address as the cheatcode does.
    /// @param value The address.
    /// @return It, formatted.
    function toString(address value) external pure returns (string memory) {
        return VM.toString(value);
    }
}
