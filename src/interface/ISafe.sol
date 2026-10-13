// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title ISafe
/// @notice The read surface of a Safe v1.4.1 proxy that `LibSafe` asserts
/// against. Signatures are those of
/// https://github.com/safe-global/safe-smart-account/tree/v1.4.1/contracts.
interface ISafe {
    /// @notice Answered by the `SafeProxy` bytecode itself, without delegating
    /// to the singleton: the singleton address the proxy holds in its slot 0.
    /// @return The proxy's singleton.
    function masterCopy() external view returns (address);

    /// @return The number of owner signatures required to execute a
    /// transaction.
    function getThreshold() external view returns (uint256);

    /// @return The owners, in the Safe's internal linked-list order.
    function getOwners() external view returns (address[] memory);

    /// @param start The cursor; the modules sentinel `address(0x1)` starts at
    /// the head of the list.
    /// @param pageSize The maximum number of modules to return.
    /// @return array Up to `pageSize` enabled modules.
    /// @return next The cursor for the next page.
    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        returns (address[] memory array, address next);

    /// @param offset The first storage slot to read.
    /// @param length The number of consecutive slots to read.
    /// @return The `length` 32-byte words from `offset`, concatenated.
    function getStorageAt(uint256 offset, uint256 length) external view returns (bytes memory);

    /// @return The singleton's version string.
    //slither-disable-next-line naming-convention
    function VERSION() external view returns (string memory);
}
