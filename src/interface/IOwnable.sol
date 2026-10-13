// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title IOwnable
/// @notice The ownership getter of OpenZeppelin `Ownable` and ERC-173, and
/// nothing else. A deploy check reads who owns a contract; it never transfers
/// or renounces ownership, so the mutators are deliberately absent.
interface IOwnable {
    /// @notice The current owner of the contract.
    /// @return The owner address.
    function owner() external view returns (address);
}
