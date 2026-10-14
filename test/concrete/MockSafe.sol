// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockSafe
/// @notice A Safe stand-in whose `execTransaction` outcome is chosen by the
/// test, for the outcomes a real Safe never produces. Threshold and owners
/// are fixed; nothing it executes takes effect.
contract MockSafe {
    /// What `execTransaction` does.
    enum Mode {
        /// `GS020` below the threshold, `true` at it: a real Safe's gate.
        Gate,
        /// `true` at any signature count.
        AcceptAll,
        /// Revert with `iRevertReason` below the threshold, `true` at it.
        OtherRevert,
        /// `GS020` below the threshold, `false` at it.
        ReturnFalse
    }

    /// The signature-entry length a real Safe divides by.
    uint256 internal constant SIGNATURE_LENGTH = 65;

    /// The behaviour.
    Mode public immutable iMode;
    /// The threshold.
    uint256 public immutable iThreshold;
    /// The revert reason for `Mode.OtherRevert`.
    bytes public iRevertReason;
    /// The owners.
    address[] internal sOwners;

    /// @param mode The behaviour.
    /// @param owners The owners.
    /// @param threshold The threshold.
    /// @param revertReason The revert reason for `Mode.OtherRevert`.
    constructor(Mode mode, address[] memory owners, uint256 threshold, bytes memory revertReason) {
        iMode = mode;
        sOwners = owners;
        iThreshold = threshold;
        iRevertReason = revertReason;
    }

    function getThreshold() external view returns (uint256) {
        return iThreshold;
    }

    function getOwners() external view returns (address[] memory) {
        return sOwners;
    }

    function nonce() external pure returns (uint256) {
        return 0;
    }

    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256,
        uint256,
        uint256,
        address,
        address,
        uint256 _nonce
    ) external pure returns (bytes32) {
        return keccak256(abi.encode(to, value, data, operation, _nonce));
    }

    function approveHash(bytes32) external {}

    function execTransaction(
        address,
        uint256,
        bytes calldata,
        uint8,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes calldata signatures
    ) external payable returns (bool) {
        bool undersigned = signatures.length < iThreshold * SIGNATURE_LENGTH;
        if (iMode == Mode.AcceptAll) return true;
        if (undersigned) {
            if (iMode == Mode.OtherRevert) {
                bytes memory reason = iRevertReason;
                assembly ("memory-safe") {
                    revert(add(reason, 0x20), mload(reason))
                }
            }
            revert("GS020");
        }
        return iMode != Mode.ReturnFalse;
    }
}
