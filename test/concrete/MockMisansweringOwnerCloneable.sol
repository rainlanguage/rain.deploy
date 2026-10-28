// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableV2, ICLONEABLE_V2_SUCCESS} from "rain-factory-0.2.6/src/interface/ICloneableV2.sol";

/// @title MockMisansweringOwnerCloneable
/// @notice A cloneable whose `owner()` does not answer an owner: it either reverts with the initializing origin as
/// its whole revert data, or returns fewer than 32 bytes.
contract MockMisansweringOwnerCloneable is ICloneableV2 {
    address internal sOrigin;
    bool internal sShort;

    /// @param data `abi.encode(bool)`: whether `owner()` returns short rather than reverting.
    function initialize(bytes calldata data) external returns (bytes32) {
        sOrigin = tx.origin;
        sShort = abi.decode(data, (bool));
        return ICLONEABLE_V2_SUCCESS;
    }

    /// Never returns normally: reverts with the origin, or returns 31 bytes of it.
    /// @return Nothing: it never returns a full word.
    function owner() external view returns (address) {
        address seated = sOrigin;
        bool short = sShort;
        assembly ("memory-safe") {
            mstore(0, seated)
            if short { return(0, 0x1f) }
            revert(0, 0x20)
        }
    }
}
