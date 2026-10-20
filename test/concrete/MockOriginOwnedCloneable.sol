// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableV2, ICLONEABLE_V2_SUCCESS} from "rain-factory-0.1.30/src/interface/ICloneableV2.sol";

/// @title MockOriginOwnedCloneable
/// @notice A clone implementation seating the address its init data names as `owner()`, or the initialization's
/// origin when that address is zero.
contract MockOriginOwnedCloneable is ICloneableV2 {
    /// The seated owner.
    address internal sOwner;

    /// @inheritdoc ICloneableV2
    function initialize(bytes calldata data) external returns (bytes32) {
        address named = abi.decode(data, (address));
        sOwner = named == address(0) ? tx.origin : named;
        return ICLONEABLE_V2_SUCCESS;
    }

    /// @return The seated owner.
    function owner() external view returns (address) {
        return sOwner;
    }
}
