// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockOriginRevertingOwner
/// @notice Reverts `owner()` with the word a successful answer naming its deployment's origin would carry.
contract MockOriginRevertingOwner {
    /// The deployment's origin.
    address internal sOrigin = tx.origin;

    /// Reverts with `sOrigin`, ABI-encoded, as the whole of the revert data.
    function owner() external view {
        bytes memory answer = abi.encode(sOrigin);
        assembly ("memory-safe") {
            revert(add(answer, 0x20), mload(answer))
        }
    }
}
