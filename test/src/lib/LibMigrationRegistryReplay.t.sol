// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibMigrationRegistry} from "../../../src/lib/LibMigrationRegistry.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    IMigrationRegistryV2,
    Prerequisite,
    MIGRATION_HEAD_GENESIS
} from "../../../src/interface/IMigrationRegistryV2.sol";
import {IMigrationRegistryV3} from "../../../src/interface/IMigrationRegistryV3.sol";
import {MigrationRegistry} from "../../../src/concrete/MigrationRegistry.sol";
import {
    CREATION_CODE as MIGRATION_REGISTRY_V2_CREATION_CODE,
    BYTECODE_HASH as MIGRATION_REGISTRY_V2_CODEHASH
} from "../../../src/generated/0_1_18/MigrationRegistry.sol";

/// @title LibMigrationRegistryReplayTest
/// @notice `replayV2Call` against the released V2 registry: the calls it builds,
/// sent in order, reproduce each V2 record in the V3 registry.
contract LibMigrationRegistryReplayTest is Test {
    address internal constant WRITER = address(0x1111);
    address internal constant DELEGATE = address(0x2222);
    address internal constant OTHER = address(0x3333);
    bytes32 internal constant NAMESPACE = keccak256("namespace");
    bytes32 internal constant OTHER_NAMESPACE = keccak256("other namespace");
    bytes32 internal constant OTHER_MIGRATION = keccak256("other migration");
    bytes32 internal constant FIRST = keccak256("first");
    bytes32 internal constant SECOND = keccak256("second");
    bytes32 internal constant THIRD = keccak256("third");

    IMigrationRegistryV2 internal sV2;

    function setUp() external {
        vm.warp(1_000_000);
        sV2 = IMigrationRegistryV2(LibRainDeploy.etchAndDeployZoltu(vm, MIGRATION_REGISTRY_V2_CREATION_CODE));
    }

    function onto(address writer, bytes32 namespace, bytes32 head) internal pure returns (Prerequisite[] memory) {
        Prerequisite[] memory prerequisites = new Prerequisite[](1);
        prerequisites[0] = Prerequisite({writer: writer, namespace: namespace, migration: head});
        return prerequisites;
    }

    function externalReplay(address writer, bytes32 namespace) external view returns (address, bytes[] memory) {
        return LibMigrationRegistry.replayV2Call(sV2, writer, namespace);
    }

    /// Writes the V2 lines the round trip replays: one record under `OTHER`,
    /// then three under `WRITER`, the second waiting on `OTHER`'s and the third
    /// at the same moment as the second.
    function writeV2Lines() internal {
        vm.prank(OTHER);
        sV2.applyMigrationHistory(
            OTHER_NAMESPACE, OTHER_MIGRATION, 100, onto(OTHER, OTHER_NAMESPACE, MIGRATION_HEAD_GENESIS)
        );
        vm.startPrank(WRITER);
        sV2.applyMigrationHistory(NAMESPACE, FIRST, 200, onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS));
        Prerequisite[] memory afterOther = new Prerequisite[](2);
        afterOther[0] = Prerequisite({writer: WRITER, namespace: NAMESPACE, migration: FIRST});
        afterOther[1] = Prerequisite({writer: OTHER, namespace: OTHER_NAMESPACE, migration: OTHER_MIGRATION});
        sV2.applyMigrationHistory(NAMESPACE, SECOND, 300, afterOther);
        sV2.applyMigrationHistory(NAMESPACE, THIRD, 300, onto(WRITER, NAMESPACE, SECOND));
        vm.stopPrank();
    }

    function replay(address writer, bytes32 namespace, uint256 expectedLength) internal {
        (address to, bytes[] memory calls) = LibMigrationRegistry.replayV2Call(sV2, writer, namespace);
        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(calls.length, expectedLength);
        for (uint256 i = 0; i < calls.length; i++) {
            vm.prank(writer);
            (bool success,) = to.call(calls[i]);
            assertTrue(success);
        }
    }

    function assertRecordReplayed(IMigrationRegistryV3 v3, address writer, bytes32 namespace, bytes32 migration)
        internal
        view
    {
        assertTrue(sV2.applied(writer, namespace, migration) != 0);
        assertEq(v3.appliedV3(writer, namespace, migration), sV2.applied(writer, namespace, migration));
        assertEq(v3.appliedOntoV3(writer, namespace, migration), sV2.appliedOnto(writer, namespace, migration));
        assertEq(
            abi.encode(v3.appliedAfterV3(writer, namespace, migration)),
            abi.encode(sV2.appliedAfter(writer, namespace, migration))
        );
    }

    /// A three-record V2 line waiting on a record in another line, replayed
    /// after that line, matches V2 record for record and at the head.
    function testReplayRoundTripsAThreeRecordLine() external {
        IMigrationRegistryV3 v3 =
            IMigrationRegistryV3(LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode));
        writeV2Lines();

        replay(OTHER, OTHER_NAMESPACE, 1);
        replay(WRITER, NAMESPACE, 3);

        assertEq(v3.headV3(OTHER, OTHER_NAMESPACE), sV2.head(OTHER, OTHER_NAMESPACE));
        assertEq(v3.headV3(WRITER, NAMESPACE), sV2.head(WRITER, NAMESPACE));
        assertEq(v3.headV3(WRITER, NAMESPACE), THIRD);
        assertRecordReplayed(v3, OTHER, OTHER_NAMESPACE, OTHER_MIGRATION);
        assertRecordReplayed(v3, WRITER, NAMESPACE, FIRST);
        assertRecordReplayed(v3, WRITER, NAMESPACE, SECOND);
        assertRecordReplayed(v3, WRITER, NAMESPACE, THIRD);
    }

    /// The calls are the V2 records' history writes, oldest first.
    function testReplayCallsAreOldestFirst() external {
        LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
        writeV2Lines();
        (, bytes[] memory calls) = LibMigrationRegistry.replayV2Call(sV2, WRITER, NAMESPACE);
        assertEq(calls.length, 3);
        assertEq(
            calls[0],
            abi.encodeCall(
                IMigrationRegistryV3.applyMigrationHistoryV3,
                (WRITER, NAMESPACE, FIRST, 200, onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS))
            )
        );
        assertEq(
            calls[1],
            abi.encodeCall(
                IMigrationRegistryV3.applyMigrationHistoryV3,
                (WRITER, NAMESPACE, SECOND, 300, sV2.appliedAfter(WRITER, NAMESPACE, SECOND))
            )
        );
        assertEq(
            calls[2],
            abi.encodeCall(
                IMigrationRegistryV3.applyMigrationHistoryV3,
                (WRITER, NAMESPACE, THIRD, 300, onto(WRITER, NAMESPACE, SECOND))
            )
        );
    }

    /// An empty V2 line replays as no calls.
    function testReplayEmptyLineIsNoCalls() external {
        LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
        (address to, bytes[] memory calls) = LibMigrationRegistry.replayV2Call(sV2, WRITER, NAMESPACE);
        assertEq(to, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(calls.length, 0);
    }

    /// A chain without the V3 registry is refused by its code hash.
    function testReplayNoRegistryIsRefused() external {
        writeV2Lines();
        assertEq(LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS.code.length, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalReplay(WRITER, NAMESPACE);
    }

    function externalCheckV2Replayed(address writer, bytes32 namespace) external view {
        LibMigrationRegistry.checkV2Replayed(sV2, writer, namespace);
    }

    /// Code other than the released V2 registry at `v2` is refused before
    /// anything is read from it.
    function testReplayRefusesOtherCodeAtV2() external {
        LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
        writeV2Lines();
        bytes memory other = hex"00";
        vm.etch(address(sV2), other);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                MIGRATION_REGISTRY_V2_CODEHASH,
                keccak256(other)
            )
        );
        this.externalReplay(WRITER, NAMESPACE);
    }

    /// An address with no code at `v2` is refused by its code hash.
    function testReplayRefusesNoCodeAtV2() external {
        LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
        vm.etch(address(sV2), "");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                MIGRATION_REGISTRY_V2_CODEHASH,
                address(sV2).codehash
            )
        );
        this.externalReplay(WRITER, NAMESPACE);
    }

    /// Sends call `index` of `writer`'s replay from `writer`, returning whether
    /// it landed and what it returned.
    function sendReplayCall(address writer, bytes32 namespace, uint256 index) internal returns (bool, bytes memory) {
        (address to, bytes[] memory calls) = LibMigrationRegistry.replayV2Call(sV2, writer, namespace);
        vm.prank(writer);
        return to.call(calls[index]);
    }

    /// Writes two V2 lines that wait on each other: A1 and B1 at genesis, A2
    /// after B1, B2 after A1.
    function writeMutualV2Lines() internal {
        vm.prank(WRITER);
        sV2.applyMigrationHistory(NAMESPACE, FIRST, 100, onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS));
        vm.prank(OTHER);
        sV2.applyMigrationHistory(OTHER_NAMESPACE, FIRST, 100, onto(OTHER, OTHER_NAMESPACE, MIGRATION_HEAD_GENESIS));
        Prerequisite[] memory afterB1 = new Prerequisite[](2);
        afterB1[0] = Prerequisite({writer: WRITER, namespace: NAMESPACE, migration: FIRST});
        afterB1[1] = Prerequisite({writer: OTHER, namespace: OTHER_NAMESPACE, migration: FIRST});
        vm.prank(WRITER);
        sV2.applyMigrationHistory(NAMESPACE, SECOND, 200, afterB1);
        Prerequisite[] memory afterA1 = new Prerequisite[](2);
        afterA1[0] = Prerequisite({writer: OTHER, namespace: OTHER_NAMESPACE, migration: FIRST});
        afterA1[1] = Prerequisite({writer: WRITER, namespace: NAMESPACE, migration: FIRST});
        vm.prank(OTHER);
        sV2.applyMigrationHistory(OTHER_NAMESPACE, SECOND, 200, afterA1);
    }

    /// Two lines that wait on each other cannot be replayed line by line in
    /// either order: each stops at its second record, naming the other
    /// line's first. Interleaved, record by record, both land at their V2
    /// heads.
    function testReplayMutuallyWaitingLinesInterleaved() external {
        IMigrationRegistryV3 v3 =
            IMigrationRegistryV3(LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode));
        writeMutualV2Lines();
        uint256 fresh = vm.snapshotState();

        (bool success, bytes memory result) = sendReplayCall(WRITER, NAMESPACE, 0);
        assertTrue(success);
        (success, result) = sendReplayCall(WRITER, NAMESPACE, 1);
        assertFalse(success);
        assertEq(
            result,
            abi.encodeWithSelector(IMigrationRegistryV3.PrerequisiteNotApplied.selector, OTHER, OTHER_NAMESPACE, FIRST)
        );

        vm.revertToState(fresh);
        (success, result) = sendReplayCall(OTHER, OTHER_NAMESPACE, 0);
        assertTrue(success);
        (success, result) = sendReplayCall(OTHER, OTHER_NAMESPACE, 1);
        assertFalse(success);
        assertEq(
            result,
            abi.encodeWithSelector(IMigrationRegistryV3.PrerequisiteNotApplied.selector, WRITER, NAMESPACE, FIRST)
        );

        vm.revertToState(fresh);
        (success,) = sendReplayCall(WRITER, NAMESPACE, 0);
        assertTrue(success);
        (success,) = sendReplayCall(OTHER, OTHER_NAMESPACE, 0);
        assertTrue(success);
        (success,) = sendReplayCall(WRITER, NAMESPACE, 1);
        assertTrue(success);
        (success,) = sendReplayCall(OTHER, OTHER_NAMESPACE, 1);
        assertTrue(success);
        assertEq(v3.headV3(WRITER, NAMESPACE), SECOND);
        assertEq(v3.headV3(OTHER, OTHER_NAMESPACE), SECOND);
        assertRecordReplayed(v3, WRITER, NAMESPACE, FIRST);
        assertRecordReplayed(v3, WRITER, NAMESPACE, SECOND);
        assertRecordReplayed(v3, OTHER, OTHER_NAMESPACE, FIRST);
        assertRecordReplayed(v3, OTHER, OTHER_NAMESPACE, SECOND);
    }

    /// A replay sent by a delegate records the delegate as each record's
    /// author, and one sent by the writer records the writer.
    function testReplayAuthorIsTheSender() external {
        IMigrationRegistryV3 v3 =
            IMigrationRegistryV3(LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode));
        writeV2Lines();
        replay(OTHER, OTHER_NAMESPACE, 1);
        assertEq(v3.appliedByV3(OTHER, OTHER_NAMESPACE, OTHER_MIGRATION), OTHER);

        vm.prank(WRITER);
        v3.approveV3(NAMESPACE, DELEGATE);
        (address to, bytes[] memory calls) = LibMigrationRegistry.replayV2Call(sV2, WRITER, NAMESPACE);
        for (uint256 i = 0; i < calls.length; i++) {
            vm.prank(DELEGATE);
            (bool success,) = to.call(calls[i]);
            assertTrue(success);
        }
        assertEq(v3.appliedByV3(WRITER, NAMESPACE, FIRST), DELEGATE);
        assertEq(v3.appliedByV3(WRITER, NAMESPACE, SECOND), DELEGATE);
        assertEq(v3.appliedByV3(WRITER, NAMESPACE, THIRD), DELEGATE);
    }

    /// `checkV2Replayed` refuses a line whose V3 head is behind its V2 head,
    /// naming both heads, until the last record is replayed.
    function testCheckV2ReplayedRefusesUntilTheHeadsMatch() external {
        LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
        writeV2Lines();
        replay(OTHER, OTHER_NAMESPACE, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.V2LineNotReplayed.selector, WRITER, NAMESPACE, THIRD, MIGRATION_HEAD_GENESIS
            )
        );
        this.externalCheckV2Replayed(WRITER, NAMESPACE);

        (address to, bytes[] memory calls) = LibMigrationRegistry.replayV2Call(sV2, WRITER, NAMESPACE);
        for (uint256 i = 0; i < 2; i++) {
            vm.prank(WRITER);
            (bool success,) = to.call(calls[i]);
            assertTrue(success);
        }
        vm.expectRevert(
            abi.encodeWithSelector(LibMigrationRegistry.V2LineNotReplayed.selector, WRITER, NAMESPACE, THIRD, SECOND)
        );
        this.externalCheckV2Replayed(WRITER, NAMESPACE);

        vm.prank(WRITER);
        (bool landed,) = to.call(calls[2]);
        assertTrue(landed);
        this.externalCheckV2Replayed(WRITER, NAMESPACE);
        this.externalCheckV2Replayed(OTHER, OTHER_NAMESPACE);
    }

    /// A V3 line ahead of an empty V2 line is not a replay of it.
    function testCheckV2ReplayedRefusesALineAheadOfV2() external {
        IMigrationRegistryV3 v3 =
            IMigrationRegistryV3(LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode));
        this.externalCheckV2Replayed(WRITER, NAMESPACE);
        vm.prank(WRITER);
        v3.applyMigrationV3(WRITER, NAMESPACE, FIRST, onto(WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.V2LineNotReplayed.selector, WRITER, NAMESPACE, MIGRATION_HEAD_GENESIS, FIRST
            )
        );
        this.externalCheckV2Replayed(WRITER, NAMESPACE);
    }

    /// `checkV2Replayed` refuses other code at `v2`, and a chain without the
    /// V3 registry.
    function testCheckV2ReplayedRefusesUnknownCode() external {
        bytes memory other = hex"00";
        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                bytes32(0)
            )
        );
        this.externalCheckV2Replayed(WRITER, NAMESPACE);

        LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
        vm.etch(address(sV2), other);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibMigrationRegistry.UnexpectedMigrationRegistryCodeHash.selector,
                MIGRATION_REGISTRY_V2_CODEHASH,
                keccak256(other)
            )
        );
        this.externalCheckV2Replayed(WRITER, NAMESPACE);
    }
}
