// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableV2, ICLONEABLE_V2_SUCCESS} from "rain-factory-0.1.30/src/interface/ICloneableV2.sol";

/// Thrown when `initialize` is called on an already-initialized clone.
error MockCloneableAlreadyInitialized();

/// @title MockCloneable
/// @notice The implementation a clone delegates into, and the minimum that makes
/// a clone deploy REAL: `LibICloneableFactoryV4.cloneAndInitialize` calls
/// `ICloneableV2.initialize` atomically with the `CREATE2` and only considers the
/// clone created if it answers `ICLONEABLE_V2_SUCCESS`, so an implementation that
/// does not implement the interface makes every clone deploy revert and no test
/// of the address derivation could run at all.
///
/// It stores the init data because that is what makes a successful clone
/// observable as having been initialized with the bytes the declaration named —
/// the open salt commits to `data`, so a clone that initialized with something
/// else is at a different address, and reading the data back is how a test sees
/// which one it got.
///
/// Double-initialization is guarded for the reason a real implementation guards
/// it: the factory's call is atomic with the clone, so a second one can only come
/// from outside, and an implementation that let it happen would let anybody reset
/// a deployed clone's state.
contract MockCloneable is ICloneableV2 {
    /// The data this clone was initialized with, verbatim.
    bytes public sInitData;

    /// Whether `initialize` has run. Separate from `sInitData` being empty,
    /// because empty data is a legitimate initialization — `data` MAY be empty
    /// per `ICloneableFactoryV4.cloneDeterministicOpenSalt` — so emptiness is
    /// not a usable "not yet initialized" signal.
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
