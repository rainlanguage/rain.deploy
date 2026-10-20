// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableV2, ICLONEABLE_V2_SUCCESS} from "rain-factory-pr271-4379965/src/interface/ICloneableV2.sol";

/// Thrown when `initialize` is called on an already-initialized clone.
error MockCloneableV2AlreadyInitialized();

/// @title MockCloneableV2
/// @notice A clone implementation whose code differs from `MockCloneable`'s, so the two derive
/// different Zoltu addresses and the clones of each embed a different implementation address.
contract MockCloneableV2 is ICloneableV2 {
    /// The data this clone was initialized with, verbatim.
    bytes public sInitData;

    /// Whether `initialize` has run.
    bool public sInitialized;

    /// @inheritdoc ICloneableV2
    function initialize(bytes calldata data) external returns (bytes32) {
        if (sInitialized) {
            revert MockCloneableV2AlreadyInitialized();
        }
        sInitialized = true;
        sInitData = data;
        return ICLONEABLE_V2_SUCCESS;
    }

    /// Which implementation this is.
    /// @return 2.
    function version() external pure returns (uint256) {
        return 2;
    }
}
