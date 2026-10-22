// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableFactoryV4} from "rain-factory-0.2.5/src/interface/deprecated/ICloneableFactoryV4.sol";
import {ICloneableFactoryV3} from "rain-factory-0.2.5/src/interface/deprecated/ICloneableFactoryV3.sol";
import {LibICloneableFactoryV5} from "rain-factory-0.2.5/src/lib/LibICloneableFactoryV5.sol";

/// @title MockCloneFactory
/// @notice A real `ICloneableFactoryV4`, not a stub.
contract MockCloneFactory is ICloneableFactoryV4 {
    /// @inheritdoc ICloneableFactoryV4
    function cloneDeterministicOpenSalt(address implementation, bytes calldata data, bytes32 salt)
        external
        virtual
        returns (address)
    {
        return LibICloneableFactoryV5.cloneDeterministicOpenSalt(implementation, data, salt);
    }

    /// @inheritdoc ICloneableFactoryV4
    function predictDeterministicAddressOpenSalt(address implementation, bytes calldata data, bytes32 salt)
        external
        view
        virtual
        returns (address)
    {
        return LibICloneableFactoryV5.predictDeterministicAddressOpenSalt(implementation, data, salt);
    }

    /// @inheritdoc ICloneableFactoryV3
    function cloneDeterministic(address implementation, bytes calldata data, bytes32 salt)
        external
        virtual
        returns (address)
    {
        return LibICloneableFactoryV5.cloneDeterministic(implementation, data, salt);
    }

    /// @inheritdoc ICloneableFactoryV3
    function predictDeterministicAddress(address implementation, bytes32 salt, address deployer)
        external
        view
        virtual
        returns (address)
    {
        return LibICloneableFactoryV5.predictDeterministicAddress(implementation, salt, deployer);
    }
}
