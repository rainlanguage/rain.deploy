// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {BeaconProxyStandInImplementation} from "../../../src/concrete/BeaconProxyStandInImplementation.sol";

contract BeaconProxyStandInImplementationTest is Test {
    /// The stand-in implementation initializes to the `ICloneableV2` success value with any data.
    function testStandInImplementationInitializes(bytes memory data) external {
        BeaconProxyStandInImplementation standIn = new BeaconProxyStandInImplementation();
        assertEq(standIn.initialize(data), keccak256("ICloneableV2.initialize"));
    }
}
