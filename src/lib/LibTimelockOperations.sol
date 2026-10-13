// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

/// The operation-state reads of OpenZeppelin's `TimelockController`, the only
/// part of it this library calls.
interface ITimelockOperationState {
    /// Whether `id` is scheduled and neither executed nor cancelled; true for
    /// a ready operation as well as a waiting one.
    /// @param id The operation id.
    /// @return Whether the operation is pending.
    function isOperationPending(bytes32 id) external view returns (bool);

    /// The timestamp at which `id` becomes ready, 1 once it is done, 0 when
    /// it is unset or cancelled.
    /// @param id The operation id.
    /// @return The stored timestamp.
    function getTimestamp(bytes32 id) external view returns (uint256);
}

/// One call of a scheduled timelock operation.
/// @param target The contract called.
/// @param value The native value sent.
/// @param data The calldata.
struct TimelockCall {
    address target;
    uint256 value;
    bytes data;
}

/// A timelock operation reconstructed from its `CallScheduled` logs.
/// @param id The operation id `cancel` and the state reads take.
/// @param predecessor The operation that must be done before this one runs.
/// @param readyAt The timestamp the timelock holds for it: when it becomes
/// executable.
/// @param calls Its calls in batch order; one for a `schedule`, one per batch
/// entry for a `scheduleBatch`.
struct TimelockOperation {
    bytes32 id;
    bytes32 predecessor;
    uint256 readyAt;
    TimelockCall[] calls;
}

