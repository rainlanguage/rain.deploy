// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IMetaV1_2} from "rain-metadata-0.1.43/src/interface/unstable/IMetaV1_2.sol";
import {LocalLogsForkVm} from "../concrete/LocalLogsForkVm.sol";

/// @title LibMetaV1_2Log
/// @notice `MetaV1_2` logs as `eth_getLogs` returns them, set on a `LocalLogsForkVm` for the one-block query of a
/// metaboard.
library LibMetaV1_2Log {
    function topics() internal pure returns (bytes32[] memory) {
        bytes32[] memory metaTopics = new bytes32[](1);
        metaTopics[0] = IMetaV1_2.MetaV1_2.selector;
        return metaTopics;
    }

    function log(address metaBoard, address sender, address described, bytes memory meta)
        internal
        pure
        returns (Vm.EthGetLogs memory)
    {
        return Vm.EthGetLogs({
            emitter: metaBoard,
            topics: topics(),
            data: abi.encode(sender, bytes32(uint256(uint160(described))), meta),
            blockHash: bytes32(0),
            blockNumber: 0,
            transactionHash: bytes32(0),
            transactionIndex: 0,
            logIndex: 0,
            removed: false
        });
    }

    function one(address metaBoard, address sender, address described, bytes memory meta)
        internal
        pure
        returns (Vm.EthGetLogs[] memory)
    {
        Vm.EthGetLogs[] memory logs = new Vm.EthGetLogs[](1);
        logs[0] = log(metaBoard, sender, described, meta);
        return logs;
    }

    function setInBlock(
        LocalLogsForkVm logsVm,
        uint256 chainId,
        uint256 blockNumber,
        address metaBoard,
        Vm.EthGetLogs[] memory logs
    ) internal {
        logsVm.setLogs(chainId, blockNumber, blockNumber, metaBoard, topics(), logs);
    }
}
