// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableV2, ICLONEABLE_V2_SUCCESS} from "rain-factory-pr271-0477c05/src/interface/ICloneableV2.sol";

/// @title MockDirtyOwnerCloneable
/// @notice A cloneable whose `owner()` answers a word holding the initializing origin in its low 160 bits and
/// the initialized value above them.
contract MockDirtyOwnerCloneable is ICloneableV2 {
    uint256 internal sOwner;

    /// @param data `abi.encode(uint96)`: the bits above the origin.
    function initialize(bytes calldata data) external returns (bytes32) {
        sOwner = (uint256(abi.decode(data, (uint96))) << 160) | uint256(uint160(tx.origin));
        return ICLONEABLE_V2_SUCCESS;
    }

    /// @return The stored word: the origin in the low 160 bits, the init data's `uint96` above.
    function owner() external view returns (uint256) {
        return sOwner;
    }
}
