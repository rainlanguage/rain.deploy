// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockOriginOwned
/// @notice Seats whoever originated its deployment as `owner()`.
contract MockOriginOwned {
    /// The deployment's origin.
    address public owner = tx.origin;
}
