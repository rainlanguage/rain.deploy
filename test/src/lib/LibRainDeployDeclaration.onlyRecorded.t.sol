// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";

contract LibRainDeployDeclarationOnlyRecordedTest is Test {
    function testOnlyRecordedKeepsTheRecordedEntriesInOrder(address[] memory addresses, uint256 mask) external pure {
        vm.assume(addresses.length <= 256);
        bool[] memory recorded = new bool[](addresses.length);
        address[] memory expected = new address[](addresses.length);
        uint256 count = 0;
        for (uint256 i = 0; i < addresses.length; i++) {
            recorded[i] = ((mask >> i) & 1) == 1;
            if (recorded[i]) {
                expected[count++] = addresses[i];
            }
        }
        address[] memory kept = LibRainDeployDeclaration.onlyRecorded(recorded, addresses);
        assertEq(kept.length, count);
        for (uint256 i = 0; i < count; i++) {
            assertEq(kept[i], expected[i]);
        }
    }
}
