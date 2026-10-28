// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableFactoryV5} from "rain-factory-0.2.6/src/interface/ICloneableFactoryV7.sol";
import {LibICloneableFactoryV5} from "rain-factory-0.2.6/src/lib/LibICloneableFactoryV5.sol";
import {MockBeaconProxyFactory} from "./MockBeaconProxyFactory.sol";

/// @title MockStorageReadingBeaconProxyFactory
/// @notice `MockBeaconProxyFactory` whose `beaconProxyDeterministicOpenSalt` reads its own `SALT_MASK_SLOT` before
/// it deploys.
contract MockStorageReadingBeaconProxyFactory is MockBeaconProxyFactory {
    /// The slot read: nonzero, so it is told apart from a reported slot of zero.
    uint256 internal constant SALT_MASK_SLOT = 1;

    /// @inheritdoc ICloneableFactoryV5
    function beaconProxyDeterministicOpenSalt(address beacon, bytes calldata data, bytes32 salt)
        external
        override
        returns (address)
    {
        // Never written, so zero: the proxy's salt is unchanged.
        bytes32 mask;
        assembly ("memory-safe") {
            mask := sload(SALT_MASK_SLOT)
        }
        return LibICloneableFactoryV5.beaconProxyDeterministicOpenSalt(beacon, data, salt ^ mask);
    }
}
