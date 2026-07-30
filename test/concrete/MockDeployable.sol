// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockDeployable
/// Minimal contract used as a deployment target for Zoltu factory tests.
contract MockDeployable {
    /// @notice Placeholder value to ensure the contract has non-trivial code.
    uint256 public value = 42;
}
