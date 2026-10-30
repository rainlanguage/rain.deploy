// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration, DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {MetaBoardUndeclared} from "../../../src/lib/LibRainDeployDescribedByMeta.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";

contract RainDeploySuitesBaseCheckedMetaBoardTest is RainDeploySuitesBase, Test {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        return d;
    }

    function externalCheckedMetaBoard(address metaBoard, string memory key, bytes memory meta)
        external
        pure
        returns (address)
    {
        DeployDeclaration memory d = declaration();
        d.metaBoard = metaBoard;
        DeploySuite memory suite;
        suite.suite = key;
        suite.describedByMeta = meta;
        return checkedMetaBoard(d, suite);
    }

    function testASuiteCarryingAMetaRefusesAnUndeclaredMetaBoard(string memory key, bytes memory meta) external {
        vm.assume(meta.length != 0);
        vm.expectRevert(abi.encodeWithSelector(MetaBoardUndeclared.selector, key));
        this.externalCheckedMetaBoard(address(0), key, meta);
    }

    function testASuiteCarryingAMetaGetsTheDeclaredMetaBoard(address metaBoard, string memory key, bytes memory meta)
        external
        view
    {
        vm.assume(metaBoard != address(0));
        vm.assume(meta.length != 0);
        assertEq(this.externalCheckedMetaBoard(metaBoard, key, meta), metaBoard);
    }

    function testASuiteCarryingNoMetaGetsTheDeclaredMetaBoardEvenZero(address metaBoard, string memory key)
        external
        view
    {
        assertEq(this.externalCheckedMetaBoard(metaBoard, key, ""), metaBoard);
    }
}
