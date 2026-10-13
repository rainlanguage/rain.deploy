// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {
    ITimelockOperationState,
    LibTimelockOperations,
    TimelockOperation
} from "../../../src/lib/LibTimelockOperations.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {MockTimelock} from "../../concrete/MockTimelock.sol";

/// @title LibTimelockOperationsTest
/// @notice Reconstructing pending operations from `CallScheduled` logs a
/// timelock really emitted, recorded locally and handed in as the RPC would
/// return them.
contract LibTimelockOperationsTest is Test {
    MockTimelock internal timelock;

    bytes32 constant ID_A = keccak256("op a");
    bytes32 constant ID_B = keccak256("op b");
    bytes32 constant ID_C = keccak256("op c");
    bytes32 constant PREDECESSOR = keccak256("predecessor");

    function setUp() external {
        timelock = new MockTimelock();
    }

    /// `pendingFromLogs` reached through a call, for `vm.expectRevert`. Returns
    /// nothing: decoding a returned `TimelockOperation[]` at the call site is
    /// too deep for the legacy code generator.
    function externalPendingFromLogs(Vm.EthGetLogs[] memory logs, address target) external view {
        LibTimelockOperations.pendingFromLogs(logs, target);
    }

    /// `scheduledLogs` reached through a call, for `vm.expectRevert`. Returns
    /// nothing, for the same reason.
    function externalScheduledLogs(address target, uint256 fromBlock, uint256 toBlock, uint256 span) external view {
        LibTimelockOperations.scheduledLogs(vm, target, fromBlock, toBlock, span);
    }

    /// The recorded logs in the shape `vm.eth_getLogs` returns them.
    function takeLogs() internal view returns (Vm.EthGetLogs[] memory out) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        out = new Vm.EthGetLogs[](logs.length);
        for (uint256 i = 0; i < logs.length; i++) {
            out[i].emitter = logs[i].emitter;
            out[i].topics = logs[i].topics;
            out[i].data = logs[i].data;
        }
    }

    /// The topic constant is the hash of the event as OZ declares it.
    function testCallScheduledTopic() external pure {
        assertEq(LibTimelockOperations.CALL_SCHEDULED_TOPIC, MockTimelock.CallScheduled.selector);
    }

    /// A single `schedule` reads back as one operation with its call,
    /// predecessor and ready timestamp.
    function testSingleCallOperation() external {
        vm.recordLogs();
        timelock.emitScheduled(ID_A, 0, address(0xBEEF), 7, hex"c0ffee", PREDECESSOR, 100);
        Vm.EthGetLogs[] memory logs = takeLogs();
        timelock.setTimestamp(ID_A, 12345);

        TimelockOperation[] memory ops = LibTimelockOperations.pendingFromLogs(logs, address(timelock));
        assertEq(ops.length, 1);
        assertEq(ops[0].id, ID_A);
        assertEq(ops[0].predecessor, PREDECESSOR);
        assertEq(ops[0].readyAt, 12345);
        assertEq(ops[0].calls.length, 1);
        assertEq(ops[0].calls[0].target, address(0xBEEF));
        assertEq(ops[0].calls[0].value, 7);
        assertEq(ops[0].calls[0].data, hex"c0ffee");
    }

    /// A batch reads back as one operation with its calls placed by batch
    /// index, whatever order the logs arrive in.
    function testBatchPlacedByIndex() external {
        vm.recordLogs();
        timelock.emitScheduled(ID_A, 2, address(0xC2), 2, hex"02", bytes32(0), 100);
        timelock.emitScheduled(ID_A, 0, address(0xC0), 0, hex"00", bytes32(0), 100);
        timelock.emitScheduled(ID_A, 1, address(0xC1), 1, hex"01", bytes32(0), 100);
        Vm.EthGetLogs[] memory logs = takeLogs();
        timelock.setTimestamp(ID_A, 2);

        TimelockOperation[] memory ops = LibTimelockOperations.pendingFromLogs(logs, address(timelock));
        assertEq(ops.length, 1);
        assertEq(ops[0].calls.length, 3);
        for (uint256 i = 0; i < 3; i++) {
            assertEq(ops[0].calls[i].target, address(uint160(0xC0 + i)));
            assertEq(ops[0].calls[i].value, i);
            assertEq(ops[0].calls[i].data, abi.encodePacked(uint8(i)));
        }
        assertEq(ops[0].readyAt, 2);
    }

    /// An id scheduled, cancelled and scheduled again logs its calls twice and
    /// reads back once, with each call once.
    function testRescheduledIdDeduplicated() external {
        vm.recordLogs();
        timelock.emitScheduled(ID_A, 0, address(0xC0), 0, hex"00", bytes32(0), 100);
        timelock.emitScheduled(ID_A, 1, address(0xC1), 0, hex"01", bytes32(0), 100);
        timelock.emitScheduled(ID_A, 0, address(0xC0), 0, hex"00", bytes32(0), 200);
        timelock.emitScheduled(ID_A, 1, address(0xC1), 0, hex"01", bytes32(0), 200);
        Vm.EthGetLogs[] memory logs = takeLogs();
        timelock.setTimestamp(ID_A, 99);

        TimelockOperation[] memory ops = LibTimelockOperations.pendingFromLogs(logs, address(timelock));
        assertEq(ops.length, 1);
        assertEq(ops[0].calls.length, 2);
        assertEq(ops[0].calls[0].target, address(0xC0));
        assertEq(ops[0].calls[1].target, address(0xC1));
    }

    /// Only ids the timelock reports pending are kept: unset or cancelled
    /// (0) and done (1) are dropped, ready (any timestamp above 1, past or
    /// future) is kept. Order is first scheduling.
    function testOnlyPendingKeptInScheduleOrder() external {
        vm.warp(1_000_000);
        bytes32 idDone = keccak256("done");
        vm.recordLogs();
        timelock.emitScheduled(ID_C, 0, address(0xC), 0, "", bytes32(0), 1);
        timelock.emitScheduled(ID_A, 0, address(0xA), 0, "", bytes32(0), 1);
        timelock.emitScheduled(idDone, 0, address(0xD), 0, "", bytes32(0), 1);
        timelock.emitScheduled(ID_B, 0, address(0xB), 0, "", bytes32(0), 1);
        timelock.emitScheduled(ID_C, 0, address(0xC), 0, "", bytes32(0), 1);
        Vm.EthGetLogs[] memory logs = takeLogs();
        timelock.setTimestamp(ID_C, block.timestamp + 1 days);
        timelock.setTimestamp(idDone, 1);
        timelock.setTimestamp(ID_B, block.timestamp);
        // ID_A stays 0: cancelled.

        TimelockOperation[] memory ops = LibTimelockOperations.pendingFromLogs(logs, address(timelock));
        assertEq(ops.length, 2);
        assertEq(ops[0].id, ID_C);
        assertEq(ops[0].readyAt, block.timestamp + 1 days);
        assertEq(ops[1].id, ID_B);
        assertEq(ops[1].readyAt, block.timestamp);
    }

    /// No logs, no operations.
    function testEmpty() external view {
        assertEq(LibTimelockOperations.pendingFromLogs(new Vm.EthGetLogs[](0), address(timelock)).length, 0);
    }

    /// A log the chain marks removed is not counted toward its operation.
    function testRemovedLogSkipped() external {
        vm.recordLogs();
        timelock.emitScheduled(ID_A, 0, address(0xA0), 0, "", bytes32(0), 1);
        timelock.emitScheduled(ID_A, 1, address(0xA1), 0, "", bytes32(0), 1);
        timelock.emitScheduled(ID_B, 0, address(0xB0), 0, "", bytes32(0), 1);
        Vm.EthGetLogs[] memory logs = takeLogs();
        logs[1].removed = true;
        logs[2].removed = true;
        timelock.setTimestamp(ID_A, 5);
        timelock.setTimestamp(ID_B, 5);

        TimelockOperation[] memory ops = LibTimelockOperations.pendingFromLogs(logs, address(timelock));
        assertEq(ops.length, 1);
        assertEq(ops[0].id, ID_A);
        assertEq(ops[0].calls.length, 1);
        assertEq(ops[0].calls[0].target, address(0xA0));
    }

    /// A missing batch index is refused rather than read as a shorter batch
    /// or a zero call.
    function testGapRefused() external {
        vm.recordLogs();
        timelock.emitScheduled(ID_A, 0, address(0xA0), 0, "", bytes32(0), 1);
        timelock.emitScheduled(ID_A, 2, address(0xA2), 0, "", bytes32(0), 1);
        Vm.EthGetLogs[] memory logs = takeLogs();
        timelock.setTimestamp(ID_A, 5);

        vm.expectRevert(abi.encodeWithSelector(LibTimelockOperations.IncompleteOperation.selector, ID_A, uint256(1)));
        this.externalPendingFromLogs(logs, address(timelock));
    }

    /// A gap in a non-pending operation is not read, so it is not refused.
    function testGapInNonPendingIgnored() external {
        vm.recordLogs();
        timelock.emitScheduled(ID_A, 1, address(0xA1), 0, "", bytes32(0), 1);
        Vm.EthGetLogs[] memory logs = takeLogs();
        assertEq(LibTimelockOperations.pendingFromLogs(logs, address(timelock)).length, 0);
    }

    /// A log from another emitter is refused, by its position.
    function testForeignEmitterRefused() external {
        MockTimelock other = new MockTimelock();
        vm.recordLogs();
        timelock.emitScheduled(ID_A, 0, address(0xA0), 0, "", bytes32(0), 1);
        other.emitScheduled(ID_A, 0, address(0xA0), 0, "", bytes32(0), 1);
        Vm.EthGetLogs[] memory logs = takeLogs();

        vm.expectRevert(abi.encodeWithSelector(LibTimelockOperations.UnexpectedLog.selector, uint256(1)));
        this.externalPendingFromLogs(logs, address(timelock));
    }

    /// A log with another signature topic is refused.
    function testForeignTopicRefused() external {
        vm.recordLogs();
        timelock.emitScheduled(ID_A, 0, address(0xA0), 0, "", bytes32(0), 1);
        Vm.EthGetLogs[] memory logs = takeLogs();
        logs[0].topics[0] = keccak256("CallExecuted(bytes32,uint256,address,uint256,bytes)");

        vm.expectRevert(abi.encodeWithSelector(LibTimelockOperations.UnexpectedLog.selector, uint256(0)));
        this.externalPendingFromLogs(logs, address(timelock));
    }

    /// A log with the right signature topic but the wrong topic count is
    /// refused rather than read out of bounds or misread.
    function testWrongTopicCountRefused() external {
        vm.recordLogs();
        timelock.emitScheduled(ID_A, 0, address(0xA0), 0, "", bytes32(0), 1);
        Vm.EthGetLogs[] memory logs = takeLogs();
        bytes32[] memory short = new bytes32[](2);
        short[0] = logs[0].topics[0];
        short[1] = logs[0].topics[1];
        logs[0].topics = short;

        vm.expectRevert(abi.encodeWithSelector(LibTimelockOperations.UnexpectedLog.selector, uint256(0)));
        this.externalPendingFromLogs(logs, address(timelock));

        bytes32[] memory long = new bytes32[](4);
        logs[0].topics = long;
        long[0] = LibTimelockOperations.CALL_SCHEDULED_TOPIC;
        vm.expectRevert(abi.encodeWithSelector(LibTimelockOperations.UnexpectedLog.selector, uint256(0)));
        this.externalPendingFromLogs(logs, address(timelock));
    }

    /// A range that starts after it ends is refused before any request.
    function testInvertedRangeRefused() external {
        vm.expectRevert(abi.encodeWithSelector(LibTimelockOperations.InvalidLogRange.selector, uint256(11), uint256(10)));
        this.externalScheduledLogs(address(timelock), 11, 10, 100);
    }

    /// A zero span is refused before any request.
    function testZeroSpanRefused() external {
        vm.expectRevert(abi.encodeWithSelector(LibTimelockOperations.ZeroLogSpan.selector));
        this.externalScheduledLogs(address(timelock), 0, 10, 0);
    }

    /// A governance timelock on Base and one operation it really scheduled:
    /// `updateDelay(172800)` on itself, scheduled with `schedule` in block
    /// `FORK_SCHEDULE_BLOCK` and since executed. Read off the chain's own
    /// `eth_getLogs` for that block, independently of this library.
    address constant FORK_TIMELOCK = address(0x48ba1371A78E6cC54157c63721756ab444510DB3);
    uint256 constant FORK_SCHEDULE_BLOCK = 50143676;
    uint256 constant FORK_SCHEDULE_TIMESTAMP = 1787076699;
    uint256 constant FORK_DELAY = 172800;
    bytes32 constant FORK_OPERATION_ID = 0x92707146398fe693c20e79ad13494d985affa342144be25ed3973d33063be358;
    /// A block after the operation executed.
    uint256 constant FORK_EXECUTED_BLOCK = 52562593;

    /// Pinned to the scheduling block itself, the operation is pending and
    /// reads back with its call, predecessor and ready time. The log sits in
    /// the fork's own block, the last one read.
    function testForkPendingOperationAtScheduleBlock() external {
        vm.createSelectFork(LibRainDeploy.BASE, FORK_SCHEDULE_BLOCK);
        TimelockOperation[] memory ops =
            LibTimelockOperations.pendingOperations(vm, FORK_TIMELOCK, FORK_SCHEDULE_BLOCK - 20, 10);
        assertEq(ops.length, 1);
        assertEq(ops[0].id, FORK_OPERATION_ID);
        assertEq(ops[0].predecessor, bytes32(0));
        assertEq(ops[0].readyAt, FORK_SCHEDULE_TIMESTAMP + FORK_DELAY);
        assertEq(ops[0].calls.length, 1);
        assertEq(ops[0].calls[0].target, FORK_TIMELOCK);
        assertEq(ops[0].calls[0].value, 0);
        assertEq(ops[0].calls[0].data, abi.encodeWithSignature("updateDelay(uint256)", FORK_DELAY));
    }

    /// Pinned to the block before, nothing is scheduled yet: neither log nor
    /// state reaches past the fork's block.
    function testForkNothingBeforeScheduleBlock() external {
        vm.createSelectFork(LibRainDeploy.BASE, FORK_SCHEDULE_BLOCK - 1);
        assertEq(LibTimelockOperations.pendingOperations(vm, FORK_TIMELOCK, FORK_SCHEDULE_BLOCK - 20, 10).length, 0);
    }

    /// The three-argument form reads the same as an explicit span.
    function testForkDefaultSpan() external {
        vm.createSelectFork(LibRainDeploy.BASE, FORK_SCHEDULE_BLOCK);
        TimelockOperation[] memory ops = LibTimelockOperations.pendingOperations(vm, FORK_TIMELOCK, FORK_SCHEDULE_BLOCK);
        assertEq(ops.length, 1);
        assertEq(ops[0].id, FORK_OPERATION_ID);
    }

    /// Every span reads the log exactly once, whether the scheduling block
    /// starts a chunk, ends one, sits inside one or is the whole range.
    function testForkScheduledLogsEverySpan() external {
        vm.createSelectFork(LibRainDeploy.BASE, FORK_SCHEDULE_BLOCK);
        uint256 fromBlock = FORK_SCHEDULE_BLOCK - 3;
        uint256 toBlock = FORK_SCHEDULE_BLOCK + 3;
        for (uint256 span = 1; span <= 8; span++) {
            Vm.EthGetLogs[] memory logs =
                LibTimelockOperations.scheduledLogs(vm, FORK_TIMELOCK, fromBlock, toBlock, span);
            assertEq(logs.length, 1, "one log");
            assertEq(logs[0].blockNumber, FORK_SCHEDULE_BLOCK);
            assertEq(logs[0].emitter, FORK_TIMELOCK);
            assertEq(logs[0].topics[1], FORK_OPERATION_ID);
        }
        assertEq(
            LibTimelockOperations.scheduledLogs(vm, FORK_TIMELOCK, FORK_SCHEDULE_BLOCK, FORK_SCHEDULE_BLOCK, 1).length, 1
        );
        assertEq(
            LibTimelockOperations.scheduledLogs(vm, FORK_TIMELOCK, fromBlock, FORK_SCHEDULE_BLOCK - 1, 2).length, 0
        );
    }

    /// Once executed, the same logs read back as nothing pending.
    function testForkExecutedOperationNotPending() external {
        vm.createSelectFork(LibRainDeploy.BASE, FORK_EXECUTED_BLOCK);
        assertTrue(ITimelockOperationState(FORK_TIMELOCK).getTimestamp(FORK_OPERATION_ID) == 1, "done");
        Vm.EthGetLogs[] memory logs =
            LibTimelockOperations.scheduledLogs(vm, FORK_TIMELOCK, FORK_SCHEDULE_BLOCK - 3, FORK_SCHEDULE_BLOCK + 3, 7);
        assertEq(logs.length, 1);
        assertEq(LibTimelockOperations.pendingFromLogs(logs, FORK_TIMELOCK).length, 0);
    }
}
