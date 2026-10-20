// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    BEACON_PROXY_STAND_IN_IMPLEMENTATION,
    BeaconProxyStandInBeacon
} from "../../../src/concrete/BeaconProxyStandInBeacon.sol";

contract BeaconProxyStandInBeaconTest is Test {
    /// The stand-in beacon serves the stand-in implementation.
    function testStandInBeaconServesTheStandInImplementation() external {
        assertEq(new BeaconProxyStandInBeacon().implementation(), BEACON_PROXY_STAND_IN_IMPLEMENTATION);
    }

    /// The stand-in implementation's address is the hash of its tag.
    function testStandInImplementationAddressDerivation() external pure {
        assertEq(
            BEACON_PROXY_STAND_IN_IMPLEMENTATION,
            address(uint160(uint256(keccak256("rain.deploy.beaconproxy.standin.implementation"))))
        );
    }
}
