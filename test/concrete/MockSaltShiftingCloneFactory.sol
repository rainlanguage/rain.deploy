// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableFactoryV4} from "rain-factory-0.2.5/src/interface/deprecated/ICloneableFactoryV4.sol";
import {LibICloneableFactoryV5} from "rain-factory-0.2.5/src/lib/LibICloneableFactoryV5.sol";
import {MockCloneFactory} from "./MockCloneFactory.sol";

/// @title MockSaltShiftingCloneFactory
/// @notice `MockCloneFactory` whose `cloneDeterministicOpenSalt` deploys a real clone under the salt with its low bit
/// flipped, so the clone lands and initializes off the formula's address.
contract MockSaltShiftingCloneFactory is MockCloneFactory {
    /// @inheritdoc ICloneableFactoryV4
    function cloneDeterministicOpenSalt(address implementation, bytes calldata data, bytes32 salt)
        external
        override
        returns (address)
    {
        return LibICloneableFactoryV5.cloneDeterministicOpenSalt(implementation, data, salt ^ bytes32(uint256(1)));
    }
}
