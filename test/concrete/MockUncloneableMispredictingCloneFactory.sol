// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableFactoryV4} from "rain-factory-0.1.30/src/interface/ICloneableFactoryV4.sol";
import {ICloneableFactoryV3} from "rain-factory-0.1.30/src/interface/deprecated/ICloneableFactoryV3.sol";
import {LibICloneableFactoryV4} from "rain-factory-0.1.30/src/lib/LibICloneableFactoryV4.sol";

/// @title MockUncloneableMispredictingCloneFactory
/// @notice `MockMispredictingCloneFactory` with its clone path shut.
contract MockUncloneableMispredictingCloneFactory is ICloneableFactoryV4 {
    /// Thrown by every clone path, so reaching one is reportable.
    error CloneWasReached();

    /// @inheritdoc ICloneableFactoryV4
    function predictDeterministicAddressOpenSalt(address implementation, bytes calldata data, bytes32 salt)
        external
        view
        returns (address)
    {
        return address(
            uint160(LibICloneableFactoryV4.predictDeterministicAddressOpenSalt(implementation, data, salt)) + 1
        );
    }

    /// @inheritdoc ICloneableFactoryV4
    function cloneDeterministicOpenSalt(address, bytes calldata, bytes32) external pure returns (address) {
        revert CloneWasReached();
    }

    /// @inheritdoc ICloneableFactoryV3
    function cloneDeterministic(address, bytes calldata, bytes32) external pure returns (address) {
        revert CloneWasReached();
    }

    /// @inheritdoc ICloneableFactoryV3
    function predictDeterministicAddress(address implementation, bytes32 salt, address deployer)
        external
        view
        returns (address)
    {
        return LibICloneableFactoryV4.predictDeterministicAddress(implementation, salt, deployer);
    }
}
