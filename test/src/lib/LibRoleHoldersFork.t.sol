// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {LibRoleHolders, RoleGrant} from "../../../src/lib/LibRoleHolders.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";

/// The `AccessControl` writes the tests drive on the fork.
interface IRoleAdmin {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
}

/// @title LibRoleHoldersForkTest
/// @notice Enumeration against a live OpenZeppelin `TimelockController` on
/// Base, whose whole role history is the four grants its constructor emits.
///
/// The expected membership is OpenZeppelin's constructor, not this library:
/// `DEFAULT_ADMIN_ROLE` to the timelock itself, `PROPOSER_ROLE` and
/// `CANCELLER_ROLE` to each proposer, `EXECUTOR_ROLE` to each executor, and the
/// one executor this timelock was built with is `address(0)` (open execution).
/// That last pair is the point: a `hasRole` check over a map that forgot it
/// still passes, and the replay names it.
///
/// Public Base endpoints cap one `eth_getLogs` call at 200 blocks
/// (mainnet.base.org), 1000 (tenderly) and 10000 (drpc), so every fetch here
/// stays within 200.
contract LibRoleHoldersForkTest is Test {
    address constant TIMELOCK = 0x48ba1371A78E6cC54157c63721756ab444510DB3;
    address constant PROPOSER = 0xe70d821f3462a074e63b42d0AaC6523faAe1d611;
    /// The block whose transaction created `TIMELOCK`.
    uint256 constant CREATION_BLOCK = 49872773;
    /// Ten blocks after creation: a window several chunks long at one block a
    /// chunk, with nothing in it after the constructor.
    uint256 constant FORK_BLOCK = CREATION_BLOCK + 10;
    uint256 constant MAX_RANGE = 200;

    bytes32 constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
    bytes32 constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    function setUp() external {
        vm.createSelectFork(LibRainDeploy.BASE, FORK_BLOCK);
    }

    function constructorGrants() internal pure returns (RoleGrant[] memory grants) {
        grants = new RoleGrant[](4);
        grants[0] = RoleGrant(DEFAULT_ADMIN_ROLE, TIMELOCK);
        grants[1] = RoleGrant(PROPOSER_ROLE, PROPOSER);
        grants[2] = RoleGrant(CANCELLER_ROLE, PROPOSER);
        grants[3] = RoleGrant(EXECUTOR_ROLE, address(0));
    }

    function assertGrantsEq(RoleGrant[] memory actual, RoleGrant[] memory expected) internal pure {
        assertEq(actual.length, expected.length);
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(actual[i].role, expected[i].role);
            assertEq(actual[i].grantee, expected[i].grantee);
        }
    }

    function externalHoldersOf(uint256 fromBlock, uint256 maxRange) external view returns (RoleGrant[] memory) {
        return LibRoleHolders.holdersOf(vm, TIMELOCK, fromBlock, maxRange);
    }

    function externalAssertNoUnmappedHolder(RoleGrant[] memory grants) external view {
        LibRoleHolders.assertNoUnmappedHolder(vm, TIMELOCK, grants, CREATION_BLOCK, MAX_RANGE);
    }

    function externalAssertMapHeld(RoleGrant[] memory grants) external view {
        LibRoleHolders.assertMapHeld(TIMELOCK, grants);
    }

    function externalFetch(uint256 fromBlock, uint256 toBlock, uint256 maxRange)
        external
        view
        returns (Vm.EthGetLogs[] memory)
    {
        return LibRoleHolders.fetchRoleLogs(vm, TIMELOCK, fromBlock, toBlock, maxRange);
    }

    function testHoldersOfIsTheConstructorGrants() external view {
        assertGrantsEq(LibRoleHolders.holdersOf(vm, TIMELOCK, CREATION_BLOCK, MAX_RANGE), constructorGrants());
    }

    /// Fetching one block per chunk crosses a chunk boundary at every block
    /// and lands on the same stream as one call; so does a chunk wider than
    /// the window, and one exactly as wide.
    function testFetchChunkingIsInvisible() external view {
        Vm.EthGetLogs[] memory whole = LibRoleHolders.fetchRoleLogs(vm, TIMELOCK, CREATION_BLOCK, FORK_BLOCK, MAX_RANGE);
        assertEq(whole.length, 4);
        uint256[3] memory ranges = [uint256(1), 3, FORK_BLOCK - CREATION_BLOCK + 1];
        for (uint256 r = 0; r < ranges.length; r++) {
            Vm.EthGetLogs[] memory chunked =
                LibRoleHolders.fetchRoleLogs(vm, TIMELOCK, CREATION_BLOCK, FORK_BLOCK, ranges[r]);
            assertEq(chunked.length, whole.length);
            for (uint256 i = 0; i < whole.length; i++) {
                assertEq(chunked[i].blockNumber, whole[i].blockNumber);
                assertEq(chunked[i].logIndex, whole[i].logIndex);
                assertEq(chunked[i].topics[1], whole[i].topics[1]);
            }
        }
    }

    /// The constructor's `MinDelayChange` log shares the creation block with
    /// the grants; the fetch asks only for the two role events.
    function testFetchReturnsOnlyRoleLogsInOrder() external view {
        Vm.EthGetLogs[] memory logs = LibRoleHolders.fetchRoleLogs(vm, TIMELOCK, CREATION_BLOCK, FORK_BLOCK, MAX_RANGE);
        assertEq(logs.length, 4);
        RoleGrant[] memory expected = constructorGrants();
        for (uint256 i = 0; i < logs.length; i++) {
            assertEq(logs[i].emitter, TIMELOCK);
            assertEq(logs[i].blockNumber, CREATION_BLOCK);
            assertEq(logs[i].topics[0], LibRoleHolders.ROLE_GRANTED_TOPIC);
            assertEq(logs[i].topics[1], expected[i].role);
            if (i > 0) {
                assertGt(logs[i].logIndex, logs[i - 1].logIndex);
            }
        }
    }

    /// A window that ends before creation fetches nothing; one that starts
    /// at the last block before it reaches the grants.
    function testFetchWindowEdges() external view {
        assertEq(LibRoleHolders.fetchRoleLogs(vm, TIMELOCK, CREATION_BLOCK - 5, CREATION_BLOCK - 1, 1).length, 0);
        assertEq(LibRoleHolders.fetchRoleLogs(vm, TIMELOCK, CREATION_BLOCK - 1, CREATION_BLOCK, 1).length, 4);
        assertEq(LibRoleHolders.fetchRoleLogs(vm, TIMELOCK, CREATION_BLOCK, CREATION_BLOCK, 1).length, 4);
    }

    function testFetchRejectsZeroRange() external {
        vm.expectRevert(
            abi.encodeWithSelector(LibRoleHolders.InvalidLogRange.selector, CREATION_BLOCK, FORK_BLOCK, uint256(0))
        );
        this.externalFetch(CREATION_BLOCK, FORK_BLOCK, 0);
    }

    function testFetchRejectsInvertedRange() external {
        vm.expectRevert(
            abi.encodeWithSelector(LibRoleHolders.InvalidLogRange.selector, FORK_BLOCK, CREATION_BLOCK, MAX_RANGE)
        );
        this.externalFetch(FORK_BLOCK, CREATION_BLOCK, MAX_RANGE);
    }

    /// `holdersOf` reads through the selected block, so a `fromBlock` past it
    /// is an inverted range.
    function testHoldersOfRejectsFromBlockPastSelectedBlock() external {
        vm.expectRevert(
            abi.encodeWithSelector(LibRoleHolders.InvalidLogRange.selector, FORK_BLOCK + 1, FORK_BLOCK, MAX_RANGE)
        );
        this.externalHoldersOf(FORK_BLOCK + 1, MAX_RANGE);
    }

    /// A pinned map that leaves out open execution still passes the `hasRole`
    /// check over the map; enumeration finds the pair it left out.
    function testUnmappedHolderInvisibleToMapCheckIsFound() external {
        RoleGrant[] memory full = constructorGrants();
        RoleGrant[] memory withoutExecutor = new RoleGrant[](3);
        for (uint256 i = 0; i < 3; i++) {
            withoutExecutor[i] = full[i];
        }
        this.externalAssertMapHeld(withoutExecutor);
        vm.expectRevert(
            abi.encodeWithSelector(LibRoleHolders.UnmappedHolder.selector, TIMELOCK, EXECUTOR_ROLE, address(0))
        );
        this.externalAssertNoUnmappedHolder(withoutExecutor);
    }

    /// The first unmapped pair in grant order is the one named.
    function testUnmappedHolderNamesFirstUnmappedPair() external {
        vm.expectRevert(
            abi.encodeWithSelector(LibRoleHolders.UnmappedHolder.selector, TIMELOCK, DEFAULT_ADMIN_ROLE, TIMELOCK)
        );
        this.externalAssertNoUnmappedHolder(new RoleGrant[](0));
    }

    function testNoUnmappedHolderPassesOnTheFullMap() external view {
        LibRoleHolders.assertNoUnmappedHolder(vm, TIMELOCK, constructorGrants(), CREATION_BLOCK, MAX_RANGE);
        LibRoleHolders.assertMapHeld(TIMELOCK, constructorGrants());
    }

    /// A map row the contract does not hold is named.
    function testMapHeldNamesMissingGrant() external {
        RoleGrant[] memory grants = constructorGrants();
        grants[2] = RoleGrant(CANCELLER_ROLE, address(0));
        vm.expectRevert(
            abi.encodeWithSelector(LibRoleHolders.ExpectedGrantMissing.selector, TIMELOCK, CANCELLER_ROLE, address(0))
        );
        this.externalAssertMapHeld(grants);
    }

    /// A revoke the fetched logs do not contain leaves the replay claiming a
    /// pair the contract no longer holds.
    function testReplayHeldButStateRevoked() external {
        vm.prank(TIMELOCK);
        IRoleAdmin(TIMELOCK).revokeRole(PROPOSER_ROLE, PROPOSER);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRoleHolders.ReplayDisagreesWithState.selector, TIMELOCK, PROPOSER_ROLE, PROPOSER, true
            )
        );
        this.externalHoldersOf(CREATION_BLOCK, MAX_RANGE);
    }

    /// A grant of a pair the replay never saw is invisible to it: no log, no
    /// pair to check. This is the bound `fromBlock` at or before creation
    /// exists to keep closed for history.
    function testGrantWithoutLogIsInvisible() external {
        address stranger = makeAddr("stranger");
        vm.prank(TIMELOCK);
        IRoleAdmin(TIMELOCK).grantRole(PROPOSER_ROLE, stranger);
        assertTrue(IRoleAdmin(TIMELOCK).hasRole(PROPOSER_ROLE, stranger));
        assertGrantsEq(this.externalHoldersOf(CREATION_BLOCK, MAX_RANGE), constructorGrants());
    }

    /// Starting after creation misses every constructor grant: the
    /// documented precondition, pinned.
    function testFromBlockAfterCreationMissesHistory() external view {
        assertEq(LibRoleHolders.holdersOf(vm, TIMELOCK, CREATION_BLOCK + 1, MAX_RANGE).length, 0);
    }
}
