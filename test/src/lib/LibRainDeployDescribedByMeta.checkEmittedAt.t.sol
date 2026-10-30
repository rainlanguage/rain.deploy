// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm, VmSafe} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    DescribedByMetaEmissionUndeclared,
    DescribedByMetaNotEmittedAt,
    LibRainDeployDescribedByMeta,
    MetaBoardNotDeployed
} from "../../../src/lib/LibRainDeployDescribedByMeta.sol";
import {LocalLogsForkVm} from "../../concrete/LocalLogsForkVm.sol";
import {
    FLARE_DESCRIBED,
    FLARE_DESCRIBED_BY_META,
    FLARE_EMISSION_BLOCK,
    FLARE_META_BOARD
} from "../../lib/FlareDescribedByMetaEmission.sol";

struct CheckEmittedAtCall {
    string network;
    string suite;
    uint256 chainId;
    address metaBoard;
    bool declared;
    uint256 blockNumber;
    address described;
    bytes meta;
}

/// @title LibRainDeployDescribedByMetaCheckEmittedAtTest
/// @notice `checkEmittedAt` refuses an undeclared emission block, a codeless metaboard and a declared block without
/// the emission, and passes Flare's emission at its block.
contract LibRainDeployDescribedByMetaCheckEmittedAtTest is Test {
    function externalCheckEmittedAt(Vm forkVm, CheckEmittedAtCall memory c) external view {
        LibRainDeployDescribedByMeta.checkEmittedAt(
            forkVm, c.network, c.suite, c.chainId, c.metaBoard, c.declared, c.blockNumber, c.described, c.meta
        );
    }

    function flareCheck(uint256 blockNumber) internal returns (CheckEmittedAtCall memory) {
        vm.createSelectFork(LibRainDeploy.FLARE);
        return CheckEmittedAtCall({
            network: LibRainDeploy.FLARE,
            suite: "described@0_0_1",
            chainId: 14,
            metaBoard: FLARE_META_BOARD,
            declared: true,
            blockNumber: blockNumber,
            described: FLARE_DESCRIBED,
            meta: FLARE_DESCRIBED_BY_META
        });
    }

    function expectNotEmittedAt(CheckEmittedAtCall memory c) internal {
        vm.expectRevert(abi.encodeWithSelector(DescribedByMetaNotEmittedAt.selector, c.suite, c.chainId, c.blockNumber));
        this.externalCheckEmittedAt(vm, c);
    }

    function testAnEmptyMetaChecksNothing(CheckEmittedAtCall memory c) external {
        c.meta = "";
        LocalLogsForkVm logsVm = new LocalLogsForkVm();
        vm.expectCall(address(logsVm), abi.encodeWithSelector(VmSafe.eth_getLogs.selector), 0);
        this.externalCheckEmittedAt(Vm(address(logsVm)), c);
    }

    function testANonEmptyMetaWithNoDeclaredBlockIsRefusedBeforeTheMetaBoard(CheckEmittedAtCall memory c) external {
        vm.assume(c.meta.length != 0);
        c.declared = false;
        c.metaBoard = makeAddr("codeless metaboard");
        vm.expectRevert(
            abi.encodeWithSelector(DescribedByMetaEmissionUndeclared.selector, c.network, c.suite, c.chainId)
        );
        this.externalCheckEmittedAt(vm, c);
    }

    function testADeclaredBlockOnACodelessMetaBoardIsRefused(CheckEmittedAtCall memory c) external {
        vm.assume(c.meta.length != 0);
        c.declared = true;
        c.metaBoard = makeAddr("codeless metaboard");
        vm.expectRevert(abi.encodeWithSelector(MetaBoardNotDeployed.selector, c.network, c.metaBoard));
        this.externalCheckEmittedAt(vm, c);
    }

    function testTheFlareEmissionAtItsBlockPasses() external {
        this.externalCheckEmittedAt(vm, flareCheck(FLARE_EMISSION_BLOCK));
    }

    function testTheBlockBeforeTheFlareEmissionIsRefused() external {
        expectNotEmittedAt(flareCheck(FLARE_EMISSION_BLOCK - 1));
    }

    function testTheBlockAfterTheFlareEmissionIsRefused() external {
        expectNotEmittedAt(flareCheck(FLARE_EMISSION_BLOCK + 1));
    }
}
