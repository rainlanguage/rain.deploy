// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableV2, ICLONEABLE_V2_SUCCESS} from "rain-factory-0.1.30/src/interface/ICloneableV2.sol";

/// Thrown when `initialize` finds nothing registered.
error MockNameNotRegistered();

/// Thrown when `initialize` is told to revert.
error MockInitializeRefused();

/// @title MockStorageSource
/// @notice One storage word another contract's `initialize` reads or writes.
contract MockStorageSource {
    uint256 public sValue;

    function set(uint256 value) external {
        sValue = value;
    }
}

/// How `MockStorageReadingCloneable.initialize` treats its source.
enum SourceUse {
    Read,
    ReadRequired,
    Write,
    Refuse
}

/// @title MockStorageReadingCloneable
/// @notice A cloneable whose `initialize` reads or writes a `MockStorageSource`, or reverts, as its data says.
contract MockStorageReadingCloneable is ICloneableV2 {
    /// @inheritdoc ICloneableV2
    function initialize(bytes calldata data) external returns (bytes32) {
        (MockStorageSource source, SourceUse use) = abi.decode(data, (MockStorageSource, SourceUse));
        if (use == SourceUse.Write) {
            source.set(1);
        } else if (use == SourceUse.Refuse) {
            revert MockInitializeRefused();
        } else if (source.sValue() == 0 && use == SourceUse.ReadRequired) {
            revert MockNameNotRegistered();
        }
        return ICLONEABLE_V2_SUCCESS;
    }
}
