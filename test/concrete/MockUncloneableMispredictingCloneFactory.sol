// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableFactoryV4} from "rain-factory-pr271-0477c05/src/interface/deprecated/ICloneableFactoryV4.sol";
import {ICloneableFactoryV3} from "rain-factory-pr271-0477c05/src/interface/deprecated/ICloneableFactoryV3.sol";
import {MockMispredictingCloneFactory} from "./MockMispredictingCloneFactory.sol";

/// @title MockUncloneableMispredictingCloneFactory
/// @notice `MockMispredictingCloneFactory` with its clone path shut.
contract MockUncloneableMispredictingCloneFactory is MockMispredictingCloneFactory {
    /// Thrown by every clone path, so reaching one is reportable.
    error CloneWasReached();

    /// @inheritdoc ICloneableFactoryV4
    function cloneDeterministicOpenSalt(address, bytes calldata, bytes32) external pure override returns (address) {
        revert CloneWasReached();
    }

    /// @inheritdoc ICloneableFactoryV3
    function cloneDeterministic(address, bytes calldata, bytes32) external pure override returns (address) {
        revert CloneWasReached();
    }
}
