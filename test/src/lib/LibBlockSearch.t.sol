// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibBlockSearch} from "../../../src/lib/LibBlockSearch.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";

/// @title LibBlockSearchTest
/// Tests for `LibBlockSearch.isStartBlock` and `findDeployBlock` against the
/// Zoltu factory and a genesis predeploy on Base.
contract LibBlockSearchTest is Test {
    /// Base allocates the OP Stack WETH9 predeploy in its genesis block, so
    /// this address has code at block 0.
    address constant BASE_GENESIS_PREDEPLOY = 0x4200000000000000000000000000000000000006;

    /// Code hash of the Base genesis WETH9 predeploy, fixed by the genesis
    /// allocation and therefore identical at block 0 and block 1.
    bytes32 constant BASE_GENESIS_PREDEPLOY_CODEHASH =
        0x8a3a1f6a9f9dce633117adee5b458245835a8645a8c8726a26382a4622508b1c;

    /// The block at which the Zoltu factory first has its code on Base.
    uint256 constant ZOLTU_BASE_DEPLOY_BLOCK = 1117029;

    /// External wrapper for `isStartBlock` so that it can be called
    /// externally in tests.
    /// @param target The contract address to check.
    /// @param expectedCodeHash The code hash to look for.
    /// @param blockNumber The block number to check.
    /// @return True if the contract first appears at this block.
    function externalIsStartBlock(address target, bytes32 expectedCodeHash, uint256 blockNumber)
        external
        returns (bool)
    {
        bool isStart = LibBlockSearch.isStartBlock(vm, target, expectedCodeHash, blockNumber);
        return isStart;
    }

    /// External wrapper for `findDeployBlock` so that `vm.expectRevert`
    /// works at the correct call depth.
    /// @param target The contract address to search for.
    /// @param expectedCodeHash The expected code hash of the target.
    /// @param startBlock The earliest block to search from.
    /// @return The first block number where `target` has code.
    function externalFindDeployBlock(address target, bytes32 expectedCodeHash, uint256 startBlock)
        external
        returns (uint256)
    {
        uint256 deployBlock = LibBlockSearch.findDeployBlock(vm, target, expectedCodeHash, startBlock);
        return deployBlock;
    }

    /// `isStartBlock` MUST return false when the target has no code at the
    /// given block.
    function testIsStartBlockNoCode() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertFalse(LibBlockSearch.isStartBlock(vm, address(0xdead), bytes32(uint256(1)), block.number));
    }

    /// `isStartBlock` MUST return false when the target has the expected
    /// code hash at both the given block and the block before it.
    function testIsStartBlockCodeAtBothBlocks() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        // The Zoltu factory exists at the current block and the block
        // before it, so this is not a start block.
        assertFalse(
            LibBlockSearch.isStartBlock(
                vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, block.number
            )
        );
    }

    /// `isStartBlock` MUST return true when the target has the expected code
    /// hash at the given block but not at the block before it. Uses the
    /// actual Zoltu factory deploy block found by `findDeployBlock`.
    function testIsStartBlockAtDeployBlock() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        uint256 deployBlock =
            LibBlockSearch.findDeployBlock(vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, 0);
        assertTrue(
            LibBlockSearch.isStartBlock(
                vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, deployBlock
            )
        );
    }

    /// `isStartBlock` MUST restore the fork to its original block number.
    function testIsStartBlockRestoresFork() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        uint256 originalBlock = block.number;
        LibBlockSearch.isStartBlock(vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, 0);
        assertEq(block.number, originalBlock);
    }

    /// `findDeployBlock` MUST revert with `NotDeployed` when the target
    /// address has no code on the current fork.
    function testFindDeployBlockNotDeployedReverts() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        vm.expectRevert(abi.encodeWithSelector(LibBlockSearch.NotDeployed.selector, address(0xdead)));
        this.externalFindDeployBlock(address(0xdead), bytes32(0), 0);
    }

    /// `findDeployBlock` MUST revert with `UnexpectedDeployedCodeHash` when
    /// the target's code hash does not match the expected value.
    function testFindDeployBlockWrongCodeHashReverts() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        bytes32 wrongHash = bytes32(uint256(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedDeployedCodeHash.selector, wrongHash, LibRainDeploy.ZOLTU_FACTORY_CODEHASH
            )
        );
        this.externalFindDeployBlock(LibRainDeploy.ZOLTU_FACTORY, wrongHash, 0);
    }

    /// `findDeployBlock` MUST revert with `DeployedBeforeStartBlock` when
    /// the target already has code at the start block.
    function testFindDeployBlockDeployedBeforeStartBlockReverts() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        // Use the current block as startBlock — the Zoltu factory already
        // exists here, so the function should revert.
        uint256 startBlock = block.number;
        vm.expectRevert(
            abi.encodeWithSelector(
                LibBlockSearch.DeployedBeforeStartBlock.selector, LibRainDeploy.ZOLTU_FACTORY, startBlock
            )
        );
        this.externalFindDeployBlock(LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, startBlock);
    }

    /// `findDeployBlock` MUST return a block that `isStartBlock` confirms,
    /// and the fork MUST be restored to the original block number.
    /// Uses Base because the public Base RPC has full archive access.
    function testFindDeployBlockZoltuFactory() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        uint256 originalBlock = block.number;

        uint256 deployBlock =
            LibBlockSearch.findDeployBlock(vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, 0);

        // Fork must be restored to the original block.
        assertEq(block.number, originalBlock);

        // The result must be a valid start block.
        assertTrue(
            LibBlockSearch.isStartBlock(
                vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, deployBlock
            )
        );
    }

    /// `isStartBlock` MUST return true at block 0 for a target that already
    /// has the expected code hash in the genesis allocation. There is no block
    /// before genesis, so the code hash at the given block alone decides.
    function testIsStartBlockGenesisAllocationAtBlockZero() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertTrue(LibBlockSearch.isStartBlock(vm, BASE_GENESIS_PREDEPLOY, BASE_GENESIS_PREDEPLOY_CODEHASH, 0));
    }

    /// `isStartBlock` MUST return false at block 1 for a target from the
    /// genesis allocation, because block 0 already has the same code hash.
    function testIsStartBlockGenesisAllocationAtBlockOne() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertFalse(LibBlockSearch.isStartBlock(vm, BASE_GENESIS_PREDEPLOY, BASE_GENESIS_PREDEPLOY_CODEHASH, 1));
    }

    /// `isStartBlock` MUST return false for the block immediately after the
    /// deploy block. The block compared against is the immediately preceding
    /// one, which already has the expected code hash.
    function testIsStartBlockOneBlockAfterDeployBlock() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertFalse(
            LibBlockSearch.isStartBlock(
                vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, ZOLTU_BASE_DEPLOY_BLOCK + 1
            )
        );
    }

    /// `findDeployBlock` MUST return the exact block at which the target first
    /// has the expected code hash, including when that is the block the fork is
    /// currently at.
    function testFindDeployBlockExactZoltuBaseDeployBlock() external {
        vm.createSelectFork(LibRainDeploy.BASE, ZOLTU_BASE_DEPLOY_BLOCK);
        assertEq(
            LibBlockSearch.findDeployBlock(vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, 0),
            ZOLTU_BASE_DEPLOY_BLOCK
        );
    }

    /// `findDeployBlock` MUST leave the fork on its original block when it
    /// reverts because the target already has the expected code hash at the
    /// start block.
    function testFindDeployBlockRestoresForkOnDeployedBeforeStartBlockRevert() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        uint256 originalBlock = block.number;
        vm.expectRevert(
            abi.encodeWithSelector(
                LibBlockSearch.DeployedBeforeStartBlock.selector, LibRainDeploy.ZOLTU_FACTORY, ZOLTU_BASE_DEPLOY_BLOCK
            )
        );
        this.externalFindDeployBlock(
            LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, ZOLTU_BASE_DEPLOY_BLOCK
        );
        assertEq(block.number, originalBlock);
    }

    /// `findDeployBlock` MUST report `NotDeployed` for a target with no code,
    /// rather than a code hash mismatch against the hash an empty account
    /// answers with. Nothing at the address is not a deployment whose hash is
    /// wrong, and the two are only told apart when the expected hash is not
    /// the zero hash.
    function testFindDeployBlockNotDeployedTakesPrecedenceOverCodeHash() external {
        vm.expectRevert(abi.encodeWithSelector(LibBlockSearch.NotDeployed.selector, address(0xdead)));
        this.externalFindDeployBlock(address(0xdead), bytes32(uint256(1)), 0);
    }

    /// `isStartBlock` MUST read the code hash at the block it is handed, not at
    /// the one after it. The block immediately before the Zoltu factory deploy
    /// block has no code at the factory address at all, so it is not a start
    /// block, however the block after it reads.
    function testIsStartBlockOneBlockBeforeDeployBlock() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertFalse(
            LibBlockSearch.isStartBlock(
                vm, LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, ZOLTU_BASE_DEPLOY_BLOCK - 1
            )
        );
    }

    /// `findDeployBlock` MUST answer with a block it has read the expected code
    /// hash at, and MUST narrow the search on every step.
    ///
    /// The window here is the three blocks around the Zoltu factory deploy
    /// block, so the very first block the search reads IS the answer. A search
    /// that discards the block it just matched at answers with the block below
    /// it, and one that cannot narrow a window this small never settles at all,
    /// which is why the call is given a stipend: a search that halves its range
    /// reads a handful of blocks, and anything that does not runs out of gas
    /// instead of running forever.
    function testFindDeployBlockWhereTheFirstReadIsTheAnswer() external {
        vm.createSelectFork(LibRainDeploy.BASE, ZOLTU_BASE_DEPLOY_BLOCK + 1);
        assertEq(
            this.externalFindDeployBlock{gas: 1_000_000}(
                LibRainDeploy.ZOLTU_FACTORY, LibRainDeploy.ZOLTU_FACTORY_CODEHASH, ZOLTU_BASE_DEPLOY_BLOCK - 1
            ),
            ZOLTU_BASE_DEPLOY_BLOCK
        );
    }

    /// `isStartBlock` MUST refuse a zero `expectedCodeHash` rather than answer
    /// true for an address no contract has ever existed at. Block 0 of Base is
    /// such a block for this address, and it is the case the guard has to take:
    /// at block 0 only the one read happens, so a zero expectation is met
    /// outright.
    function testIsStartBlockZeroCodeHashWhereNoContractEverExisted() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        vm.rollFork(uint256(0));
        assertEq(address(0xdead).codehash, bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(LibBlockSearch.NoExpectedCodeHash.selector, address(0xdead)));
        this.externalIsStartBlock(address(0xdead), bytes32(0), 0);
    }

    /// `isStartBlock` MUST refuse a zero `expectedCodeHash` at the genuine
    /// start block of a real contract, where the true code hash answers true
    /// and zero answers false.
    function testIsStartBlockZeroCodeHashAtGenuineStartBlock() external {
        vm.createSelectFork(LibRainDeploy.BASE, ZOLTU_BASE_DEPLOY_BLOCK);
        assertGt(LibRainDeploy.ZOLTU_FACTORY.code.length, 0);
        vm.expectRevert(abi.encodeWithSelector(LibBlockSearch.NoExpectedCodeHash.selector, LibRainDeploy.ZOLTU_FACTORY));
        this.externalIsStartBlock(LibRainDeploy.ZOLTU_FACTORY, bytes32(0), ZOLTU_BASE_DEPLOY_BLOCK);
    }
}
