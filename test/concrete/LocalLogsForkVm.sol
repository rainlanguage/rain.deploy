// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm, VmSafe} from "forge-std-1.17.0/src/Vm.sol";
import {LocalForkVm} from "./LocalForkVm.sol";

/// @title LocalLogsForkVm
/// @notice `LocalForkVm` answering `eth_getLogs` with the logs set for exactly that query on the selected chain, and
/// with none for any other.
contract LocalLogsForkVm is LocalForkVm {
    mapping(bytes32 => bytes) internal sLogs;

    function queryKey(uint256 chainId, uint256 fromBlock, uint256 toBlock, address target, bytes32[] memory topics)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(chainId, fromBlock, toBlock, target, topics));
    }

    function setLogs(
        uint256 chainId,
        uint256 fromBlock,
        uint256 toBlock,
        address target,
        bytes32[] memory topics,
        Vm.EthGetLogs[] memory logs
    ) external {
        sLogs[queryKey(chainId, fromBlock, toBlock, target, topics)] = abi.encode(logs);
    }

    function eth_getLogs(uint256 fromBlock, uint256 toBlock, address target, bytes32[] calldata topics)
        external
        view
        returns (Vm.EthGetLogs[] memory)
    {
        bytes memory logs = sLogs[queryKey(block.chainid, fromBlock, toBlock, target, topics)];
        if (logs.length == 0) {
            return new Vm.EthGetLogs[](0);
        }
        return abi.decode(logs, (VmSafe.EthGetLogs[]));
    }
}
