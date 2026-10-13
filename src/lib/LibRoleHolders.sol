// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";

/// @notice A `(role, grantee)` pair on an OpenZeppelin `AccessControl`.
struct RoleGrant {
    bytes32 role;
    address grantee;
}

/// @title LibRoleHolders
/// @notice Enumerates the holders of every role on an OpenZeppelin
/// `AccessControl` by replaying its `RoleGranted` / `RoleRevoked` logs, and
/// checks the result against a pinned `(role, grantee)` map.
///
/// `AccessControl` membership is not enumerable on chain: `hasRole` answers for
/// a pair already named, so a check over a pinned map alone cannot see a holder
/// the map does not name. Every membership change emits one of the two events,
/// so the log history up to a block is the complete membership at that block.
///
/// The replay is only complete when `fromBlock` is at or before the contract's
/// creation block: a grant emitted before it is never fetched, and its holder
/// is exactly the unmapped holder this exists to find. Every pair the replay
/// touches is checked against live `hasRole` state, which catches a fetch that
/// stops short of the selected block or drops logs inside the range, but
/// cannot see a pair whose every log fell outside it.
library LibRoleHolders {
    /// @notice A log in the replayed stream was emitted by another contract.
    error ForeignEmitter(address acl, address emitter);
    /// @notice A log in the replayed stream is marked removed by a reorg.
    error RemovedLog(uint64 blockNumber, uint256 logIndex);
    /// @notice The replayed stream is not strictly ascending by
    /// `(blockNumber, logIndex)`, so applying it in order would not reproduce
    /// the chain's order of grants and revokes.
    error LogsOutOfOrder(uint64 blockNumber, uint256 logIndex);
    /// @notice A role event does not carry the three indexed topics after its
    /// signature, or its account topic is not a left-padded address.
    error MalformedRoleLog(uint64 blockNumber, uint256 logIndex);
    /// @notice A fetch was asked for an empty block range or a chunk size of
    /// zero.
    error InvalidLogRange(uint256 fromBlock, uint256 toBlock, uint256 maxRange);
    /// @notice The replay and `hasRole` disagree on whether `grantee` holds
    /// `role`: the replayed logs do not describe the selected state.
    /// @param replayHeld What the replay concluded.
    error ReplayDisagreesWithState(address acl, bytes32 role, address grantee, bool replayHeld);
    /// @notice `grantee` holds `role` on `acl` and the pinned map does not
    /// assign it.
    error UnmappedHolder(address acl, bytes32 role, address grantee);
    /// @notice The pinned map assigns `role` to `grantee` and `acl` does not
    /// hold it.
    error ExpectedGrantMissing(address acl, bytes32 role, address grantee);

    /// @notice Whether `grants` assigns `role` to `grantee`.
    /// @param grants The map.
    /// @param role The role to look for.
    /// @param grantee The grantee to look for.
    /// @return Whether the pair is in the map.
    function mapAssigns(RoleGrant[] memory grants, bytes32 role, address grantee) internal pure returns (bool) {
        for (uint256 i = 0; i < grants.length; i++) {
            if (grants[i].role == role && grants[i].grantee == grantee) {
                return true;
            }
        }
        return false;
    }

    /// @notice Fetch every `RoleGranted` and `RoleRevoked` log `acl` emitted in
    /// `[fromBlock, toBlock]`, in chain order, from the selected fork's RPC.
    /// The range is fetched in chunks of at most `maxRange` blocks, because
    /// providers cap the block span of one `eth_getLogs` call.
    /// @param vm The Vm instance to fetch with.
    /// @param acl The `AccessControl` whose logs are fetched.
    /// @param fromBlock The first block fetched, inclusive.
    /// @param toBlock The last block fetched, inclusive.
    /// @param maxRange The most blocks one `eth_getLogs` call spans.
    /// @return The role logs, ascending by `(blockNumber, logIndex)`.
    function fetchRoleLogs(Vm vm, address acl, uint256 fromBlock, uint256 toBlock, uint256 maxRange)
        internal
        view
        returns (Vm.EthGetLogs[] memory)
    {
        if (maxRange == 0 || fromBlock > toBlock) {
            revert InvalidLogRange(fromBlock, toBlock, maxRange);
        }
        Vm.EthGetLogs[] memory logs = new Vm.EthGetLogs[](0);
        uint256 start = fromBlock;
        while (true) {
            uint256 end = chunkEnd(start, toBlock, maxRange);
            logs = concat(logs, fetchRoleLogsChunk(vm, acl, start, end));
            // `end` never passes `toBlock`, so equality is the exact test for
            // the last chunk; slither reads it as a strict equality on state
            // an attacker can move.
            // slither-disable-next-line incorrect-equality
            if (end == toBlock) {
                break;
            }
            start = end + 1;
        }
        return logs;
    }

    /// @notice The last block of the chunk that starts at `start`: `toBlock`
    /// when at most `maxRange` blocks remain, otherwise the block that makes
    /// the chunk exactly `maxRange` blocks long.
    /// @param start The chunk's first block. At most `toBlock`.
    /// @param toBlock The fetch's last block.
    /// @param maxRange The most blocks one chunk spans. Non-zero.
    /// @return The chunk's last block, inclusive.
    function chunkEnd(uint256 start, uint256 toBlock, uint256 maxRange) internal pure returns (uint256) {
        return toBlock - start < maxRange ? toBlock : start + maxRange - 1;
    }

    /// @notice One chunk of `fetchRoleLogs`: one `eth_getLogs` call per event,
    /// merged into chain order.
    /// @param vm The Vm instance to fetch with.
    /// @param acl The `AccessControl` whose logs are fetched.
    /// @param start The first block fetched, inclusive.
    /// @param end The last block fetched, inclusive.
    /// @return The chunk's role logs, ascending by `(blockNumber, logIndex)`.
    function fetchRoleLogsChunk(Vm vm, address acl, uint256 start, uint256 end)
        internal
        view
        returns (Vm.EthGetLogs[] memory)
    {
        bytes32[] memory filter = new bytes32[](1);
        filter[0] = IAccessControl.RoleGranted.selector;
        Vm.EthGetLogs[] memory granted = vm.eth_getLogs(start, end, acl, filter);
        filter[0] = IAccessControl.RoleRevoked.selector;
        return merge(granted, vm.eth_getLogs(start, end, acl, filter));
    }

    /// @notice Replay a role log stream into the state of every pair it
    /// touches. Logs with any other signature are skipped, so the stream may be
    /// every log `acl` emitted.
    /// @param acl The `AccessControl` the stream was fetched from.
    /// @param logs The stream, ascending by `(blockNumber, logIndex)`.
    /// @return Every pair the stream grants or revokes, in the order each
    /// first appears.
    /// @return Whether each of those pairs, positionally, is held after the
    /// stream's last log.
    function replayPairs(address acl, Vm.EthGetLogs[] memory logs)
        internal
        pure
        returns (RoleGrant[] memory, bool[] memory)
    {
        RoleGrant[] memory seen = new RoleGrant[](logs.length);
        bool[] memory seenHeld = new bool[](logs.length);
        uint256 seenLength = 0;

        for (uint256 i = 0; i < logs.length; i++) {
            Vm.EthGetLogs memory log = logs[i];
            if (log.emitter != acl) {
                revert ForeignEmitter(acl, log.emitter);
            }
            if (log.removed) {
                revert RemovedLog(log.blockNumber, log.logIndex);
            }
            // Logs are keyed by `(blockNumber, logIndex)`: a block tie falls
            // through to the index, so equality is part of the order. slither
            // reports the condition's own lines, not the `if`, hence the pair.
            // slither-disable-start incorrect-equality
            if (
                i > 0
                    && (log.blockNumber < logs[i - 1].blockNumber
                        || (log.blockNumber == logs[i - 1].blockNumber && log.logIndex <= logs[i - 1].logIndex))
            ) {
                revert LogsOutOfOrder(log.blockNumber, log.logIndex);
            }
            // slither-disable-end incorrect-equality
            // An anonymous event has no signature topic to read.
            // slither-disable-next-line incorrect-equality
            if (log.topics.length == 0) {
                continue;
            }
            bytes32 signature = log.topics[0];
            if (signature != IAccessControl.RoleGranted.selector && signature != IAccessControl.RoleRevoked.selector) {
                continue;
            }
            if (log.topics.length != 4 || uint256(log.topics[2]) > type(uint160).max) {
                revert MalformedRoleLog(log.blockNumber, log.logIndex);
            }
            bytes32 role = log.topics[1];
            address account = address(uint160(uint256(log.topics[2])));

            uint256 j = 0;
            while (j < seenLength && (seen[j].role != role || seen[j].grantee != account)) {
                j++;
            }
            if (j == seenLength) {
                seen[j] = RoleGrant(role, account);
                seenLength++;
            }
            // `signature` is one of the two role topics here; the grant topic
            // is the held one.
            // slither-disable-next-line incorrect-equality
            seenHeld[j] = signature == IAccessControl.RoleGranted.selector;
        }

        RoleGrant[] memory pairs = new RoleGrant[](seenLength);
        bool[] memory held = new bool[](seenLength);
        for (uint256 i = 0; i < seenLength; i++) {
            pairs[i] = seen[i];
            held[i] = seenHeld[i];
        }
        return (pairs, held);
    }

    /// @notice Replay a role log stream into the set of pairs held after its
    /// last log.
    /// @param acl The `AccessControl` the stream was fetched from.
    /// @param logs The stream, ascending by `(blockNumber, logIndex)`.
    /// @return Every pair held after the stream, in the order each
    /// first appears in it.
    function replay(address acl, Vm.EthGetLogs[] memory logs) internal pure returns (RoleGrant[] memory) {
        (RoleGrant[] memory pairs, bool[] memory held) = replayPairs(acl, logs);
        RoleGrant[] memory holders = heldOnly(pairs, held);
        return holders;
    }

    /// @notice Every `(role, grantee)` pair held on `acl` at the selected
    /// block, replayed from `fromBlock` through `block.number`. Every pair the
    /// replay touches is checked against `hasRole`, held and revoked alike.
    /// @param vm The Vm instance to fetch with.
    /// @param acl The `AccessControl` to enumerate.
    /// @param fromBlock A block at or before `acl`'s creation block.
    /// @param maxRange The most blocks one `eth_getLogs` call spans.
    /// @return Every pair held, in the order each first appears in the
    /// log history.
    function holdersOf(Vm vm, address acl, uint256 fromBlock, uint256 maxRange)
        internal
        view
        returns (RoleGrant[] memory)
    {
        (RoleGrant[] memory pairs, bool[] memory held) =
            replayPairs(acl, fetchRoleLogs(vm, acl, fromBlock, block.number, maxRange));
        for (uint256 i = 0; i < pairs.length; i++) {
            if (IAccessControl(acl).hasRole(pairs[i].role, pairs[i].grantee) != held[i]) {
                revert ReplayDisagreesWithState(acl, pairs[i].role, pairs[i].grantee, held[i]);
            }
        }
        RoleGrant[] memory holders = heldOnly(pairs, held);
        return holders;
    }

    /// @notice Assert no pair outside `grants` is held on `acl` at the
    /// selected block.
    /// @param vm The Vm instance to fetch with.
    /// @param acl The `AccessControl` to check.
    /// @param grants The pinned map.
    /// @param fromBlock A block at or before `acl`'s creation block.
    /// @param maxRange The most blocks one `eth_getLogs` call spans.
    function assertNoUnmappedHolder(Vm vm, address acl, RoleGrant[] memory grants, uint256 fromBlock, uint256 maxRange)
        internal
        view
    {
        RoleGrant[] memory holders = holdersOf(vm, acl, fromBlock, maxRange);
        for (uint256 i = 0; i < holders.length; i++) {
            if (!mapAssigns(grants, holders[i].role, holders[i].grantee)) {
                revert UnmappedHolder(acl, holders[i].role, holders[i].grantee);
            }
        }
    }

    /// @notice Assert every pair in `grants` is held on `acl`.
    /// @param acl The `AccessControl` to check.
    /// @param grants The pinned map.
    function assertMapHeld(address acl, RoleGrant[] memory grants) internal view {
        for (uint256 i = 0; i < grants.length; i++) {
            if (!IAccessControl(acl).hasRole(grants[i].role, grants[i].grantee)) {
                revert ExpectedGrantMissing(acl, grants[i].role, grants[i].grantee);
            }
        }
    }

    /// @notice The pairs whose `held` flag is set, in order.
    /// @param pairs The pairs.
    /// @param held Whether each pair is held.
    /// @return The held pairs.
    function heldOnly(RoleGrant[] memory pairs, bool[] memory held) internal pure returns (RoleGrant[] memory) {
        uint256 heldCount = 0;
        for (uint256 i = 0; i < pairs.length; i++) {
            if (held[i]) {
                heldCount++;
            }
        }
        RoleGrant[] memory holders = new RoleGrant[](heldCount);
        uint256 k = 0;
        for (uint256 i = 0; i < pairs.length; i++) {
            if (held[i]) {
                holders[k] = pairs[i];
                k++;
            }
        }
        return holders;
    }

    /// @notice Merge two streams that are each ascending by
    /// `(blockNumber, logIndex)` into one that is.
    /// @param a One stream.
    /// @param b The other stream.
    /// @return Both streams, ascending.
    function merge(Vm.EthGetLogs[] memory a, Vm.EthGetLogs[] memory b) internal pure returns (Vm.EthGetLogs[] memory) {
        Vm.EthGetLogs[] memory merged = new Vm.EthGetLogs[](a.length + b.length);
        uint256 i = 0;
        uint256 j = 0;
        for (uint256 k = 0; k < merged.length; k++) {
            // `j == b.length` is the exhausted-stream test and a block tie
            // falls through to the log index.
            // slither-disable-start incorrect-equality
            if (
                j == b.length
                    || (i < a.length
                        && (a[i].blockNumber < b[j].blockNumber
                            || (a[i].blockNumber == b[j].blockNumber && a[i].logIndex < b[j].logIndex)))
            ) {
                merged[k] = a[i];
                i++;
            } else {
                merged[k] = b[j];
                j++;
            }
            // slither-disable-end incorrect-equality
        }
        return merged;
    }

    /// @notice `a` followed by `b`.
    /// @param a The leading stream.
    /// @param b The trailing stream.
    /// @return `a` then `b`.
    function concat(Vm.EthGetLogs[] memory a, Vm.EthGetLogs[] memory b) internal pure returns (Vm.EthGetLogs[] memory) {
        Vm.EthGetLogs[] memory joined = new Vm.EthGetLogs[](a.length + b.length);
        for (uint256 i = 0; i < a.length; i++) {
            joined[i] = a[i];
        }
        for (uint256 i = 0; i < b.length; i++) {
            joined[a.length + i] = b[i];
        }
        return joined;
    }
}
