// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ICloneableV2, ICLONEABLE_V2_SUCCESS} from "rain-factory-0.2.4/src/interface/ICloneableV2.sol";

/// Thrown when a clone is initialized under the chain id its init data refuses.
/// @param refused The chain id the init data refuses.
error MockChainRefusingCloneableRefusedChain(uint256 refused);

/// @title MockChainRefusingCloneable
/// @notice A clone implementation whose initialization refuses the one chain id its init data names.
contract MockChainRefusingCloneable is ICloneableV2 {
    /// @inheritdoc ICloneableV2
    function initialize(bytes calldata data) external view returns (bytes32) {
        uint256 refused = abi.decode(data, (uint256));
        if (refused == block.chainid) {
            revert MockChainRefusingCloneableRefusedChain(refused);
        }
        return ICLONEABLE_V2_SUCCESS;
    }

    /// @return Nobody.
    function owner() external pure returns (address) {
        return address(0);
    }
}
