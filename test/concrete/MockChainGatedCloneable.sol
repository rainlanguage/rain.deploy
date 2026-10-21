// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableV2, ICLONEABLE_V2_SUCCESS} from "rain-factory-0.2.4/src/interface/ICloneableV2.sol";

/// Thrown when a clone is initialized under a chain id other than the one its init data names.
/// @param named The chain id the init data names.
/// @param chainId The chain id it was initialized under.
error MockChainGatedCloneableWrongChain(uint256 named, uint256 chainId);

/// @title MockChainGatedCloneable
/// @notice A clone implementation whose initialization succeeds only under the chain id its init data names.
contract MockChainGatedCloneable is ICloneableV2 {
    /// @inheritdoc ICloneableV2
    function initialize(bytes calldata data) external view returns (bytes32) {
        uint256 named = abi.decode(data, (uint256));
        if (named != block.chainid) {
            revert MockChainGatedCloneableWrongChain(named, block.chainid);
        }
        return ICLONEABLE_V2_SUCCESS;
    }

    /// @return Nobody.
    function owner() external pure returns (address) {
        return address(0);
    }
}