/// @title LibTimelockOperations
/// @notice Lists the operations still pending on an OpenZeppelin
/// `TimelockController`.
///
/// The timelock stores one timestamp per operation id and nothing that can be
/// enumerated, so the only list of what was ever scheduled is its
/// `CallScheduled` logs. This reads them over `vm.eth_getLogs`, groups them by
/// id, and keeps the ids the timelock still reports pending.
///
/// Block-pinned: the logs are read from `fromBlock` up to the active fork's
/// `block.number` and the pending state is read at that same block, so both
/// halves describe one point in the chain's history. Pin the fork to a block
/// for an answer that does not move under a rerun.
library LibTimelockOperations {
    /// `CallScheduled(bytes32 indexed id, uint256 indexed index, address
    /// target, uint256 value, bytes data, bytes32 predecessor, uint256 delay)`.
    bytes32 internal constant CALL_SCHEDULED_TOPIC =
        keccak256("CallScheduled(bytes32,uint256,address,uint256,bytes,bytes32,uint256)");

    /// The block span of one `eth_getLogs` request in `pendingOperations`
    /// without an explicit span. Public RPCs commonly refuse ranges above
    /// 10_000 blocks.
    uint256 internal constant DEFAULT_LOG_SPAN = 10_000;

    /// Thrown when the log range starts after the fork's block.
    /// @param fromBlock The requested first block.
    /// @param toBlock The fork's `block.number`.
    error InvalidLogRange(uint256 fromBlock, uint256 toBlock);

    /// Thrown for a zero `eth_getLogs` span, which would never advance.
    error ZeroLogSpan();

    /// Thrown when a log is not a `CallScheduled` from the timelock being
    /// read. `eth_getLogs` is filtered on both, so this is an endpoint that
    /// ignored the filter, or logs handed in from somewhere else.
    /// @param index The log's position in the input.
    error UnexpectedLog(uint256 index);

    /// Thrown when an operation's logs skip a batch index: the logs read do
    /// not hold every call of the operation, so its calls cannot be stated.
    /// @param id The operation id.
    /// @param index The first missing batch index.
    error IncompleteOperation(bytes32 id, uint256 index);

    /// The operations pending on `timelock` at the active fork's block,
    /// reading logs in `DEFAULT_LOG_SPAN` blocks per request.
    /// @param vm The cheatcode address.
    /// @param timelock The timelock.
    /// @param fromBlock The first block to read logs from; its deploy block
    /// or any block before it.
    /// @return operations The pending operations, in order of first
    /// scheduling.
    function pendingOperations(Vm vm, address timelock, uint256 fromBlock)
        internal
        view
        returns (TimelockOperation[] memory operations)
    {
        operations = pendingOperations(vm, timelock, fromBlock, DEFAULT_LOG_SPAN);
    }

    /// The operations pending on `timelock` at the active fork's block,
    /// reading logs `span` blocks per request.
    /// @param vm The cheatcode address.
    /// @param timelock The timelock.
    /// @param fromBlock The first block to read logs from; its deploy block
    /// or any block before it.
    /// @param span The most blocks one `eth_getLogs` request covers.
    /// @return operations The pending operations, in order of first
    /// scheduling.
    function pendingOperations(Vm vm, address timelock, uint256 fromBlock, uint256 span)
        internal
        view
        returns (TimelockOperation[] memory operations)
    {
        operations = pendingFromLogs(scheduledLogs(vm, timelock, fromBlock, block.number, span), timelock);
    }

    /// Every `CallScheduled` log `timelock` emitted in `[fromBlock, toBlock]`,
    /// read `span` blocks per request, in chain order.
    /// @param vm The cheatcode address.
    /// @param timelock The timelock.
    /// @param fromBlock The first block, inclusive.
    /// @param toBlock The last block, inclusive.
    /// @param span The most blocks one request covers.
    /// @return logs The logs.
    function scheduledLogs(Vm vm, address timelock, uint256 fromBlock, uint256 toBlock, uint256 span)
        internal
        view
        returns (Vm.EthGetLogs[] memory logs)
    {
        if (fromBlock > toBlock) {
            revert InvalidLogRange(fromBlock, toBlock);
        }
        if (span == 0) {
            revert ZeroLogSpan();
        }
        bytes32[] memory topics = new bytes32[](1);
        topics[0] = CALL_SCHEDULED_TOPIC;

        uint256 chunks = (toBlock - fromBlock) / span + 1;
        Vm.EthGetLogs[][] memory pages = new Vm.EthGetLogs[][](chunks);
        uint256 total = 0;
        for (uint256 i = 0; i < chunks; i++) {
            uint256 start = fromBlock + i * span;
            uint256 end = start + (span - 1);
            if (end > toBlock) {
                end = toBlock;
            }
            pages[i] = vm.eth_getLogs(start, end, timelock, topics);
            total += pages[i].length;
        }

        logs = new Vm.EthGetLogs[](total);
        uint256 k = 0;
        for (uint256 i = 0; i < chunks; i++) {
            for (uint256 j = 0; j < pages[i].length; j++) {
                logs[k] = pages[i][j];
                k++;
            }
        }
    }

    /// The operations in `logs` that `timelock` reports pending now.
    ///
    /// Each id appears once however its logs arrived: a `scheduleBatch` logs
    /// its id once per call, and an id cancelled and scheduled again logs the
    /// same calls again (the id commits to them), so a batch index already
    /// seen for an id is skipped. A log the chain has marked `removed` is not
    /// part of it and is skipped.
    /// @param logs `CallScheduled` logs from `timelock`, in chain order.
    /// @param timelock The timelock.
    /// @return operations The pending operations, in order of first
    /// scheduling.
    function pendingFromLogs(Vm.EthGetLogs[] memory logs, address timelock)
        internal
        view
        returns (TimelockOperation[] memory operations)
    {
        // Distinct ids in first-seen order, and the highest batch index each
        // one logged.
        bytes32[] memory ids = new bytes32[](logs.length);
        uint256[] memory sizes = new uint256[](logs.length);
        uint256 idCount = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.EthGetLogs memory log = logs[i];
            if (
                log.emitter != timelock || log.topics.length != 3 || log.topics[0] != CALL_SCHEDULED_TOPIC
            ) {
                revert UnexpectedLog(i);
            }
            if (log.removed) {
                continue;
            }
            uint256 slot = indexOf(ids, idCount, log.topics[1]);
            if (slot == idCount) {
                ids[idCount] = log.topics[1];
                idCount++;
            }
            uint256 size = uint256(log.topics[2]) + 1;
            if (size > sizes[slot]) {
                sizes[slot] = size;
            }
        }

        uint256 pendingCount = 0;
        bool[] memory pending = new bool[](idCount);
        for (uint256 s = 0; s < idCount; s++) {
            pending[s] = ITimelockOperationState(timelock).isOperationPending(ids[s]);
            if (pending[s]) {
                pendingCount++;
            }
        }

        operations = new TimelockOperation[](pendingCount);
        uint256 o = 0;
        for (uint256 s = 0; s < idCount; s++) {
            if (!pending[s]) {
                continue;
            }
            operations[o] = assemble(logs, ids[s], sizes[s]);
            operations[o].readyAt = ITimelockOperationState(timelock).getTimestamp(ids[s]);
            o++;
        }
    }

    /// One operation's calls, filled by batch index from its logs.
    /// @param logs The validated logs.
    /// @param id The operation id.
    /// @param size One past the highest batch index the id logged.
    /// @return operation The operation, `readyAt` unset.
    function assemble(Vm.EthGetLogs[] memory logs, bytes32 id, uint256 size)
        private
        pure
        returns (TimelockOperation memory operation)
    {
        operation.id = id;
        operation.calls = new TimelockCall[](size);
        bool[] memory filled = new bool[](size);
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].removed || logs[i].topics[1] != id) {
                continue;
            }
            uint256 index = uint256(logs[i].topics[2]);
            if (filled[index]) {
                continue;
            }
            filled[index] = true;
            (address target, uint256 value, bytes memory data, bytes32 predecessor,) =
                abi.decode(logs[i].data, (address, uint256, bytes, bytes32, uint256));
            operation.calls[index] = TimelockCall({target: target, value: value, data: data});
            operation.predecessor = predecessor;
        }
        for (uint256 index = 0; index < size; index++) {
            if (!filled[index]) {
                revert IncompleteOperation(id, index);
            }
        }
    }

    /// The position of `id` among the first `count` of `ids`, or `count` when
    /// it is not there.
    /// @param ids The ids seen so far.
    /// @param count How many of `ids` are filled.
    /// @param id The id to find.
    /// @return The position.
    function indexOf(bytes32[] memory ids, uint256 count, bytes32 id) private pure returns (uint256) {
        for (uint256 i = 0; i < count; i++) {
            if (ids[i] == id) {
                return i;
            }
        }
        return count;
    }
}
