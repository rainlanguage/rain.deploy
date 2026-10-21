// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableFactoryV5} from "rain-factory-0.2.0/src/interface/ICloneableFactoryV5.sol";
import {LibICloneableFactoryV5} from "rain-factory-0.2.0/src/lib/LibICloneableFactoryV5.sol";
import {MockBeaconProxyFactory} from "./MockBeaconProxyFactory.sol";

/// @title MockSaltShiftingBeaconProxyFactory
/// @notice `MockBeaconProxyFactory` whose `beaconProxyDeterministicOpenSalt` deploys a real beacon proxy under the
/// salt with its low bit flipped, so the proxy lands and initializes off the formula's address.
contract MockSaltShiftingBeaconProxyFactory is MockBeaconProxyFactory {
    /// @inheritdoc ICloneableFactoryV5
    function beaconProxyDeterministicOpenSalt(address beacon, bytes calldata data, bytes32 salt)
        external
        override
        returns (address)
    {
        return LibICloneableFactoryV5.beaconProxyDeterministicOpenSalt(beacon, data, salt ^ bytes32(uint256(1)));
    }
}
