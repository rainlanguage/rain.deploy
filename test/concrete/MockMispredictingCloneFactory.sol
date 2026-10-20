// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableFactoryV4} from "rain-factory-pr271-4379965/src/interface/deprecated/ICloneableFactoryV4.sol";
import {LibICloneableFactoryV4} from "rain-factory-pr271-4379965/src/lib/LibICloneableFactoryV4.sol";
import {MockCloneFactory} from "./MockCloneFactory.sol";

/// @title MockMispredictingCloneFactory
/// @notice `MockCloneFactory` differing in EXACTLY the one function under test.
contract MockMispredictingCloneFactory is MockCloneFactory {
    /// @inheritdoc ICloneableFactoryV4
    function predictDeterministicAddressOpenSalt(address implementation, bytes calldata data, bytes32 salt)
        external
        view
        override
        returns (address)
    {
        return address(
            uint160(LibICloneableFactoryV4.predictDeterministicAddressOpenSalt(implementation, data, salt)) + 1
        );
    }
}
