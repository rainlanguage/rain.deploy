// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";

/// @title LocalForkVm
/// @notice Forks each catalogue alias as the local EVM at its catalogue chain id, or at `sReportedChainId` once set, and formats addresses as the cheatcodes do.
contract LocalForkVm {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 public sReportedChainId;

    function setReportedChainId(uint256 chainId) external {
        sReportedChainId = chainId;
    }

    function createFork(string calldata network) external pure returns (uint256) {
        string[] memory names = new string[](1);
        names[0] = network;
        return LibRainDeploy.declaredNetworkConfigs(names)[0].chainId;
    }

    function selectFork(uint256 forkId) external {
        VM.chainId(sReportedChainId == 0 ? forkId : sReportedChainId);
    }

    function rememberKey(uint256 privateKey) external pure returns (address) {
        return VM.addr(privateKey);
    }

    function startBroadcast(address) external pure {}

    function stopBroadcast() external pure {}

    function toString(address value) external pure returns (string memory) {
        return VM.toString(value);
    }
}
