// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Enum} from "safe-global-safe-smart-account-1.5.0/contracts/libraries/Enum.sol";
import {LibSafeTx, SafeTx} from "../../../src/lib/LibSafeTx.sol";
import {LibSafeTxBuilderJson} from "../../../src/lib/LibSafeTxBuilderJson.sol";

/// @title LibSafeTxBuilderJsonTest
contract LibSafeTxBuilderJsonTest is Test {
    function externalToJson(address safe, uint256 chainId, string memory name, SafeTx[] memory txs)
        external
        view
        returns (string memory)
    {
        return LibSafeTxBuilderJson.toJson(vm, safe, chainId, name, txs);
    }

    function externalFromJson(string memory json) external view returns (uint256, address, SafeTx[] memory) {
        return LibSafeTxBuilderJson.fromJson(vm, json);
    }

    function externalRequireMatches(string memory json, address safe, SafeTx[] memory expected) external view {
        LibSafeTxBuilderJson.requireMatches(vm, json, safe, expected);
    }

    function externalParseDecimal(string memory value) external pure returns (uint256) {
        return LibSafeTxBuilderJson.parseDecimal(value);
    }

    function externalRequireUnescaped(string memory value) external pure {
        LibSafeTxBuilderJson.requireUnescaped(value);
    }

    function twoTxs() internal pure returns (SafeTx[] memory) {
        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = SafeTx({
            to: address(0x1111111111111111111111111111111111111111),
            value: 12,
            data: hex"aabb",
            operation: Enum.Operation.Call
        });
        txs[1] = SafeTx({
            to: address(0x2222222222222222222222222222222222222222), value: 0, data: "", operation: Enum.Operation.Call
        });
        return txs;
    }

    /// The JSON is exactly the Transaction Builder import shape.
    function testToJsonExact() external {
        vm.warp(1700000000);
        string memory json = LibSafeTxBuilderJson.toJson(
            vm, address(0x3333333333333333333333333333333333333333), 8453, "bundle", twoTxs()
        );
        assertEq(
            json,
            string.concat(
                '{"version":"1.0","chainId":"8453","createdAt":1700000000000,',
                '"meta":{"name":"bundle","txBuilderVersion":"1.16.5",',
                '"createdFromSafeAddress":"0x3333333333333333333333333333333333333333"},',
                '"transactions":[',
                '{"to":"0x1111111111111111111111111111111111111111","value":"12","data":"0xaabb"},',
                '{"to":"0x2222222222222222222222222222222222222222","value":"0","data":"0x"}',
                "]}"
            )
        );
    }

    /// Whatever is written reads back the same.
    function testRoundTrip(address safe, uint256 chainId, address[] memory tos, uint256 seed) external view {
        vm.assume(tos.length > 0 && tos.length <= 20);
        SafeTx[] memory txs = new SafeTx[](tos.length);
        for (uint256 i = 0; i < tos.length; i++) {
            bytes32 r = keccak256(abi.encode(seed, i));
            txs[i] = SafeTx({
                to: tos[i], value: uint256(r) >> (i * 8), data: abi.encodePacked(r, i), operation: Enum.Operation.Call
            });
            if (i % 3 == 0) txs[i].data = "";
        }
        string memory json = LibSafeTxBuilderJson.toJson(vm, safe, chainId, "round trip", txs);
        (uint256 parsedChainId, address parsedSafe, SafeTx[] memory parsed) = LibSafeTxBuilderJson.fromJson(vm, json);
        assertEq(parsedChainId, chainId);
        assertEq(parsedSafe, safe);
        assertEq(parsed.length, txs.length);
        for (uint256 i = 0; i < txs.length; i++) {
            assertEq(parsed[i].to, txs[i].to);
            assertEq(parsed[i].value, txs[i].value);
            assertEq(parsed[i].data, txs[i].data);
            assertEq(uint8(parsed[i].operation), uint8(Enum.Operation.Call));
        }
    }

    /// A file exported by the Transaction Builder, with the fields it adds that
    /// this library does not write, reads as its raw transactions.
    function testFromJsonExported() external view {
        string memory json = string.concat(
            '{"version":"1.0","chainId":"1","createdAt":1718000000000,',
            '"meta":{"name":"Transactions Batch","description":"","txBuilderVersion":"1.16.5",',
            '"createdFromSafeAddress":"0x3333333333333333333333333333333333333333",',
            '"createdFromOwnerAddress":"","checksum":"0x1234"},',
            '"transactions":[{"to":"0x1111111111111111111111111111111111111111","value":"1000000000000000000",',
            '"data":"0x01","contractMethod":null,"contractInputsValues":null}]}'
        );
        (uint256 chainId, address safe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, json);
        assertEq(chainId, 1);
        assertEq(safe, address(0x3333333333333333333333333333333333333333));
        assertEq(txs.length, 1);
        assertEq(txs[0].to, address(0x1111111111111111111111111111111111111111));
        assertEq(txs[0].value, 1e18);
        assertEq(txs[0].data, hex"01");
    }

    /// An empty bundle is neither written nor read.
    function testNoTransactions() external {
        vm.expectRevert(LibSafeTxBuilderJson.NoTransactions.selector);
        this.externalToJson(address(1), 1, "x", new SafeTx[](0));
        vm.expectRevert(LibSafeTxBuilderJson.NoTransactions.selector);
        this.externalFromJson(
            '{"chainId":"1","meta":{"createdFromSafeAddress":"0x3333333333333333333333333333333333333333"},"transactions":[]}'
        );
    }

    /// A DELEGATECALL entry is not written.
    function testToJsonRejectsDelegateCall() external {
        SafeTx[] memory txs = twoTxs();
        txs[1].operation = Enum.Operation.DelegateCall;
        vm.expectRevert(abi.encodeWithSelector(LibSafeTx.UnsupportedOperation.selector, 1, Enum.Operation.DelegateCall));
        this.externalToJson(address(1), 1, "x", txs);
    }

    /// A name that would need escaping is not written: `"`, `\`, and the
    /// control characters 0x00 to 0x1f.
    function testToJsonRejectsUnescapedName() external {
        bytes memory rejected = hex"0001091f225c";
        for (uint256 i = 0; i < rejected.length; i++) {
            string memory name = string(abi.encodePacked("a", rejected[i], "b"));
            vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.UnescapedJsonString.selector, name));
            this.externalToJson(address(1), 1, name, twoTxs());
        }
    }

    /// The bytes either side of the rejected ones, and the top of the range,
    /// are left alone.
    function testRequireUnescapedAccepts() external pure {
        bytes memory accepted = hex"2021235b5d7e7fff";
        for (uint256 i = 0; i < accepted.length; i++) {
            LibSafeTxBuilderJson.requireUnescaped(string(abi.encodePacked("a", accepted[i], "b")));
        }
    }

    /// `parseDecimal` inverts `vm.toString`.
    function testParseDecimalInvertsToString(uint256 value) external pure {
        assertEq(LibSafeTxBuilderJson.parseDecimal(vm.toString(value)), value);
    }

    /// Leading zeros are digits like any other.
    function testParseDecimalLeadingZeros() external pure {
        assertEq(LibSafeTxBuilderJson.parseDecimal("007"), 7);
    }

    /// Anything but one or more digits is rejected, including a hex literal.
    function testParseDecimalRejects() external {
        string[6] memory bad = ["", "0x1", "1a", " 1", "-1", "1/"];
        for (uint256 i = 0; i < bad.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.NotDecimal.selector, bad[i]));
            this.externalParseDecimal(bad[i]);
        }
        // ':' is the byte after '9'.
        vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.NotDecimal.selector, "9:"));
        this.externalParseDecimal("9:");
    }

    /// A value past `type(uint256).max` reverts rather than wrapping.
    function testParseDecimalOverflow() external {
        vm.expectRevert();
        this.externalParseDecimal("115792089237316195423570985008687907853269984665640564039457584007913129639936");
    }

    /// A malformed `value` field fails the read.
    function testFromJsonRejectsBadValue() external {
        vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.NotDecimal.selector, "0x1"));
        this.externalFromJson(
            string.concat(
                '{"chainId":"1","meta":{"createdFromSafeAddress":"0x3333333333333333333333333333333333333333"},',
                '"transactions":[{"to":"0x1111111111111111111111111111111111111111","value":"0x1","data":"0x"}]}'
            )
        );
    }

    function artifact(address safe, SafeTx[] memory txs) internal view returns (string memory) {
        return LibSafeTxBuilderJson.toJson(vm, safe, block.chainid, "artifact", txs);
    }

    /// The artifact of exactly the expected bundle passes.
    function testRequireMatchesExact() external view {
        LibSafeTxBuilderJson.requireMatches(vm, artifact(address(3), twoTxs()), address(3), twoTxs());
    }

    function expectMismatch(string memory json, address safe, SafeTx[] memory expected, string memory fieldName)
        internal
    {
        vm.expectRevert(abi.encodeWithSelector(LibSafeTxBuilderJson.ArtifactMismatch.selector, fieldName));
        this.externalRequireMatches(json, safe, expected);
    }

    /// Every field a signer relies on is compared.
    function testRequireMatchesEachField() external {
        string memory json = artifact(address(3), twoTxs());
        SafeTx[] memory expected;

        expectMismatch(
            LibSafeTxBuilderJson.toJson(vm, address(3), block.chainid + 1, "artifact", twoTxs()),
            address(3),
            twoTxs(),
            "chainId"
        );

        expectMismatch(json, address(4), twoTxs(), "safe");

        expected = new SafeTx[](1);
        expected[0] = twoTxs()[0];
        expectMismatch(json, address(3), expected, "txCount");

        expected = twoTxs();
        expected[1].to = address(5);
        expectMismatch(json, address(3), expected, "to");

        expected = twoTxs();
        expected[1].value = 1;
        expectMismatch(json, address(3), expected, "value");

        expected = twoTxs();
        expected[1].operation = Enum.Operation.DelegateCall;
        expectMismatch(json, address(3), expected, "operation");

        expected = twoTxs();
        expected[1].data = hex"00";
        expectMismatch(json, address(3), expected, "data");
    }
}
