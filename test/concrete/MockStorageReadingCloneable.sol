// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableV2, ICLONEABLE_V2_SUCCESS} from "rain-factory-0.1.30/src/interface/ICloneableV2.sol";
import {MockStorageSource} from "./MockStorageSource.sol";

/// Thrown when `initialize` finds nothing registered.
error MockNameNotRegistered();

/// Thrown when `initialize` is told to revert.
error MockInitializeRefused();

/// How `MockStorageReadingCloneable.initialize` treats its source.
/// `Read` reads it. `ReadRequired` reads it and reverts with `MockNameNotRegistered` on zero. `Write` writes 1 to
/// it. `WriteThenRead` writes its slot 0, then reads it. `Refuse` reverts with `MockInitializeRefused` without
/// touching it. `ReadChild` ignores it and reads a `MockStorageSource` it creates.
enum SourceUse {
    Read,
    ReadRequired,
    Write,
    Refuse,
    ReadChild,
    WriteThenRead
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
        } else if (use == SourceUse.WriteThenRead) {
            source.setPaddingThenRead(1);
        } else if (use == SourceUse.ReadChild) {
            (new MockStorageSource()).sValue();
        } else if (source.sValue() == 0 && use == SourceUse.ReadRequired) {
            revert MockNameNotRegistered();
        }
        return ICLONEABLE_V2_SUCCESS;
    }
}
