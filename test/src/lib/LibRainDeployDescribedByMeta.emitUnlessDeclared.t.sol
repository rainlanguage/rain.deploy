// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IMetaBoardV1_2} from "rain-metadata-0.1.43/src/interface/unstable/IMetaBoardV1_2.sol";
import {IMetaV1_2} from "rain-metadata-0.1.43/src/interface/unstable/IMetaV1_2.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    DescribedByMetaMismatch,
    DescribedByMetaNotEmittedAt,
    LibRainDeployDescribedByMeta,
    MetaBoardNotDeployed
} from "../../../src/lib/LibRainDeployDescribedByMeta.sol";
import {LocalLogsForkVm} from "../../concrete/LocalLogsForkVm.sol";
import {MockDescribedByMeta} from "../../concrete/MockDescribedByMeta.sol";
import {
    FLARE_DESCRIBED,
    FLARE_DESCRIBED_BY_META,
    FLARE_EMISSION_BLOCK,
    FLARE_META_BOARD
} from "../../lib/FlareDescribedByMetaEmission.sol";

struct EmitUnlessDeclaredCall {
    string suite;
    string network;
    uint256 chainId;
    address metaBoard;
    bool declared;
    uint256 blockNumber;
    address described;
    bytes meta;
    address deployer;
}

/// @title LibRainDeployDescribedByMetaEmitUnlessDeclaredTest
/// @notice `emitUnlessDeclared` skips where the declared block holds the emission, refuses where it does not, and
/// emits as the deployer where no block is declared, against Flare's emission at its block.
contract LibRainDeployDescribedByMetaEmitUnlessDeclaredTest is Test {
    function externalEmitUnlessDeclared(Vm forkVm, EmitUnlessDeclaredCall memory e) external {
        LibRainDeployDescribedByMeta.emitUnlessDeclared(
            forkVm,
            e.suite,
            e.network,
            e.chainId,
            e.metaBoard,
            e.declared,
            e.blockNumber,
            e.described,
            e.meta,
            e.deployer
        );
    }

    function flareEmission(bool declared, uint256 blockNumber) internal returns (EmitUnlessDeclaredCall memory) {
        vm.createSelectFork(LibRainDeploy.FLARE);
        return EmitUnlessDeclaredCall({
            suite: "described@0_0_1",
            network: LibRainDeploy.FLARE,
            chainId: 14,
            metaBoard: FLARE_META_BOARD,
            declared: declared,
            blockNumber: blockNumber,
            described: FLARE_DESCRIBED,
            meta: FLARE_DESCRIBED_BY_META,
            deployer: makeAddr("deployer")
        });
    }

    function testAnEmptyMetaReadsAndBroadcastsNothing(EmitUnlessDeclaredCall memory e) external {
        e.meta = "";
        LocalLogsForkVm logsVm = new LocalLogsForkVm();
        vm.expectCall(address(logsVm), abi.encodeWithSelector(Vm.eth_getLogs.selector), 0);
        vm.expectCall(address(logsVm), abi.encodeWithSelector(LocalLogsForkVm.startBroadcast.selector), 0);
        this.externalEmitUnlessDeclared(Vm(address(logsVm)), e);
    }

    function testANonEmptyMetaRefusesACodelessMetaBoard(EmitUnlessDeclaredCall memory e) external {
        vm.assume(e.meta.length != 0);
        e.metaBoard = makeAddr("codeless metaboard");
        vm.expectRevert(abi.encodeWithSelector(MetaBoardNotDeployed.selector, e.network, e.metaBoard));
        this.externalEmitUnlessDeclared(vm, e);
    }

    function testUndeclaredRefusesADeploymentAnsweringAnotherHash(EmitUnlessDeclaredCall memory e, bytes32 answer)
        external
    {
        vm.assume(e.meta.length != 0);
        vm.assume(answer != keccak256(e.meta));
        e.declared = false;
        e.metaBoard = makeAddr("metaboard");
        vm.etch(e.metaBoard, hex"00");
        e.described = address(new MockDescribedByMeta(answer));
        vm.expectCall(e.metaBoard, abi.encodeWithSelector(IMetaBoardV1_2.emitMeta.selector), 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                DescribedByMetaMismatch.selector, e.suite, e.described, true, answer, keccak256(e.meta)
            )
        );
        this.externalEmitUnlessDeclared(vm, e);
    }

    function testADeclaredBlockHoldingTheEmissionSkips() external {
        EmitUnlessDeclaredCall memory e = flareEmission(true, FLARE_EMISSION_BLOCK);
        vm.expectCall(FLARE_META_BOARD, abi.encodeWithSelector(IMetaBoardV1_2.emitMeta.selector), 0);
        this.externalEmitUnlessDeclared(vm, e);
    }

    function testADeclaredBlockBeforeTheEmissionIsRefused() external {
        EmitUnlessDeclaredCall memory e = flareEmission(true, FLARE_EMISSION_BLOCK - 1);
        vm.expectRevert(
            abi.encodeWithSelector(DescribedByMetaNotEmittedAt.selector, e.suite, e.chainId, FLARE_EMISSION_BLOCK - 1)
        );
        this.externalEmitUnlessDeclared(vm, e);
    }

    function testADeclaredBlockAfterTheEmissionIsRefused() external {
        EmitUnlessDeclaredCall memory e = flareEmission(true, FLARE_EMISSION_BLOCK + 1);
        vm.expectRevert(
            abi.encodeWithSelector(DescribedByMetaNotEmittedAt.selector, e.suite, e.chainId, FLARE_EMISSION_BLOCK + 1)
        );
        this.externalEmitUnlessDeclared(vm, e);
    }

    function testUndeclaredEmitsAsTheDeployerWhereTheChainAlreadyHoldsTheEmission() external {
        EmitUnlessDeclaredCall memory e = flareEmission(false, FLARE_EMISSION_BLOCK);
        vm.expectCall(
            FLARE_META_BOARD,
            abi.encodeCall(
                IMetaBoardV1_2.emitMeta, (bytes32(uint256(uint160(FLARE_DESCRIBED))), FLARE_DESCRIBED_BY_META)
            ),
            1
        );
        vm.expectEmit(FLARE_META_BOARD);
        emit IMetaV1_2.MetaV1_2(e.deployer, bytes32(uint256(uint160(FLARE_DESCRIBED))), FLARE_DESCRIBED_BY_META);
        this.externalEmitUnlessDeclared(vm, e);
    }
}
