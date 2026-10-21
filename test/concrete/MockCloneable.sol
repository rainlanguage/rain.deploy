// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableV2, ICLONEABLE_V2_SUCCESS} from "rain-factory-0.2.0/src/interface/ICloneableV2.sol";

/// Thrown when `initialize` is called on an already-initialized clone.
error MockCloneableAlreadyInitialized();

/// @title MockCloneable
/// @notice The implementation a clone delegates into, and the minimum that makes a clone deploy
/// REAL.
contract MockCloneable is ICloneableV2 {
    /// The data this clone was initialized with, verbatim.
    bytes public sInitData;

    /// Whether `initialize` has run.
    bool public sInitialized;

    /// @inheritdoc ICloneableV2
    function initialize(bytes calldata data) external returns (bytes32) {
        if (sInitialized) {
            revert MockCloneableAlreadyInitialized();
        }
        sInitialized = true;
        sInitData = data;
        return ICLONEABLE_V2_SUCCESS;
    }
}
