// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibDeploySuiteConcat} from "../../../src/lib/LibDeploySuiteConcat.sol";

contract LibDeploySuiteConcatTest is Test {
    function suiteAt(uint256 i, uint256 j) internal pure returns (DeploySuite memory) {
        DeploySuite memory suite;
        suite.suite = string.concat(vm.toString(i), "-", vm.toString(j));
        suite.storedDeployedAddress = address(uint160(uint256(keccak256(abi.encode(i, j)))));
        return suite;
    }

    function shaped(uint256[] memory lengths) internal pure returns (DeploySuite[][] memory) {
        DeploySuite[][] memory suites = new DeploySuite[][](lengths.length);
        for (uint256 i = 0; i < lengths.length; i++) {
            suites[i] = new DeploySuite[](lengths[i]);
            for (uint256 j = 0; j < lengths[i]; j++) {
                suites[i][j] = suiteAt(i, j);
            }
        }
        return suites;
    }

    function assertFlattened(uint256[] memory lengths) internal pure {
        DeploySuite[] memory flat = LibDeploySuiteConcat.concat(shaped(lengths));

        uint256 k = 0;
        for (uint256 i = 0; i < lengths.length; i++) {
            for (uint256 j = 0; j < lengths[i]; j++) {
                assertEq(abi.encode(flat[k]), abi.encode(suiteAt(i, j)));
                k++;
            }
        }
        assertEq(flat.length, k);
    }

    function testConcatEmptyOuter() external pure {
        assertEq(LibDeploySuiteConcat.concat(new DeploySuite[][](0)).length, 0);
    }

    function testConcatAllInnerEmpty() external pure {
        assertEq(LibDeploySuiteConcat.concat(new DeploySuite[][](3)).length, 0);
    }

    function testConcatEmptyInnerAmongNonEmpty() external pure {
        uint256[] memory lengths = new uint256[](5);
        lengths[0] = 0;
        lengths[1] = 2;
        lengths[2] = 0;
        lengths[3] = 1;
        lengths[4] = 0;
        assertFlattened(lengths);
    }

    function testConcatOrderPreserved() external pure {
        uint256[] memory lengths = new uint256[](3);
        lengths[0] = 2;
        lengths[1] = 3;
        lengths[2] = 1;
        DeploySuite[] memory flat = LibDeploySuiteConcat.concat(shaped(lengths));

        string[6] memory expected = ["0-0", "0-1", "1-0", "1-1", "1-2", "2-0"];
        assertEq(flat.length, expected.length);
        for (uint256 k = 0; k < expected.length; k++) {
            assertEq(flat[k].suite, expected[k]);
        }
    }

    function testConcatShapes(uint8[] memory rawLengths) external pure {
        uint256 outer = bound(rawLengths.length, 0, 8);
        uint256[] memory lengths = new uint256[](outer);
        for (uint256 i = 0; i < outer; i++) {
            lengths[i] = bound(rawLengths[i], 0, 5);
        }
        assertFlattened(lengths);
    }
}
