// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title MockResolvedValues
/// @notice A deployment holding resolved values that are not addresses: a
/// threshold, a code hash and a signer list.
contract MockResolvedValues {
    /// A resolved threshold.
    uint256 public immutable iThreshold;
    /// A resolved code hash.
    bytes32 public immutable iCodeHash;
    /// A resolved signer list.
    address[] internal sSigners;

    /// @param threshold The threshold to hold.
    /// @param codeHash The code hash to hold.
    /// @param signerList The signer list to hold.
    constructor(uint256 threshold, bytes32 codeHash, address[] memory signerList) {
        iThreshold = threshold;
        iCodeHash = codeHash;
        sSigners = signerList;
    }

    /// @return The signer list.
    function signers() external view returns (address[] memory) {
        return sSigners;
    }
}
