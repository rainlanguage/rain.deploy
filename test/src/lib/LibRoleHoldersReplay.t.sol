// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";

import {LibRoleHolders, RoleGrant} from "../../../src/lib/LibRoleHolders.sol";

/// @title LibRoleHoldersReplayTest
/// @notice The pure half of role enumeration: replaying a log stream into the
/// pairs it leaves held, merging per-event streams back into chain order, and
/// matching pairs against a map. The streams are built here, so every ordering
/// and malformation a provider could hand back is reachable without one.
contract LibRoleHoldersReplayTest is Test {
    address constant ACL = address(uint160(uint256(keccak256("role holders acl"))));
    address constant ALICE = address(uint160(uint256(keccak256("role holders alice"))));
    address constant BOB = address(uint160(uint256(keccak256("role holders bob"))));
    address constant SENDER = address(uint160(uint256(keccak256("role holders sender"))));
    bytes32 constant ROLE_A = keccak256("ROLE_A");
    bytes32 constant ROLE_B = keccak256("ROLE_B");

    function roleLog(bytes32 signature, bytes32 role, address account, uint64 blockNumber, uint256 logIndex)
        internal
        pure
        returns (Vm.EthGetLogs memory log)
    {
        bytes32[] memory topics = new bytes32[](4);
        topics[0] = signature;
        topics[1] = role;
        topics[2] = bytes32(uint256(uint160(account)));
        topics[3] = bytes32(uint256(uint160(SENDER)));
        log.emitter = ACL;
        log.topics = topics;
        log.blockNumber = blockNumber;
        log.logIndex = logIndex;
    }

    function stream1(Vm.EthGetLogs memory a) internal pure returns (Vm.EthGetLogs[] memory logs) {
        logs = new Vm.EthGetLogs[](1);
        logs[0] = a;
    }

    function stream2(Vm.EthGetLogs memory a, Vm.EthGetLogs memory b)
        internal
        pure
        returns (Vm.EthGetLogs[] memory logs)
    {
        logs = new Vm.EthGetLogs[](2);
        logs[0] = a;
        logs[1] = b;
    }

    function stream3(Vm.EthGetLogs memory a, Vm.EthGetLogs memory b, Vm.EthGetLogs memory c)
        internal
        pure
        returns (Vm.EthGetLogs[] memory logs)
    {
        logs = new Vm.EthGetLogs[](3);
        logs[0] = a;
        logs[1] = b;
        logs[2] = c;
    }

    function externalReplay(Vm.EthGetLogs[] memory logs) external pure returns (RoleGrant[] memory) {
        return LibRoleHolders.replay(ACL, logs);
    }

    function testReplayEmptyStreamHoldsNothing() external pure {
        assertEq(LibRoleHolders.replay(ACL, new Vm.EthGetLogs[](0)).length, 0);
    }

    function testReplayGrantIsHeld() external pure {
        RoleGrant[] memory holders =
            LibRoleHolders.replay(ACL, stream1(roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 1, 0)));
        assertEq(holders.length, 1);
        assertEq(holders[0].role, ROLE_A);
        assertEq(holders[0].grantee, ALICE);
    }

    function testReplayGrantThenRevokeIsNotHeld() external pure {
        RoleGrant[] memory holders = LibRoleHolders.replay(
            ACL,
            stream2(
                roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 1, 0),
                roleLog(IAccessControl.RoleRevoked.selector, ROLE_A, ALICE, 2, 0)
            )
        );
        assertEq(holders.length, 0);
    }

    function testReplayRevokeThenRegrantIsHeld() external pure {
        RoleGrant[] memory holders = LibRoleHolders.replay(
            ACL,
            stream3(
                roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 1, 0),
                roleLog(IAccessControl.RoleRevoked.selector, ROLE_A, ALICE, 1, 1),
                roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 3, 0)
            )
        );
        assertEq(holders.length, 1);
        assertEq(holders[0].grantee, ALICE);
    }

    /// A revoke of one pair leaves every other pair alone: same role other
    /// account, same account other role.
    function testReplayRevokeIsPerPair() external pure {
        Vm.EthGetLogs[] memory logs = new Vm.EthGetLogs[](4);
        logs[0] = roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 1, 0);
        logs[1] = roleLog(IAccessControl.RoleGranted.selector, ROLE_A, BOB, 1, 1);
        logs[2] = roleLog(IAccessControl.RoleGranted.selector, ROLE_B, ALICE, 1, 2);
        logs[3] = roleLog(IAccessControl.RoleRevoked.selector, ROLE_A, ALICE, 2, 0);
        RoleGrant[] memory holders = LibRoleHolders.replay(ACL, logs);
        assertEq(holders.length, 2);
        assertEq(holders[0].role, ROLE_A);
        assertEq(holders[0].grantee, BOB);
        assertEq(holders[1].role, ROLE_B);
        assertEq(holders[1].grantee, ALICE);
    }

    function testReplayPairsReportsRevokedPairs() external pure {
        (RoleGrant[] memory pairs, bool[] memory held) = LibRoleHolders.replayPairs(
            ACL,
            stream2(
                roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 1, 0),
                roleLog(IAccessControl.RoleRevoked.selector, ROLE_A, ALICE, 2, 0)
            )
        );
        assertEq(pairs.length, 1);
        assertEq(held.length, 1);
        assertEq(pairs[0].grantee, ALICE);
        assertFalse(held[0]);
    }

    /// A revoke for a pair never granted in the stream is still a pair the
    /// stream touched, and it is not held.
    function testReplayPairsReportsBareRevoke() external pure {
        (RoleGrant[] memory pairs, bool[] memory held) =
            LibRoleHolders.replayPairs(ACL, stream1(roleLog(IAccessControl.RoleRevoked.selector, ROLE_A, ALICE, 1, 0)));
        assertEq(pairs.length, 1);
        assertFalse(held[0]);
    }

    /// Any other event the contract emits (`RoleAdminChanged`, or anything
    /// else) is skipped, as is an anonymous log with no topics.
    /// `RoleAdminChanged(role, previousAdminRole, newAdminRole)` has the same
    /// four-topic shape as a role event, and a previous admin of
    /// `DEFAULT_ADMIN_ROLE` (zero) reads as `address(0)` in the account slot,
    /// which is a real grantee (open execution on a timelock). Read as a role
    /// event it would revoke that grant.
    function testReplaySkipsOtherEvents() external pure {
        Vm.EthGetLogs[] memory logs = new Vm.EthGetLogs[](4);
        logs[0] = roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 1, 0);
        logs[1] = roleLog(IAccessControl.RoleGranted.selector, ROLE_A, address(0), 1, 1);
        logs[2] = roleLog(IAccessControl.RoleAdminChanged.selector, ROLE_A, address(0), 1, 2);
        logs[2].topics[3] = ROLE_B;
        logs[3] = roleLog(IAccessControl.RoleGranted.selector, ROLE_A, BOB, 1, 3);
        logs[3].topics = new bytes32[](0);
        RoleGrant[] memory holders = LibRoleHolders.replay(ACL, logs);
        assertEq(holders.length, 2);
        assertEq(holders[0].role, ROLE_A);
        assertEq(holders[0].grantee, ALICE);
        assertEq(holders[1].role, ROLE_A);
        assertEq(holders[1].grantee, address(0));
    }

    function testReplayRejectsForeignEmitter() external {
        Vm.EthGetLogs memory log = roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 1, 0);
        log.emitter = BOB;
        vm.expectRevert(abi.encodeWithSelector(LibRoleHolders.ForeignEmitter.selector, ACL, BOB));
        this.externalReplay(stream1(log));
    }

    /// The emitter check covers skipped events too: a stream from the wrong
    /// contract is wrong whatever it holds.
    function testReplayRejectsForeignEmitterOnOtherEvent() external {
        Vm.EthGetLogs memory log = roleLog(keccak256("Other()"), ROLE_A, ALICE, 1, 0);
        log.emitter = BOB;
        vm.expectRevert(abi.encodeWithSelector(LibRoleHolders.ForeignEmitter.selector, ACL, BOB));
        this.externalReplay(stream1(log));
    }

    function testReplayRejectsRemovedLog() external {
        Vm.EthGetLogs memory log = roleLog(IAccessControl.RoleRevoked.selector, ROLE_A, ALICE, 7, 3);
        log.removed = true;
        vm.expectRevert(abi.encodeWithSelector(LibRoleHolders.RemovedLog.selector, uint64(7), uint256(3)));
        this.externalReplay(stream2(roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 1, 0), log));
    }

    function testReplayRejectsEarlierBlock() external {
        vm.expectRevert(abi.encodeWithSelector(LibRoleHolders.LogsOutOfOrder.selector, uint64(1), uint256(5)));
        this.externalReplay(
            stream2(
                roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 2, 0),
                roleLog(IAccessControl.RoleRevoked.selector, ROLE_A, ALICE, 1, 5)
            )
        );
    }

    function testReplayRejectsEarlierLogIndexInBlock() external {
        vm.expectRevert(abi.encodeWithSelector(LibRoleHolders.LogsOutOfOrder.selector, uint64(2), uint256(3)));
        this.externalReplay(
            stream2(
                roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 2, 4),
                roleLog(IAccessControl.RoleRevoked.selector, ROLE_A, ALICE, 2, 3)
            )
        );
    }

    /// A repeated `(blockNumber, logIndex)` is the same log twice, which a
    /// chunked fetch with overlapping ranges would produce.
    function testReplayRejectsDuplicateLog() external {
        vm.expectRevert(abi.encodeWithSelector(LibRoleHolders.LogsOutOfOrder.selector, uint64(2), uint256(4)));
        this.externalReplay(
            stream2(
                roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 2, 4),
                roleLog(IAccessControl.RoleGranted.selector, ROLE_A, BOB, 2, 4)
            )
        );
    }

    /// A later block with a lower log index is in order.
    function testReplayAcceptsLaterBlockLowerLogIndex() external pure {
        RoleGrant[] memory holders = LibRoleHolders.replay(
            ACL,
            stream2(
                roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 1, 9),
                roleLog(IAccessControl.RoleRevoked.selector, ROLE_A, ALICE, 2, 0)
            )
        );
        assertEq(holders.length, 0);
    }

    function testReplayRejectsShortRoleLog() external {
        Vm.EthGetLogs memory log = roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 4, 1);
        bytes32[] memory topics = new bytes32[](3);
        topics[0] = log.topics[0];
        topics[1] = log.topics[1];
        topics[2] = log.topics[2];
        log.topics = topics;
        vm.expectRevert(abi.encodeWithSelector(LibRoleHolders.MalformedRoleLog.selector, uint64(4), uint256(1)));
        this.externalReplay(stream1(log));
    }

    function testReplayRejectsLongRoleLog() external {
        Vm.EthGetLogs memory log = roleLog(IAccessControl.RoleRevoked.selector, ROLE_A, ALICE, 4, 1);
        bytes32[] memory topics = new bytes32[](5);
        for (uint256 i = 0; i < 4; i++) {
            topics[i] = log.topics[i];
        }
        log.topics = topics;
        vm.expectRevert(abi.encodeWithSelector(LibRoleHolders.MalformedRoleLog.selector, uint64(4), uint256(1)));
        this.externalReplay(stream1(log));
    }

    /// An account topic with any bit above the low 160 set is not an address
    /// the event could have indexed; truncating it would credit a holder the
    /// contract never named.
    function testReplayRejectsDirtyAccountTopic(uint256 dirt) external {
        dirt = bound(dirt, 1, type(uint96).max);
        Vm.EthGetLogs memory log = roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 4, 1);
        log.topics[2] = bytes32((dirt << 160) | uint256(uint160(ALICE)));
        vm.expectRevert(abi.encodeWithSelector(LibRoleHolders.MalformedRoleLog.selector, uint64(4), uint256(1)));
        this.externalReplay(stream1(log));
    }

    /// The highest clean account topic is accepted.
    function testReplayAcceptsMaxAddress() external pure {
        RoleGrant[] memory holders = LibRoleHolders.replay(
            ACL, stream1(roleLog(IAccessControl.RoleGranted.selector, ROLE_A, address(type(uint160).max), 1, 0))
        );
        assertEq(holders.length, 1);
        assertEq(holders[0].grantee, address(type(uint160).max));
    }

    function testMergeInterleavesByBlockThenLogIndex() external pure {
        Vm.EthGetLogs[] memory granted = stream3(
            roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 1, 0),
            roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 2, 5),
            roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 4, 0)
        );
        Vm.EthGetLogs[] memory revoked = stream3(
            roleLog(IAccessControl.RoleRevoked.selector, ROLE_A, ALICE, 1, 1),
            roleLog(IAccessControl.RoleRevoked.selector, ROLE_A, ALICE, 2, 4),
            roleLog(IAccessControl.RoleRevoked.selector, ROLE_A, ALICE, 3, 0)
        );
        Vm.EthGetLogs[] memory merged = LibRoleHolders.merge(granted, revoked);
        assertEq(merged.length, 6);
        uint64[6] memory blocks = [uint64(1), 1, 2, 2, 3, 4];
        uint256[6] memory indexes = [uint256(0), 1, 4, 5, 0, 0];
        bytes32[6] memory signatures = [
            IAccessControl.RoleGranted.selector,
            IAccessControl.RoleRevoked.selector,
            IAccessControl.RoleRevoked.selector,
            IAccessControl.RoleGranted.selector,
            IAccessControl.RoleRevoked.selector,
            IAccessControl.RoleGranted.selector
        ];
        for (uint256 i = 0; i < 6; i++) {
            assertEq(merged[i].blockNumber, blocks[i]);
            assertEq(merged[i].logIndex, indexes[i]);
            assertEq(merged[i].topics[0], signatures[i]);
        }
    }

    function testMergeWithEmptySide() external pure {
        Vm.EthGetLogs[] memory one = stream2(
            roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 1, 0),
            roleLog(IAccessControl.RoleGranted.selector, ROLE_A, BOB, 2, 0)
        );
        Vm.EthGetLogs[] memory left = LibRoleHolders.merge(one, new Vm.EthGetLogs[](0));
        Vm.EthGetLogs[] memory right = LibRoleHolders.merge(new Vm.EthGetLogs[](0), one);
        assertEq(left.length, 2);
        assertEq(right.length, 2);
        assertEq(left[1].blockNumber, 2);
        assertEq(right[1].blockNumber, 2);
    }

    /// Merged output of two ascending streams is ascending, whatever the two
    /// streams interleave as.
    function testMergeIsAscending(uint256 seed) external pure {
        Vm.EthGetLogs[] memory a = new Vm.EthGetLogs[](5);
        Vm.EthGetLogs[] memory b = new Vm.EthGetLogs[](5);
        uint64 blockA = 0;
        uint64 blockB = 0;
        for (uint256 i = 0; i < 5; i++) {
            blockA += uint64(uint256(keccak256(abi.encode(seed, "a", i))) % 3) + 1;
            blockB += uint64(uint256(keccak256(abi.encode(seed, "b", i))) % 3) + 1;
            a[i] = roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, blockA, 2 * i);
            b[i] = roleLog(IAccessControl.RoleRevoked.selector, ROLE_A, ALICE, blockB, 2 * i + 1);
        }
        Vm.EthGetLogs[] memory merged = LibRoleHolders.merge(a, b);
        assertEq(merged.length, 10);
        for (uint256 i = 1; i < merged.length; i++) {
            assertTrue(
                merged[i - 1].blockNumber < merged[i].blockNumber
                    || (merged[i - 1].blockNumber == merged[i].blockNumber
                        && merged[i - 1].logIndex < merged[i].logIndex)
            );
        }
    }

    function testConcatKeepsOrder() external pure {
        Vm.EthGetLogs[] memory joined = LibRoleHolders.concat(
            stream1(roleLog(IAccessControl.RoleGranted.selector, ROLE_A, ALICE, 1, 0)),
            stream2(
                roleLog(IAccessControl.RoleGranted.selector, ROLE_A, BOB, 2, 0),
                roleLog(IAccessControl.RoleGranted.selector, ROLE_B, BOB, 3, 0)
            )
        );
        assertEq(joined.length, 3);
        assertEq(joined[0].blockNumber, 1);
        assertEq(joined[1].blockNumber, 2);
        assertEq(joined[2].blockNumber, 3);
    }

    /// A chunk never spans more than `maxRange` blocks, which is the provider
    /// cap it exists to respect, and never runs past `toBlock`.
    function testChunkEndBoundaries() external pure {
        // Exactly `maxRange` blocks remain: one chunk takes them all.
        assertEq(LibRoleHolders.chunkEnd(100, 299, 200), 299);
        // One more than `maxRange` remain: the chunk stops one short.
        assertEq(LibRoleHolders.chunkEnd(100, 300, 200), 299);
        // Fewer remain.
        assertEq(LibRoleHolders.chunkEnd(100, 150, 200), 150);
        // A single block.
        assertEq(LibRoleHolders.chunkEnd(7, 7, 1), 7);
        assertEq(LibRoleHolders.chunkEnd(7, 8, 1), 7);
    }

    function testChunkEndSpan(uint256 start, uint256 toBlock, uint256 maxRange) external pure {
        toBlock = bound(toBlock, 0, type(uint64).max);
        start = bound(start, 0, toBlock);
        maxRange = bound(maxRange, 1, type(uint64).max);
        uint256 end = LibRoleHolders.chunkEnd(start, toBlock, maxRange);
        assertGe(end, start);
        assertLe(end, toBlock);
        assertLe(end - start + 1, maxRange);
        assertTrue(end == toBlock || end - start + 1 == maxRange);
    }

    function testMapAssignsMatchesBothFields() external pure {
        RoleGrant[] memory grants = new RoleGrant[](2);
        grants[0] = RoleGrant(ROLE_A, ALICE);
        grants[1] = RoleGrant(ROLE_B, BOB);
        assertTrue(LibRoleHolders.mapAssigns(grants, ROLE_A, ALICE));
        assertTrue(LibRoleHolders.mapAssigns(grants, ROLE_B, BOB));
        assertFalse(LibRoleHolders.mapAssigns(grants, ROLE_A, BOB));
        assertFalse(LibRoleHolders.mapAssigns(grants, ROLE_B, ALICE));
        assertFalse(LibRoleHolders.mapAssigns(new RoleGrant[](0), ROLE_A, ALICE));
    }
}
