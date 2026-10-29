// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDescribedByMeta} from "../../../src/lib/LibRainDeployDescribedByMeta.sol";
import {LocalLogsForkVm} from "../../concrete/LocalLogsForkVm.sol";
import {LibMetaV1_2Log} from "../../lib/LibMetaV1_2Log.sol";
import {
    FLARE_DESCRIBED,
    FLARE_DESCRIBED_BY_META,
    FLARE_DESCRIBED_BY_META_HASH,
    FLARE_EMISSION_BLOCK,
    FLARE_META_BOARD
} from "../../lib/FlareDescribedByMetaEmission.sol";

/// @title LibRainDeployDescribedByMetaIsEmittedAtTest
/// @notice `isEmittedAt` reads exactly the one block at the metaboard and needs a log whose subject and meta both
/// match: against Flare's emission at its block, and against logs set for that one query.
contract LibRainDeployDescribedByMetaIsEmittedAtTest is Test {
    LocalLogsForkVm internal sLogsVm;

    function setUp() external {
        sLogsVm = new LocalLogsForkVm();
    }

    function isEmittedOnFlareAt(address metaBoard, uint256 blockNumber, address described, bytes memory meta)
        internal
        returns (bool)
    {
        vm.createSelectFork(LibRainDeploy.FLARE);
        return LibRainDeployDescribedByMeta.isEmittedAt(vm, metaBoard, blockNumber, described, meta);
    }

    function isEmittedLocallyAt(address metaBoard, uint256 blockNumber, address described, bytes memory meta)
        internal
        view
        returns (bool)
    {
        return LibRainDeployDescribedByMeta.isEmittedAt(Vm(address(sLogsVm)), metaBoard, blockNumber, described, meta);
    }

    function testTheFlareEmissionBlockHoldsTheEmission() external {
        assertEq(keccak256(FLARE_DESCRIBED_BY_META), FLARE_DESCRIBED_BY_META_HASH);
        assertTrue(isEmittedOnFlareAt(FLARE_META_BOARD, FLARE_EMISSION_BLOCK, FLARE_DESCRIBED, FLARE_DESCRIBED_BY_META));
    }

    function testTheBlockBeforeTheFlareEmissionHoldsNone() external {
        assertFalse(
            isEmittedOnFlareAt(FLARE_META_BOARD, FLARE_EMISSION_BLOCK - 1, FLARE_DESCRIBED, FLARE_DESCRIBED_BY_META)
        );
    }

    function testTheBlockAfterTheFlareEmissionHoldsNone() external {
        assertFalse(
            isEmittedOnFlareAt(FLARE_META_BOARD, FLARE_EMISSION_BLOCK + 1, FLARE_DESCRIBED, FLARE_DESCRIBED_BY_META)
        );
    }

    function testAnotherSubjectAtTheFlareEmissionBlockIsNotEmitted() external {
        address other = address(uint160(FLARE_DESCRIBED) ^ 1);
        assertFalse(isEmittedOnFlareAt(FLARE_META_BOARD, FLARE_EMISSION_BLOCK, other, FLARE_DESCRIBED_BY_META));
    }

    function testAnotherMetaAtTheFlareEmissionBlockIsNotEmitted() external {
        bytes memory other = bytes.concat(FLARE_DESCRIBED_BY_META);
        other[other.length - 1] = other[other.length - 1] ^ 0x01;
        assertFalse(isEmittedOnFlareAt(FLARE_META_BOARD, FLARE_EMISSION_BLOCK, FLARE_DESCRIBED, other));
    }

    function testAnotherMetaBoardAtTheFlareEmissionBlockIsNotEmitted() external {
        address other = address(uint160(FLARE_META_BOARD) ^ 1);
        assertFalse(isEmittedOnFlareAt(other, FLARE_EMISSION_BLOCK, FLARE_DESCRIBED, FLARE_DESCRIBED_BY_META));
    }

    function testAMatchingLogInTheBlockIsEmittedFromAnySender(
        address metaBoard,
        uint256 blockNumber,
        address sender,
        address described,
        bytes memory meta
    ) external {
        LibMetaV1_2Log.setInBlock(
            sLogsVm, block.chainid, blockNumber, metaBoard, LibMetaV1_2Log.one(metaBoard, sender, described, meta)
        );
        vm.expectCall(
            address(sLogsVm),
            abi.encodeCall(Vm.eth_getLogs, (blockNumber, blockNumber, metaBoard, LibMetaV1_2Log.topics())),
            1
        );
        assertTrue(isEmittedLocallyAt(metaBoard, blockNumber, described, meta));
    }

    function testAMatchingLogPastOthersIsEmitted(
        address metaBoard,
        uint256 blockNumber,
        address sender,
        address described,
        bytes memory meta
    ) external {
        Vm.EthGetLogs[] memory logs = new Vm.EthGetLogs[](3);
        logs[0] = LibMetaV1_2Log.log(metaBoard, sender, address(uint160(described) ^ 1), meta);
        logs[1] = LibMetaV1_2Log.log(metaBoard, sender, described, bytes.concat(meta, hex"00"));
        logs[2] = LibMetaV1_2Log.log(metaBoard, sender, described, meta);
        LibMetaV1_2Log.setInBlock(sLogsVm, block.chainid, blockNumber, metaBoard, logs);
        assertTrue(isEmittedLocallyAt(metaBoard, blockNumber, described, meta));
    }

    function testAnEmptyBlockIsNotEmitted(address metaBoard, uint256 blockNumber, address described, bytes memory meta)
        external
        view
    {
        assertFalse(isEmittedLocallyAt(metaBoard, blockNumber, described, meta));
    }

    function testTheSubjectWithAnotherMetaIsNotEmitted(
        address metaBoard,
        uint256 blockNumber,
        address sender,
        address described,
        bytes memory meta,
        bytes memory loggedMeta
    ) external {
        vm.assume(keccak256(loggedMeta) != keccak256(meta));
        LibMetaV1_2Log.setInBlock(
            sLogsVm, block.chainid, blockNumber, metaBoard, LibMetaV1_2Log.one(metaBoard, sender, described, loggedMeta)
        );
        assertFalse(isEmittedLocallyAt(metaBoard, blockNumber, described, meta));
    }

    function testTheMetaAboutAnotherSubjectIsNotEmitted(
        address metaBoard,
        uint256 blockNumber,
        address sender,
        address described,
        address loggedSubject,
        bytes memory meta
    ) external {
        vm.assume(loggedSubject != described);
        LibMetaV1_2Log.setInBlock(
            sLogsVm, block.chainid, blockNumber, metaBoard, LibMetaV1_2Log.one(metaBoard, sender, loggedSubject, meta)
        );
        assertFalse(isEmittedLocallyAt(metaBoard, blockNumber, described, meta));
    }
}
