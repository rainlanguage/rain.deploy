// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title ISafe
/// @notice The subset of the Safe v1.4.1 ABI that authoring, hashing,
/// approving and executing a Safe transaction bundle needs, plus the
/// read-only introspection a consumer checks a Safe's configuration with.
/// Every signature matches the canonical v1.4.1 source:
/// https://github.com/safe-global/safe-smart-account/tree/v1.4.1/contracts
interface ISafe {
    /// @notice Self-call only: set the number of owner signatures
    /// `execTransaction` requires.
    /// @param threshold The new threshold, `> 0` and `<=` the owner count.
    function changeThreshold(uint256 threshold) external;

    /// @notice The number of owner signatures `execTransaction` requires.
    /// @return The current threshold.
    function getThreshold() external view returns (uint256);

    /// @notice The owner set, in the Safe's linked-list order.
    /// @return The owner addresses.
    function getOwners() external view returns (address[] memory);

    /// @notice The nonce the next `execTransaction` consumes.
    /// @return The current nonce.
    function nonce() external view returns (uint256);

    /// @notice One page of the module linked list.
    /// @param start The cursor; `address(0x1)` starts at the head.
    /// @param pageSize The most modules to return.
    /// @return array The page.
    /// @return next The cursor for the next page.
    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        returns (address[] memory array, address next);

    /// @notice The EIP-712 hash, under this Safe's own domain, that owners sign
    /// for `execTransaction` to accept the transaction.
    /// @param to The inner transaction's destination.
    /// @param value The native value forwarded to `to`.
    /// @param data The calldata forwarded to `to`.
    /// @param operation `0` CALL, `1` DELEGATECALL.
    /// @param safeTxGas Gas forwarded to the inner transaction.
    /// @param baseGas Gas independent of the inner transaction, for refunds.
    /// @param gasPrice Refund gas price.
    /// @param gasToken Refund token, `address(0)` for native.
    /// @param refundReceiver Refund receiver, `address(0)` for `tx.origin`.
    /// @param _nonce The nonce the transaction consumes.
    /// @return The Safe transaction hash.
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external view returns (bytes32);

    /// @notice Raw storage read.
    /// @param offset The first slot.
    /// @param length The number of slots.
    /// @return The slots, concatenated.
    function getStorageAt(uint256 offset, uint256 length) external view returns (bytes memory);

    /// @notice The singleton's version string, `"1.4.1"` for v1.4.1.
    /// @return The version.
    //slither-disable-next-line naming-convention
    function VERSION() external view returns (string memory);

    /// @notice Owner only: mark `hashToApprove` approved by `msg.sender`, so a
    /// `v == 1` signature entry whose `r` is the owner's address satisfies
    /// `checkSignatures` for that hash.
    /// @param hashToApprove The Safe transaction hash to approve.
    function approveHash(bytes32 hashToApprove) external;

    /// @notice Execute a Safe transaction once `signatures` satisfy the
    /// threshold. `signatures` is 65-byte entries sorted strictly ascending by
    /// signer; fewer than `threshold` entries revert `GS020`.
    /// @param to The inner transaction's destination.
    /// @param value The native value forwarded to `to`.
    /// @param data The calldata forwarded to `to`.
    /// @param operation `0` CALL, `1` DELEGATECALL.
    /// @param safeTxGas Gas forwarded to the inner transaction.
    /// @param baseGas Gas independent of the inner transaction, for refunds.
    /// @param gasPrice Refund gas price.
    /// @param gasToken Refund token, `address(0)` for native.
    /// @param refundReceiver Refund receiver, `address(0)` for `tx.origin`.
    /// @param signatures The packed owner signatures.
    /// @return success Whether the inner transaction succeeded.
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes calldata signatures
    ) external payable returns (bool success);
}
