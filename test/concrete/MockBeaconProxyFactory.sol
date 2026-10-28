// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableFactoryV5, ICloneableFactoryV7} from "rain-factory-0.2.6/src/interface/ICloneableFactoryV7.sol";
import {LibICloneableFactoryV5} from "rain-factory-0.2.6/src/lib/LibICloneableFactoryV5.sol";
import {LibICloneableFactoryV7} from "rain-factory-0.2.6/src/lib/LibICloneableFactoryV7.sol";
import {MockCloneFactory} from "./MockCloneFactory.sol";

/// @title MockBeaconProxyFactory
/// @notice A real `ICloneableFactoryV7`, not a stub.
contract MockBeaconProxyFactory is MockCloneFactory, ICloneableFactoryV7 {
    /// @inheritdoc ICloneableFactoryV5
    function beaconProxyDeterministicOpenSalt(address beacon, bytes calldata data, bytes32 salt)
        external
        virtual
        returns (address)
    {
        return LibICloneableFactoryV5.beaconProxyDeterministicOpenSalt(beacon, data, salt);
    }

    /// @inheritdoc ICloneableFactoryV5
    function predictBeaconProxyAddressOpenSalt(address beacon, bytes calldata data, bytes32 salt)
        external
        view
        virtual
        returns (address)
    {
        return LibICloneableFactoryV5.predictBeaconProxyAddressOpenSalt(beacon, data, salt);
    }

    function registryBeaconProxy(
        address registry,
        address authority,
        bytes32 beaconName,
        bytes calldata data,
        bytes32 salt
    ) external returns (address) {
        return LibICloneableFactoryV7.registryBeaconProxy(registry, authority, beaconName, data, salt);
    }

    function predictRegistryBeaconProxyAddress(
        address registry,
        address authority,
        bytes32 beaconName,
        bytes calldata data,
        bytes32 salt
    ) external view returns (address) {
        return LibICloneableFactoryV7.predictRegistryBeaconProxyAddress(registry, authority, beaconName, data, salt);
    }
}
