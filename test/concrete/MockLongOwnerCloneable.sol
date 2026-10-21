// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableV2, ICLONEABLE_V2_SUCCESS} from "rain-factory-0.2.4/src/interface/ICloneableV2.sol";

/// @title MockLongOwnerCloneable
/// @notice A cloneable whose `owner()` answers two words: the initializing origin, then a trailing word.
contract MockLongOwnerCloneable is ICloneableV2 {
    address internal sOrigin;
    bytes32 internal sTrailing;

    /// @param data `abi.encode(bytes32)`: the trailing word.
    function initialize(bytes calldata data) external returns (bytes32) {
        sOrigin = tx.origin;
        sTrailing = abi.decode(data, (bytes32));
        return ICLONEABLE_V2_SUCCESS;
    }

    /// @return The origin, followed by the trailing word.
    function owner() external view returns (address) {
        address seated = sOrigin;
        bytes32 trailing = sTrailing;
        assembly ("memory-safe") {
            mstore(0, seated)
            mstore(0x20, trailing)
            return(0, 0x40)
        }
    }
}
