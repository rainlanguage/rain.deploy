// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploy} from "./LibRainDeploy.sol";

/// @title LibBlockSearch
/// Finds the block a state change happened in by binary searching a fork's
/// history: the block a contract's code first appeared in, or the block a view
/// read first answered a given value in. Requires an active fork with archive
/// access back to the start of the search, and leaves the fork on the block it
/// was called at.
library LibBlockSearch {
    /// Thrown when attempting to find the deploy block of a contract that has
    /// no code at the current block.
    error NotDeployed(address target);

    /// Thrown when a code hash check is handed the zero code hash. An account
    /// with no code answers `codehash` zero, so a zero expectation is met by
    /// the ABSENCE of a contract and missed at every block one exists. A true
    /// from it is indistinguishable at the call site from a real match.
    error NoExpectedCodeHash(address target);

    /// Thrown when the target already has code at the start block, meaning
    /// the deploy may have happened before the search range.
    error DeployedBeforeStartBlock(address target, uint256 startBlock);

    /// Thrown when a transition search is handed an empty expected answer. A
    /// call to an account with no code succeeds and answers nothing, so an
    /// empty expectation is met by the ABSENCE of a contract, the same hole
    /// `NoExpectedCodeHash` closes for a code hash.
    error NoExpectedAnswer(address target, bytes readCall);

    /// Thrown when the read does not answer the expected bytes at the block
    /// the fork is on, so there is no transition at or before it to find.
    /// @param target The address read.
    /// @param readCall The calldata of the read.
    /// @param expectedAnswer The answer the transition produces.
    /// @param success Whether the read returned rather than reverted.
    /// @param actualAnswer The bytes the read returned, or its revert data.
    error TransitionNotReached(address target, bytes readCall, bytes expectedAnswer, bool success, bytes actualAnswer);

    /// Thrown when the read already answers the expected bytes at the start
    /// block, meaning the transition may have happened before the search
    /// range.
    error TransitionBeforeStartBlock(address target, uint256 startBlock);

    /// Checks whether a block is the first block where a contract with the
    /// expected code hash exists. True when the target has the expected code
    /// hash at `blockNumber` and does NOT have it at `blockNumber - 1`. At
    /// block 0, only the first condition is checked. The fork is restored to
    /// its original block number after checking.
    ///
    /// "First" is only true of a target whose code hash is MONOTONE: once it
    /// equals `expectedCodeHash` at some block it equals it at every later
    /// block. This reads two adjacent blocks and nothing else, so on a target
    /// that held `expectedCodeHash`, lost it and holds it again — a pre-Cancun
    /// `SELFDESTRUCT` followed by a `CREATE2` redeploy of the same code at the
    /// same address, say — it answers true at EVERY block where the hash
    /// reappears, not only the earliest. Monotonicity is the caller's to know:
    /// two blocks cannot show it.
    /// @param vm The Vm instance for fork manipulation.
    /// @param target The contract address to check.
    /// @param expectedCodeHash The code hash to look for. MUST NOT be zero;
    /// `NoExpectedCodeHash` says why.
    /// @param blockNumber The block number to check.
    /// @return True if the contract first appears at this block.
    function isStartBlock(Vm vm, address target, bytes32 expectedCodeHash, uint256 blockNumber)
        internal
        returns (bool)
    {
        if (expectedCodeHash == bytes32(0)) {
            revert NoExpectedCodeHash(target);
        }

        uint256 originalBlock = block.number;
        vm.rollFork(blockNumber);
        bool isStart = target.codehash == expectedCodeHash;
        if (isStart && blockNumber > 0) {
            vm.rollFork(blockNumber - 1);
            isStart = target.codehash != expectedCodeHash;
        }
        vm.rollFork(originalBlock);
        return isStart;
    }

    /// Finds the block number at which a contract was first deployed by binary
    /// searching the fork history. Requires an active fork with archive access
    /// back to `startBlock`. The fork is restored to its original block
    /// number before returning. The target's code hash is verified against the
    /// expected value before searching.
    ///
    /// The search REQUIRES the target's code hash to be monotone over
    /// `[startBlock, block.number]`, in the sense `isStartBlock` describes.
    /// Against a target that held `expectedCodeHash`, lost it and holds it
    /// again, the search converges on one of those appearances with no way to
    /// say which, and the result is meaningless as the subgraph start block it
    /// is typically used as.
    ///
    /// That is the caller's precondition because nothing here can check it, and
    /// `isStartBlock` least of all. `high` is only ever a block where the code
    /// hash matches: it starts at the current block, checked above, and
    /// otherwise takes a `mid` the loop has just read as matching. `low` is
    /// either `startBlock`, checked above as NOT matching, or one past a `mid`
    /// the loop has just read as not matching. It cannot still be `startBlock`
    /// when the loop ends, because that needs `high` down at `startBlock` and
    /// `high` is only ever a matching block, so where they meet the hash
    /// matches and did not match at the block before — `isStartBlock`'s exact
    /// condition, satisfied by construction and satisfied on a non-monotone
    /// history just the same. Running it on the result would read two more
    /// archive blocks to agree with itself.
    /// @param vm The Vm instance for fork manipulation.
    /// @param target The contract address to search for.
    /// @param expectedCodeHash The expected code hash of the target contract.
    /// @param startBlock The earliest block to search from. The target MUST
    /// NOT have the expected code hash at this block.
    /// @return The first block number where `target` has the expected code
    /// hash.
    function findDeployBlock(Vm vm, address target, bytes32 expectedCodeHash, uint256 startBlock)
        internal
        returns (uint256)
    {
        if (target.code.length == 0) {
            revert NotDeployed(target);
        }
        if (target.codehash != expectedCodeHash) {
            revert LibRainDeploy.UnexpectedDeployedCodeHash(expectedCodeHash, target.codehash);
        }

        uint256 originalBlock = block.number;
        bytes memory context = abi.encode(expectedCodeHash);

        // Verify the target does not already have the expected code at
        // startBlock. If it does, the deploy happened before our search
        // range and the result would be meaningless.
        vm.rollFork(startBlock);
        if (codeHashHolds(target, context)) {
            vm.rollFork(originalBlock);
            revert DeployedBeforeStartBlock(target, startBlock);
        }

        return bisectFirstHoldingBlock(vm, codeHashHolds, target, context, startBlock, originalBlock);
    }

    /// Finds the block in which a view read of `target` first answered
    /// `expectedAnswer`, by binary searching the fork history: the block a
    /// state transition such as an ownership transfer or a role grant executed
    /// in. Requires an active fork with archive access back to `startBlock`.
    /// The fork is restored to its original block number before returning.
    ///
    /// The read is a `staticcall` of `readCall` against `target`, and it holds
    /// at a block when it returns AND its return data is byte-for-byte
    /// `expectedAnswer`. A read that reverts does not hold, whatever its revert
    /// data, so a target that gained the read in an upgrade reads as before
    /// the transition; so does one with no code yet, which answers empty
    /// bytes.
    ///
    /// The search REQUIRES the read to be monotone over
    /// `[startBlock, block.number]`: once it answers `expectedAnswer` it
    /// answers it at every later block. An owner that was handed away and back
    /// again breaks that, and the search converges on one of the handovers with
    /// no way to say which. Where the answer is `expectedAnswer` and was not at
    /// the block before follows by construction, as `findDeployBlock` sets out
    /// for the code hash case.
    /// @param vm The Vm instance for fork manipulation.
    /// @param target The address the read is sent to.
    /// @param readCall The calldata of the read, e.g.
    /// `abi.encodeCall(IERC5313.owner, ())`.
    /// @param expectedAnswer The exact return data the read answers once the
    /// transition has happened, e.g. `abi.encode(newOwner)`. MUST NOT be
    /// empty; `NoExpectedAnswer` says why.
    /// @param startBlock The earliest block to search from. The read MUST NOT
    /// answer `expectedAnswer` at this block.
    /// @return The first block at which the read answers `expectedAnswer`.
    function findTransitionBlock(
        Vm vm,
        address target,
        bytes memory readCall,
        bytes memory expectedAnswer,
        uint256 startBlock
    ) internal returns (uint256) {
        if (expectedAnswer.length == 0) {
            revert NoExpectedAnswer(target, readCall);
        }
        {
            (bool holds, bool success, bytes memory actualAnswer) = readAnswers(target, readCall, expectedAnswer);
            if (!holds) {
                revert TransitionNotReached(target, readCall, expectedAnswer, success, actualAnswer);
            }
        }

        uint256 originalBlock = block.number;
        bytes memory context = abi.encode(readCall, expectedAnswer);

        vm.rollFork(startBlock);
        if (readHolds(target, context)) {
            vm.rollFork(originalBlock);
            revert TransitionBeforeStartBlock(target, startBlock);
        }

        return bisectFirstHoldingBlock(vm, readHolds, target, context, startBlock, originalBlock);
    }

    /// Whether `target` has the code hash `context` encodes, at the block the
    /// fork is on.
    /// @param target The address checked.
    /// @param context `abi.encode(expectedCodeHash)`.
    /// @return True when the code hash matches.
    function codeHashHolds(address target, bytes memory context) private view returns (bool) {
        return target.codehash == abi.decode(context, (bytes32));
    }

    /// Whether a read answers `expectedAnswer`, at the block the fork is on.
    /// @param target The address read.
    /// @param readCall The calldata of the read.
    /// @param expectedAnswer The bytes the read must return.
    /// @return True when the read returns exactly `expectedAnswer`.
    /// @return Whether the read returned rather than reverted.
    /// @return The bytes the read returned, or its revert data.
    function readAnswers(address target, bytes memory readCall, bytes memory expectedAnswer)
        private
        view
        returns (bool, bool, bytes memory)
    {
        // The consumer supplies the read, so the call is low level by
        // construction: there is no interface here to call through.
        // slither-disable-next-line low-level-calls
        (bool success, bytes memory actualAnswer) = target.staticcall(readCall);
        bool holds = success && keccak256(actualAnswer) == keccak256(expectedAnswer);
        return (holds, success, actualAnswer);
    }

    /// `readAnswers` over a read and answer packed for
    /// `bisectFirstHoldingBlock`.
    /// @param target The address read.
    /// @param context `abi.encode(readCall, expectedAnswer)`.
    /// @return True when the read returns exactly `expectedAnswer`.
    function readHolds(address target, bytes memory context) private view returns (bool) {
        (bytes memory readCall, bytes memory expectedAnswer) = abi.decode(context, (bytes, bytes));
        (bool holds,,) = readAnswers(target, readCall, expectedAnswer);
        return holds;
    }

    /// The first block in `[low, high]` at which `holds` is true, by binary
    /// search, leaving the fork on `high`. The caller MUST have established
    /// that `holds` is false at `low` and true at `high`, and is responsible
    /// for `holds` being monotone over the range; `findDeployBlock` sets out
    /// why the answer is then the exact transition.
    /// @param vm The Vm instance for fork manipulation.
    /// @param holds The condition searched for.
    /// @param target The address `holds` is evaluated against.
    /// @param context The condition's parameters, as `holds` decodes them.
    /// @param low A block at which `holds` is false.
    /// @param high A block at which `holds` is true; the fork's original block.
    /// @return The first block at which `holds` is true.
    function bisectFirstHoldingBlock(
        Vm vm,
        function(address, bytes memory) view returns (bool) holds,
        address target,
        bytes memory context,
        uint256 low,
        uint256 high
    ) private returns (uint256) {
        uint256 originalBlock = high;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            vm.rollFork(mid);
            if (holds(target, context)) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        vm.rollFork(originalBlock);
        return low;
    }
}
