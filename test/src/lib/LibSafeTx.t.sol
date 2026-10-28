// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibSafeTx, SafeTx} from "../../../src/lib/LibSafeTx.sol";
import {LibSafe} from "../../../src/lib/LibSafe.sol";
import {Safe} from "safe-global-safe-smart-account-1.5.0/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.5.0/contracts/libraries/Enum.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibForkSafe} from "../../lib/LibForkSafe.sol";

/// @title LibSafeTxTest
/// @notice Hashes are checked against the EIP-712 encoding the Safe v1.4.1
/// source defines, computed here independently, on a real Safe; the
/// MultiSend and signature encodings against byte layouts written out by hand.
contract LibSafeTxTest is Test {
    /// Safe v1.4.1 `DOMAIN_SEPARATOR_TYPEHASH`.
    bytes32 internal constant DOMAIN_SEPARATOR_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");

    /// Safe v1.4.1 `SAFE_TX_TYPEHASH`.
    bytes32 internal constant SAFE_TX_TYPEHASH = keccak256(
        "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)"
    );

    function externalEncodeMultiSend(SafeTx[] memory txs) external pure returns (bytes memory) {
        return LibSafeTx.encodeMultiSend(txs);
    }

    function externalMultiSendTx(SafeTx[] memory txs) external view returns (SafeTx memory) {
        return LibSafeTx.multiSendTx(txs);
    }

    function externalApprovedHashSignatures(address[] memory signers) external pure returns (bytes memory) {
        return LibSafeTx.approvedHashSignatures(signers);
    }

    function forkSafe() internal returns (Safe) {
        vm.createSelectFork(LibRainDeploy.BASE);
        address[] memory owners = new address[](2);
        owners[0] = makeAddr("owner0");
        owners[1] = makeAddr("owner1");
        return LibForkSafe.deploy(owners, 2);
    }

    /// The Safe v1.4.1 EIP-712 hash of a zero-refund transaction.
    function eip712(Safe safe, SafeTx memory txn, uint256 nonce) internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_SEPARATOR_TYPEHASH, block.chainid, address(safe)));
        bytes32 structHash = keccak256(
            abi.encode(
                SAFE_TX_TYPEHASH,
                txn.to,
                txn.value,
                keccak256(txn.data),
                txn.operation,
                uint256(0),
                uint256(0),
                uint256(0),
                address(0),
                address(0),
                nonce
            )
        );
        return keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator, structHash));
    }

    /// `safeTxHash` is the EIP-712 hash the Safe signs, under that Safe's
    /// domain, for every field and nonce.
    function testSafeTxHashIsEip712() external {
        Safe safe = forkSafe();
        SafeTx memory txn =
            SafeTx({to: address(0xdead), value: 7, data: hex"abcdef", operation: Enum.Operation.DelegateCall});
        assertEq(LibSafeTx.safeTxHash(safe, txn, 3), eip712(safe, txn, 3));
        txn.operation = Enum.Operation.Call;
        assertEq(LibSafeTx.safeTxHash(safe, txn, 0), eip712(safe, txn, 0));
        txn.to = address(safe);
        txn.value = 0;
        txn.data = "";
        assertEq(LibSafeTx.safeTxHash(safe, txn, type(uint256).max), eip712(safe, txn, type(uint256).max));
    }

    /// `encodeMultiSend` packs every entry `operation || to || value ||
    /// dataLength || data`, in order, behind the `multiSend(bytes)` selector.
    function testEncodeMultiSendLayout() external pure {
        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = SafeTx({
            to: address(0x1111111111111111111111111111111111111111),
            value: 2,
            data: hex"aabb",
            operation: Enum.Operation.Call
        });
        txs[1] = SafeTx({
            to: address(0x2222222222222222222222222222222222222222), value: 0, data: "", operation: Enum.Operation.Call
        });
        bytes memory payload = bytes.concat(
            hex"00",
            hex"1111111111111111111111111111111111111111",
            bytes32(uint256(2)),
            bytes32(uint256(2)),
            hex"aabb",
            hex"00",
            hex"2222222222222222222222222222222222222222",
            bytes32(0),
            bytes32(0)
        );
        assertEq(LibSafeTx.encodeMultiSend(txs), abi.encodeWithSelector(bytes4(0x8d80ff0a), payload));
    }

    /// An empty bundle encodes as an empty payload.
    function testEncodeMultiSendEmpty() external pure {
        assertEq(LibSafeTx.encodeMultiSend(new SafeTx[](0)), abi.encodeWithSelector(bytes4(0x8d80ff0a), ""));
    }

    /// A DELEGATECALL entry anywhere in the bundle is rejected, naming its
    /// index and operation.
    function testEncodeMultiSendRejectsDelegateCall(uint8 length, uint8 index) external {
        length = uint8(bound(length, 1, 8));
        index = uint8(bound(index, 0, length - 1));
        SafeTx[] memory txs = new SafeTx[](length);
        txs[index].operation = Enum.Operation.DelegateCall;
        vm.expectRevert(
            abi.encodeWithSelector(LibSafeTx.UnsupportedOperation.selector, index, Enum.Operation.DelegateCall)
        );
        this.externalEncodeMultiSend(txs);
    }

    /// Where `LibSafe.SAFE_V1_4_1_MULTI_SEND_CALL_ONLY` holds no code, or other
    /// code, no bundle is built, because a DELEGATECALL there would do nothing.
    function testMultiSendTxRejectsWrongCode(bytes memory code) external {
        vm.assume(keccak256(code) != LibSafe.SAFE_V1_4_1_MULTI_SEND_CALL_ONLY_CODEHASH);
        vm.assume(code.length == 0 || code[0] != 0xef);
        bytes32 actual = code.length == 0 ? bytes32(0) : keccak256(code);
        vm.etch(LibSafe.SAFE_V1_4_1_MULTI_SEND_CALL_ONLY, code);
        if (code.length == 0) {
            // An account with no code, balance or nonce has code hash 0.
            assertEq(LibSafe.SAFE_V1_4_1_MULTI_SEND_CALL_ONLY.codehash, bytes32(0));
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeCodehashMismatch.selector,
                LibSafe.SAFE_V1_4_1_MULTI_SEND_CALL_ONLY,
                LibSafe.SAFE_V1_4_1_MULTI_SEND_CALL_ONLY_CODEHASH,
                actual
            )
        );
        this.externalMultiSendTx(new SafeTx[](1));
    }

    /// A bundle is one DELEGATECALL of its MultiSend encoding, and its hash is
    /// that transaction's EIP-712 hash.
    function testMultiSendTxAndHash() external {
        Safe safe = forkSafe();
        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = SafeTx({to: address(0xbeef), value: 1, data: hex"01", operation: Enum.Operation.Call});
        txs[1] = SafeTx({to: address(safe), value: 0, data: hex"0203", operation: Enum.Operation.Call});
        SafeTx memory wrapped = LibSafeTx.multiSendTx(txs);
        assertEq(wrapped.to, LibSafe.SAFE_V1_4_1_MULTI_SEND_CALL_ONLY);
        assertEq(wrapped.value, 0);
        assertEq(uint8(wrapped.operation), uint8(Enum.Operation.DelegateCall));
        assertEq(wrapped.data, LibSafeTx.encodeMultiSend(txs));
        assertEq(LibSafeTx.multiSendSafeTxHash(safe, txs, 5), eip712(safe, wrapped, 5));
    }

    /// `sortAscending` returns a new ascending permutation of its input and
    /// leaves the input as it was.
    function testSortAscending(address[] memory addrs) external pure {
        address[] memory original = new address[](addrs.length);
        for (uint256 i = 0; i < addrs.length; i++) {
            original[i] = addrs[i];
        }
        address[] memory sorted = LibSafeTx.sortAscending(addrs);
        assertEq(addrs, original, "input moved");
        assertEq(sorted.length, addrs.length);
        for (uint256 i = 1; i < sorted.length; i++) {
            assertLe(uint160(sorted[i - 1]), uint160(sorted[i]), "not ascending");
        }
        for (uint256 i = 0; i < addrs.length; i++) {
            uint256 inInput = 0;
            uint256 inSorted = 0;
            for (uint256 j = 0; j < addrs.length; j++) {
                if (addrs[j] == addrs[i]) inInput++;
                if (sorted[j] == addrs[i]) inSorted++;
            }
            assertEq(inSorted, inInput, "not a permutation");
        }
    }

    /// Signers are packed ascending as `r = signer, s = 0, v = 1`.
    function testApprovedHashSignaturesLayout() external pure {
        address[] memory signers = new address[](2);
        signers[0] = address(0x2222222222222222222222222222222222222222);
        signers[1] = address(0x1111111111111111111111111111111111111111);
        assertEq(
            LibSafeTx.approvedHashSignatures(signers),
            bytes.concat(
                bytes32(uint256(uint160(signers[1]))),
                bytes32(0),
                hex"01",
                bytes32(uint256(uint160(signers[0]))),
                bytes32(0),
                hex"01"
            )
        );
    }

    /// No signers pack to no bytes; any count packs to 65 bytes each.
    function testApprovedHashSignaturesLength(uint8 count) external pure {
        address[] memory signers = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            signers[i] = address(uint160(i + 1));
        }
        assertEq(LibSafeTx.approvedHashSignatures(signers).length, uint256(count) * LibSafeTx.SIGNATURE_LENGTH);
    }

    /// A repeated signer is rejected wherever it appears.
    function testApprovedHashSignaturesRejectsDuplicate(address[] memory signers, uint256 a, uint256 b) external {
        vm.assume(signers.length >= 2);
        a = bound(a, 0, signers.length - 1);
        b = bound(b, 0, signers.length - 1);
        vm.assume(a != b);
        signers[b] = signers[a];
        address[] memory sorted = LibSafeTx.sortAscending(signers);
        address duplicate;
        for (uint256 i = 1; i < sorted.length; i++) {
            if (sorted[i] == sorted[i - 1]) {
                duplicate = sorted[i];
                break;
            }
        }
        vm.expectRevert(abi.encodeWithSelector(LibSafeTx.DuplicateSigner.selector, duplicate));
        this.externalApprovedHashSignatures(signers);
    }

    /// A DELEGATECALL is rejected, naming its index; a CALL is not.
    function testRequireCall(uint256 index) external {
        LibSafeTx.requireCall(index, Enum.Operation.Call);
        vm.expectRevert(
            abi.encodeWithSelector(LibSafeTx.UnsupportedOperation.selector, index, Enum.Operation.DelegateCall)
        );
        this.externalRequireCall(index, Enum.Operation.DelegateCall);
    }

    function externalRequireCall(uint256 index, Enum.Operation operation) external pure {
        LibSafeTx.requireCall(index, operation);
    }
}
