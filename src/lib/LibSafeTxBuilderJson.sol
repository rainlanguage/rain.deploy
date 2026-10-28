// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {Enum} from "safe-global-safe-smart-account-1.5.0/contracts/libraries/Enum.sol";
import {LibSafeTx, SafeTx} from "./LibSafeTx.sol";

/// @title LibSafeTxBuilderJson
/// @notice Writes a bundle as the JSON the Safe Transaction Builder imports,
/// reads it back, and checks an artifact against the bundle re-derived from
/// live state before anyone signs it.
///
/// The JSON is assembled by hand because `vm.serializeJson` writes an array as
/// an index-keyed object, which the Transaction Builder does not import.
/// Every entry is a raw `{to, value, data}` CALL: the format has no
/// per-transaction operation, and `contractMethod` entries are not read.
library LibSafeTxBuilderJson {
    /// The Transaction Builder file format version.
    string internal constant SCHEMA_VERSION = "1.0";

    /// The Transaction Builder app version stamped into `meta`.
    string internal constant TX_BUILDER_VERSION = "1.16.5";

    /// The bundle has no transactions.
    error NoTransactions();

    /// A string written into the JSON contains `"`, `\` or a control
    /// character, which would have to be escaped.
    /// @param value The rejected string.
    error UnescapedJsonString(string value);

    /// A decimal field holds something other than one or more ASCII digits.
    /// @param value The rejected field.
    error NotDecimal(string value);

    /// The artifact does not match the bundle re-derived from live state: it
    /// is stale, tampered, or for another Safe or chain, and must not be
    /// signed.
    /// @param field The first mismatching field.
    error ArtifactMismatch(string field);

    /// The Transaction Builder JSON for `safe` to execute `txs` on `chainId`.
    /// `createdAt` is `block.timestamp` in milliseconds, as the app writes it.
    /// @param vm The Vm, for `toString`.
    /// @param safe The Safe the bundle is for, written to
    /// `meta.createdFromSafeAddress`.
    /// @param chainId The chain the bundle is for.
    /// @param name The bundle name, written to `meta.name`.
    /// @param txs The bundle. Non-empty, and every entry a CALL.
    /// @return The JSON.
    function toJson(Vm vm, address safe, uint256 chainId, string memory name, SafeTx[] memory txs)
        internal
        view
        returns (string memory)
    {
        if (txs.length == 0) revert NoTransactions();
        requireUnescaped(name);
        string memory transactions = "[";
        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeTx.requireCall(i, txs[i].operation);
            transactions = string.concat(
                transactions,
                i == 0 ? "" : ",",
                "{",
                field("to", quote(vm.toString(txs[i].to))),
                ",",
                field("value", quote(vm.toString(txs[i].value))),
                ",",
                field("data", quote(vm.toString(txs[i].data))),
                "}"
            );
        }
        string memory meta = string.concat(
            "{",
            field("name", quote(name)),
            ",",
            field("txBuilderVersion", quote(TX_BUILDER_VERSION)),
            ",",
            field("createdFromSafeAddress", quote(vm.toString(safe))),
            "}"
        );
        return string.concat(
            "{",
            field("version", quote(SCHEMA_VERSION)),
            ",",
            field("chainId", quote(vm.toString(chainId))),
            ",",
            field("createdAt", vm.toString(block.timestamp * 1000)),
            ",",
            field("meta", meta),
            ",",
            field("transactions", string.concat(transactions, "]")),
            "}"
        );
    }

    /// Read a Transaction Builder JSON bundle. Every entry reads as a CALL.
    /// @param vm The Vm, for the JSON cheatcodes.
    /// @param json The JSON.
    /// @return The `chainId` field.
    /// @return The `meta.createdFromSafeAddress` field.
    /// @return The transactions, in order. Reverts `NoTransactions` if there
    /// are none.
    function fromJson(Vm vm, string memory json) internal view returns (uint256, address, SafeTx[] memory) {
        uint256 chainId = parseDecimal(vm.parseJsonString(json, ".chainId"));
        address safe = vm.parseJsonAddress(json, ".meta.createdFromSafeAddress");

        uint256 count = 0;
        while (vm.keyExistsJson(json, string.concat(".transactions[", vm.toString(count), "]"))) {
            count++;
        }
        if (count == 0) revert NoTransactions();

        SafeTx[] memory txs = new SafeTx[](count);
        for (uint256 i = 0; i < count; i++) {
            string memory entry = string.concat(".transactions[", vm.toString(i), "]");
            txs[i] = SafeTx({
                to: vm.parseJsonAddress(json, string.concat(entry, ".to")),
                value: parseDecimal(vm.parseJsonString(json, string.concat(entry, ".value"))),
                data: vm.parseJsonBytes(json, string.concat(entry, ".data")),
                operation: Enum.Operation.Call
            });
        }
        return (chainId, safe, txs);
    }

    /// Revert `ArtifactMismatch` unless `json` is exactly the bundle `expected`
    /// for `safe` on the current chain: chain id, Safe, entry count, and every
    /// entry's `to`, `value`, `operation` and `data`.
    /// @param vm The Vm, for the JSON cheatcodes.
    /// @param json The artifact.
    /// @param safe The Safe the bundle is for.
    /// @param expected The bundle re-derived from live state.
    function requireMatches(Vm vm, string memory json, address safe, SafeTx[] memory expected) internal view {
        (uint256 chainId, address parsedSafe, SafeTx[] memory parsed) = fromJson(vm, json);
        if (chainId != block.chainid) revert ArtifactMismatch("chainId");
        if (parsedSafe != safe) revert ArtifactMismatch("safe");
        if (parsed.length != expected.length) revert ArtifactMismatch("txCount");
        for (uint256 i = 0; i < expected.length; i++) {
            if (parsed[i].to != expected[i].to) revert ArtifactMismatch("to");
            if (parsed[i].value != expected[i].value) revert ArtifactMismatch("value");
            if (parsed[i].operation != expected[i].operation) revert ArtifactMismatch("operation");
            if (keccak256(parsed[i].data) != keccak256(expected[i].data)) revert ArtifactMismatch("data");
        }
    }

    /// Parse one or more ASCII digits as an unsigned integer. Reverts
    /// `NotDecimal` on anything else, and on overflow.
    /// @param value The digits.
    /// @return The integer.
    function parseDecimal(string memory value) internal pure returns (uint256) {
        bytes memory raw = bytes(value);
        if (raw.length == 0) revert NotDecimal(value);
        uint256 result = 0;
        for (uint256 i = 0; i < raw.length; i++) {
            uint8 c = uint8(raw[i]);
            if (c < 0x30 || c > 0x39) revert NotDecimal(value);
            result = result * 10 + (c - 0x30);
        }
        return result;
    }

    /// Revert `UnescapedJsonString` if `value` contains `"`, `\` or a control
    /// character.
    /// @param value The string.
    function requireUnescaped(string memory value) internal pure {
        bytes memory raw = bytes(value);
        for (uint256 i = 0; i < raw.length; i++) {
            bytes1 c = raw[i];
            if (c == '"' || c == "\\" || uint8(c) < 0x20) revert UnescapedJsonString(value);
        }
    }

    /// `"key":valueLiteral`.
    /// @param key The key.
    /// @param valueLiteral An already serialised JSON value.
    /// @return The field.
    function field(string memory key, string memory valueLiteral) private pure returns (string memory) {
        return string.concat('"', key, '":', valueLiteral);
    }

    /// `raw` as a JSON string literal. `raw` MUST need no escaping.
    /// @param raw The string.
    /// @return The literal.
    function quote(string memory raw) private pure returns (string memory) {
        return string.concat('"', raw, '"');
    }
}
