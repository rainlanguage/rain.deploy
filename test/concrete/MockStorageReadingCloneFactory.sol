// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableFactoryV4} from "rain-factory-0.2.0/src/interface/deprecated/ICloneableFactoryV4.sol";
import {LibICloneableFactoryV5} from "rain-factory-0.2.0/src/lib/LibICloneableFactoryV5.sol";
import {MockCloneFactory} from "./MockCloneFactory.sol";

/// @title MockStorageReadingCloneFactory
/// @notice `MockCloneFactory` whose `cloneDeterministicOpenSalt` reads its own slot 0 before it clones.
contract MockStorageReadingCloneFactory is MockCloneFactory {
    /// Slot 0, XORed into the salt. Zero, so the clone's salt is unchanged.
    uint256 internal sSaltMask;

    /// @inheritdoc ICloneableFactoryV4
    function cloneDeterministicOpenSalt(address implementation, bytes calldata data, bytes32 salt)
        external
        override
        returns (address)
    {
        return LibICloneableFactoryV5.cloneDeterministicOpenSalt(implementation, data, salt ^ bytes32(sSaltMask));
    }
}
