// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.5.0/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.5.0/contracts/common/Enum.sol";
import {MultiSendCallOnly} from "safe-global-safe-smart-account-1.5.0/contracts/libraries/MultiSendCallOnly.sol";
import {LibSafe} from "./LibSafe.sol";

/// One Safe transaction: the fields of `execTransaction` a bundle author
/// chooses. The gas and refund fields are always zero here, which is what the
/// Safe Transaction Builder signs and what a no-refund execution needs.
/// @param to The destination.
/// @param value The native value forwarded to `to`.
/// @param data The calldata forwarded to `to`.
/// @param operation CALL or DELEGATECALL.
struct SafeTx {
    address to;
    uint256 value;
    bytes data;
    Enum.Operation operation;
}

/// @title LibSafeTx
/// @notice Encodes and hashes Safe v1.4.1 transactions and bundles: the hash
/// owners sign, the `MultiSendCallOnly` batch a bundle executes as, and the
/// approved-hash signature blob `execTransaction` accepts.
library LibSafeTx {
    /// The bytes one approved-hash signature entry occupies: `r || s || v`.
    uint256 internal constant SIGNATURE_LENGTH = 65;

    /// A bundle entry is not a CALL. `MultiSendCallOnly` performs only CALLs
    /// and the Transaction Builder JSON has no per-transaction operation, so
    /// a non-CALL entry cannot be represented in either.
    /// @param index The entry's index in the bundle.
    /// @param operation The entry's operation.
    error UnsupportedOperation(uint256 index, Enum.Operation operation);

    /// Two approved-hash signers are the same address, which
    /// `checkSignatures` rejects.
    /// @param signer The repeated signer.
    error DuplicateSigner(address signer);

    /// Revert `UnsupportedOperation` unless `operation` is a CALL.
    /// @param index The entry's index, surfaced in the revert.
    /// @param operation The entry's operation.
    function requireCall(uint256 index, Enum.Operation operation) internal pure {
        if (operation != Enum.Operation.Call) revert UnsupportedOperation(index, operation);
    }

    /// The hash owners sign for `safe` to execute `txn` at `nonce`, as `safe`
    /// itself computes it, so it is bound to the Safe's own EIP-712 domain.
    /// @param safe The executing Safe.
    /// @param txn The transaction.
    /// @param nonce The nonce the transaction consumes.
    /// @return The Safe transaction hash.
    function safeTxHash(Safe safe, SafeTx memory txn, uint256 nonce) internal view returns (bytes32) {
        return
            safe.getTransactionHash(txn.to, txn.value, txn.data, txn.operation, 0, 0, 0, address(0), address(0), nonce);
    }

    /// The `multiSend(bytes)` calldata that executes `txs` in order: each
    /// entry packed as `operation (1) || to (20) || value (32) ||
    /// dataLength (32) || data`.
    /// @param txs The bundle. Every entry MUST be a CALL.
    /// @return The `multiSend(bytes)` calldata.
    function encodeMultiSend(SafeTx[] memory txs) internal pure returns (bytes memory) {
        bytes memory payload = "";
        for (uint256 i = 0; i < txs.length; i++) {
            requireCall(i, txs[i].operation);
            payload = bytes.concat(
                payload,
                abi.encodePacked(uint8(txs[i].operation), txs[i].to, txs[i].value, txs[i].data.length, txs[i].data)
            );
        }
        return abi.encodeCall(MultiSendCallOnly.multiSend, (payload));
    }

    /// The single transaction a Safe executes `txs` as: a DELEGATECALL to
    /// `LibSafe.SAFE_V1_4_1_MULTI_SEND_CALL_ONLY`, the contract the Safe
    /// Transaction Builder executes a bundle through at one nonce. A
    /// DELEGATECALL to an account with no code succeeds and does nothing, so
    /// this reverts `LibSafe.SafeCodehashMismatch` on a chain where that
    /// address does not hold the canonical code.
    /// @param txs The bundle. Every entry MUST be a CALL.
    /// @return The wrapping transaction.
    function multiSendTx(SafeTx[] memory txs) internal view returns (SafeTx memory) {
        LibSafe.assertCodehash(
            LibSafe.SAFE_V1_4_1_MULTI_SEND_CALL_ONLY, LibSafe.SAFE_V1_4_1_MULTI_SEND_CALL_ONLY_CODEHASH
        );
        return SafeTx({
            to: LibSafe.SAFE_V1_4_1_MULTI_SEND_CALL_ONLY,
            value: 0,
            data: encodeMultiSend(txs),
            operation: Enum.Operation.DelegateCall
        });
    }

    /// The hash owners sign for `safe` to execute the bundle `txs` at `nonce`.
    /// @param safe The executing Safe.
    /// @param txs The bundle. Every entry MUST be a CALL.
    /// @param nonce The nonce the bundle consumes.
    /// @return The Safe transaction hash.
    function multiSendSafeTxHash(Safe safe, SafeTx[] memory txs, uint256 nonce) internal view returns (bytes32) {
        return safeTxHash(safe, multiSendTx(txs), nonce);
    }

    /// `addrs` sorted ascending, in a new array.
    /// @param addrs The addresses.
    /// @return The same addresses, ascending.
    function sortAscending(address[] memory addrs) internal pure returns (address[] memory) {
        address[] memory sorted = new address[](addrs.length);
        for (uint256 i = 0; i < addrs.length; i++) {
            sorted[i] = addrs[i];
        }
        for (uint256 i = 1; i < sorted.length; i++) {
            address current = sorted[i];
            uint256 j = i;
            while (j > 0 && sorted[j - 1] > current) {
                sorted[j] = sorted[j - 1];
                j--;
            }
            sorted[j] = current;
        }
        return sorted;
    }

    /// The `execTransaction` signature blob in which every one of `signers`
    /// has approved the hash through `approveHash`: per signer, ascending,
    /// `r = signer` (left-padded), `s = 0`, `v = 1`. Reverts `DuplicateSigner`
    /// if a signer repeats.
    /// @param signers The approving owners, in any order.
    /// @return `signers.length * SIGNATURE_LENGTH` bytes.
    function approvedHashSignatures(address[] memory signers) internal pure returns (bytes memory) {
        address[] memory sorted = sortAscending(signers);
        bytes memory packed = "";
        for (uint256 i = 0; i < sorted.length; i++) {
            if (i > 0 && sorted[i] == sorted[i - 1]) revert DuplicateSigner(sorted[i]);
            packed = bytes.concat(packed, bytes32(uint256(uint160(sorted[i]))), bytes32(0), bytes1(0x01));
        }
        return packed;
    }
}
