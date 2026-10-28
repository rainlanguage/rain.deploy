// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration, DeployDependency, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifySnapshotBase} from "../../../src/abstract/RainDeployVerifySnapshotBase.sol";
import {DescribedByMetaMismatch, MetaBoardUndeclared} from "../../../src/lib/LibRainDeployDescribedByMeta.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {ExampleDeploySuites} from "../../abstract/ExampleDeploySuites.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDescribedByMeta} from "../../concrete/MockDescribedByMeta.sol";

contract RainDeployVerifySnapshotBaseDescribedByMetaTest is ExampleDeploySuites, RainDeployVerifySnapshotBase {
    address constant META_BOARD = address(0x4d455441);

    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        addExample(d);
        return d;
    }

    function externalCheckInternallyConsistent(address metaBoard, DeploySuite memory suite) external {
        DeployDeclaration memory d = declaration();
        d.metaBoard = metaBoard;
        checkInternallyConsistent(d, suite);
    }

    function zoltuSuite(bytes memory creationCode, bytes memory runtimeCode, bytes memory meta)
        internal
        pure
        returns (DeploySuite memory)
    {
        return DeploySuite({
            networks: LibRainDeploy.supportedNetworks(),
            suite: "described@0_0_1",
            creationCode: creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(creationCode),
            storedBytecodeHash: keccak256(runtimeCode),
            storedRuntimeCode: runtimeCode,
            artifactPath: "test/concrete/MockDescribedByMeta.sol:MockDescribedByMeta",
            dependencies: new DeployDependency[](0),
            mechanismData: LibRainDeployZoltuMechanism.mechanismData(),
            describedByMeta: meta
        });
    }

    function describedSuite(bytes32 answer, bytes memory meta) internal pure returns (DeploySuite memory) {
        return zoltuSuite(
            abi.encodePacked(type(MockDescribedByMeta).creationCode, abi.encode(answer)),
            type(MockDescribedByMeta).runtimeCode,
            meta
        );
    }

    function testAConsistentDescribedSuitePassesAndLeavesNoCode(bytes memory meta) external {
        vm.assume(meta.length != 0);
        DeploySuite memory suite = describedSuite(keccak256(meta), meta);
        this.externalCheckInternallyConsistent(META_BOARD, suite);
        assertEq(suite.storedDeployedAddress.code.length, 0);
    }

    function testADescribedSuiteRefusesAnUndeclaredMetaBoard(bytes memory meta) external {
        vm.assume(meta.length != 0);
        DeploySuite memory suite = describedSuite(keccak256(meta), meta);
        vm.expectRevert(abi.encodeWithSelector(MetaBoardUndeclared.selector, suite.suite));
        this.externalCheckInternallyConsistent(address(0), suite);
    }

    function testADeploymentAnsweringAnotherHashIsAMismatch(bytes memory meta, bytes32 answer) external {
        vm.assume(meta.length != 0);
        vm.assume(answer != keccak256(meta));
        DeploySuite memory suite = describedSuite(answer, meta);
        vm.expectRevert(
            abi.encodeWithSelector(
                DescribedByMetaMismatch.selector,
                suite.suite,
                suite.storedDeployedAddress,
                true,
                answer,
                keccak256(meta)
            )
        );
        this.externalCheckInternallyConsistent(META_BOARD, suite);
    }

    function testADeploymentAnsweringNothingIsAMismatch(bytes memory meta) external {
        vm.assume(meta.length != 0);
        DeploySuite memory suite = zoltuSuite(type(MockDeployable).creationCode, type(MockDeployable).runtimeCode, meta);
        vm.expectRevert(
            abi.encodeWithSelector(
                DescribedByMetaMismatch.selector,
                suite.suite,
                suite.storedDeployedAddress,
                false,
                bytes32(0),
                keccak256(meta)
            )
        );
        this.externalCheckInternallyConsistent(META_BOARD, suite);
    }

    function testASuiteCarryingNoMetaNeedsNoMetaBoardNorAnAnswer() external {
        this.externalCheckInternallyConsistent(
            address(0), zoltuSuite(type(MockDeployable).creationCode, type(MockDeployable).runtimeCode, "")
        );
    }
}
