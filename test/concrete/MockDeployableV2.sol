// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockDeployableV2
/// Deployment target whose creation code differs from `MockDeployable`, so the
/// two derive different Zoltu addresses. Stands in for a contract whose
/// bytecode has changed while its pinned constants have not.
contract MockDeployableV2 {
    /// @notice Placeholder value to ensure the contract has non-trivial code.
    uint256 public value = 43;

    /// @notice Second placeholder value so the runtime code also differs from
    /// `MockDeployable`.
    uint256 public other = 99;
}
