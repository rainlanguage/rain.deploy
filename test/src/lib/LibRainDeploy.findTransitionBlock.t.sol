// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {MockBlockGatedAnswer} from "../../concrete/MockBlockGatedAnswer.sol";

/// @title LibRainDeployFindTransitionBlockTest
/// Tests for `LibRainDeploy.findTransitionBlock` against a real ownership
/// transfer on Base.
///
/// The transition is the st0x orchestrator beacon's `owner()` moving from a
/// Safe to a timelock. The block it happened in is pinned from the
/// `OwnershipTransferred(safe, timelock)` log the beacon emitted there, read
/// with `eth_getLogs` independently of any search, and the owners either side
/// of it from `cast call --block` at that block and the one before.
contract LibRainDeployFindTransitionBlockTest is Test {
    /// An `Ownable` beacon on Base whose owner changed exactly once.
    address constant BEACON = 0xb9DCd744b0413Dff0EDC70A5B229c7aa03734613;

    /// The beacon's owner before the transfer.
    address constant PRIOR_OWNER = 0xe70d821f3462a074e63b42d0AaC6523faAe1d611;

    /// The beacon's owner from the transfer on.
    address constant NEW_OWNER = 0x48ba1371A78E6cC54157c63721756ab444510DB3;

    /// The block the beacon's `OwnershipTransferred(PRIOR_OWNER, NEW_OWNER)`
    /// was emitted in.
    uint256 constant TRANSFER_BLOCK = 52_176_511;

    /// A block well before the transfer, at which the beacon's owner is not
    /// `NEW_OWNER`.
    uint256 constant SEARCH_START_BLOCK = 50_000_000;

    /// External wrapper so that `vm.expectRevert` works at the correct call
    /// depth.
    function externalFindTransitionBlock(
        address target,
        bytes memory readCall,
        bytes memory expectedAnswer,
        uint256 startBlock
    ) external returns (uint256) {
        return LibRainDeploy.findTransitionBlock(vm, target, readCall, expectedAnswer, startBlock);
    }

    /// The read the transition is found by.
    /// @return The calldata of `owner()`.
    function ownerCall() internal pure returns (bytes memory) {
        return abi.encodeWithSignature("owner()");
    }

    /// The search MUST answer the exact block the transfer was emitted in, and
    /// MUST leave the fork on the block it was called at.
    function testFindTransitionBlockOwnershipTransfer() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        uint256 originalBlock = block.number;
        assertEq(
            LibRainDeploy.findTransitionBlock(vm, BEACON, ownerCall(), abi.encode(NEW_OWNER), SEARCH_START_BLOCK),
            TRANSFER_BLOCK
        );
        assertEq(block.number, originalBlock);
    }

    /// The pinned block MUST be the transfer per the chain: the log is there,
    /// and the owner differs either side of it.
    function testTransferBlockPinIsTheTransfer() external {
        vm.createSelectFork(LibRainDeploy.BASE, TRANSFER_BLOCK);
        bytes32[] memory topics = new bytes32[](3);
        topics[0] = keccak256("OwnershipTransferred(address,address)");
        topics[1] = bytes32(uint256(uint160(PRIOR_OWNER)));
        topics[2] = bytes32(uint256(uint160(NEW_OWNER)));
        assertEq(vm.eth_getLogs(TRANSFER_BLOCK, TRANSFER_BLOCK, BEACON, topics).length, 1);
        (bool success, bytes memory answer) = BEACON.staticcall(ownerCall());
        assertTrue(success);
        assertEq(abi.decode(answer, (address)), NEW_OWNER);
        vm.rollFork(TRANSFER_BLOCK - 1);
        (success, answer) = BEACON.staticcall(ownerCall());
        assertTrue(success);
        assertEq(abi.decode(answer, (address)), PRIOR_OWNER);
    }

    /// The search MUST answer a block it has read the expected answer at, and
    /// MUST narrow on every step. The window is the three blocks around the
    /// transfer, so the first block read IS the answer; the stipend turns a
    /// search that never settles into an out-of-gas rather than a hang.
    function testFindTransitionBlockWhereTheFirstReadIsTheAnswer() external {
        vm.createSelectFork(LibRainDeploy.BASE, TRANSFER_BLOCK + 1);
        assertEq(
            this.externalFindTransitionBlock{gas: 1_000_000}(
                BEACON, ownerCall(), abi.encode(NEW_OWNER), TRANSFER_BLOCK - 1
            ),
            TRANSFER_BLOCK
        );
    }

    /// The search MUST find the transition when the fork is ON the transition
    /// block, i.e. the upper bound itself is the answer.
    function testFindTransitionBlockAtTheTransitionBlock() external {
        vm.createSelectFork(LibRainDeploy.BASE, TRANSFER_BLOCK);
        assertEq(
            LibRainDeploy.findTransitionBlock(vm, BEACON, ownerCall(), abi.encode(NEW_OWNER), SEARCH_START_BLOCK),
            TRANSFER_BLOCK
        );
    }

    /// The search MUST find the transition when the start block is the block
    /// immediately before it, the lowest start the precondition allows.
    function testFindTransitionBlockStartingOneBlockBefore() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertEq(
            LibRainDeploy.findTransitionBlock(vm, BEACON, ownerCall(), abi.encode(NEW_OWNER), TRANSFER_BLOCK - 1),
            TRANSFER_BLOCK
        );
    }

    /// The search MUST refuse a start block at which the read already answers
    /// the expected bytes, and MUST leave the fork where it was.
    function testFindTransitionBlockTransitionBeforeStartBlock() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        uint256 originalBlock = block.number;
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.TransitionBeforeStartBlock.selector, BEACON, TRANSFER_BLOCK)
        );
        this.externalFindTransitionBlock(BEACON, ownerCall(), abi.encode(NEW_OWNER), TRANSFER_BLOCK);
        assertEq(block.number, originalBlock);
    }

    /// The search MUST refuse when the read does not answer the expected bytes
    /// at the block the fork is on: before the transfer there is no transition
    /// to find.
    function testFindTransitionBlockNotReached() external {
        vm.createSelectFork(LibRainDeploy.BASE, TRANSFER_BLOCK - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.TransitionNotReached.selector,
                BEACON,
                ownerCall(),
                abi.encode(NEW_OWNER),
                true,
                abi.encode(PRIOR_OWNER)
            )
        );
        this.externalFindTransitionBlock(BEACON, ownerCall(), abi.encode(NEW_OWNER), SEARCH_START_BLOCK);
    }

    /// The answer MUST match byte for byte: the right word with trailing bytes
    /// is not the expected answer.
    function testFindTransitionBlockNotReachedOnLongerAnswer() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        bytes memory expected = abi.encodePacked(abi.encode(NEW_OWNER), bytes1(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.TransitionNotReached.selector, BEACON, ownerCall(), expected, true, abi.encode(NEW_OWNER)
            )
        );
        this.externalFindTransitionBlock(BEACON, ownerCall(), expected, SEARCH_START_BLOCK);
    }

    /// A read that reverts MUST NOT count as answering at the block the fork
    /// is on, even when its revert data is the expected bytes.
    function testFindTransitionBlockRevertingReadIsNotReached() external {
        vm.createSelectFork(LibRainDeploy.BASE, TRANSFER_BLOCK);
        bytes memory answer = abi.encode(NEW_OWNER);
        MockBlockGatedAnswer target = new MockBlockGatedAnswer(block.number + 1, answer);
        bytes memory readCall = abi.encodeWithSignature("read()");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.TransitionNotReached.selector, address(target), readCall, answer, false, answer
            )
        );
        this.externalFindTransitionBlock(address(target), readCall, answer, SEARCH_START_BLOCK);
    }

    /// A read that reverts MUST NOT count as answering during the search, even
    /// when its revert data is the expected bytes: a read that reverts before
    /// a block and returns from it transitions where it starts RETURNING. The
    /// mock is persistent so the same code answers at every block the search
    /// rolls to.
    function testFindTransitionBlockRevertingReadIsBeforeTheTransition() external {
        vm.createSelectFork(LibRainDeploy.BASE, TRANSFER_BLOCK);
        bytes memory answer = abi.encode(NEW_OWNER);
        uint256 from = TRANSFER_BLOCK - 12_345;
        MockBlockGatedAnswer target = new MockBlockGatedAnswer(from, answer);
        vm.makePersistent(address(target));
        assertEq(
            LibRainDeploy.findTransitionBlock(
                vm, address(target), abi.encodeWithSignature("read()"), answer, SEARCH_START_BLOCK
            ),
            from
        );
    }

    /// The search MUST refuse an empty expected answer, which a call to an
    /// account with no code meets at every block.
    function testFindTransitionBlockEmptyExpectedAnswer() external {
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoExpectedAnswer.selector, address(0xdead), ownerCall()));
        this.externalFindTransitionBlock(address(0xdead), ownerCall(), "", 0);
    }
}
