// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IDescribedByMetaV1} from "rain-metadata-0.1.43/src/interface/IDescribedByMetaV1.sol";
import {DescribedByMetaMismatch, LibRainDeployDescribedByMeta} from "../../../src/lib/LibRainDeployDescribedByMeta.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDescribedByMeta} from "../../concrete/MockDescribedByMeta.sol";

contract LibRainDeployDescribedByMetaCheckDescribesTest is Test {
    function externalCheckDescribes(string memory suite, address described, bytes memory meta) external view {
        LibRainDeployDescribedByMeta.checkDescribes(suite, described, meta);
    }

    function expectNoAnswer(string memory suite, address described, bytes memory meta) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                DescribedByMetaMismatch.selector, suite, described, false, bytes32(0), keccak256(meta)
            )
        );
        this.externalCheckDescribes(suite, described, meta);
    }

    function testADeploymentAnsweringTheMetasHashPasses(string memory suite, bytes memory meta) external {
        vm.assume(meta.length != 0);
        address described = address(new MockDescribedByMeta(keccak256(meta)));
        vm.expectCall(described, abi.encodeCall(IDescribedByMetaV1.describedByMetaV1, ()), 1);
        this.externalCheckDescribes(suite, described, meta);
    }

    function testADeploymentAnsweringAnotherHashIsAMismatch(string memory suite, bytes memory meta, bytes32 answer)
        external
    {
        vm.assume(meta.length != 0);
        vm.assume(answer != keccak256(meta));
        address described = address(new MockDescribedByMeta(answer));
        vm.expectRevert(
            abi.encodeWithSelector(DescribedByMetaMismatch.selector, suite, described, true, answer, keccak256(meta))
        );
        this.externalCheckDescribes(suite, described, meta);
    }

    function testADeploymentWithoutDescribedByMetaV1AnswersNothing(string memory suite, bytes memory meta) external {
        vm.assume(meta.length != 0);
        expectNoAnswer(suite, address(new MockDeployable()), meta);
    }

    function testAnAddressWithoutCodeAnswersNothing(string memory suite, bytes memory meta) external {
        vm.assume(meta.length != 0);
        expectNoAnswer(suite, makeAddr("codeless"), meta);
    }

    function testAnAnswerShorterThanAWordAnswersNothing(string memory suite, bytes memory meta, uint8 length) external {
        vm.assume(meta.length != 0);
        bytes memory answer = new bytes(bound(length, 0, 31));
        address described = address(new MockDescribedByMeta(keccak256(meta)));
        vm.mockCall(described, abi.encodeCall(IDescribedByMetaV1.describedByMetaV1, ()), answer);
        expectNoAnswer(suite, described, meta);
    }

    function testARevertingDeploymentAnswersNothing(string memory suite, bytes memory meta) external {
        vm.assume(meta.length != 0);
        address described = address(new MockDescribedByMeta(keccak256(meta)));
        vm.mockCallRevert(
            described, abi.encodeCall(IDescribedByMetaV1.describedByMetaV1, ()), abi.encode(keccak256(meta))
        );
        expectNoAnswer(suite, described, meta);
    }

    function testAnEmptyMetaAsksNothing(string memory suite, address described) external {
        vm.expectCall(described, abi.encodeCall(IDescribedByMetaV1.describedByMetaV1, ()), 0);
        this.externalCheckDescribes(suite, described, "");
    }
}
