// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title MockAddressRevertingFactory
/// Zoltu factory stand-in whose calls always fail, reverting with exactly the
/// twenty bytes of its own address. A caller that reads its call output buffer
/// without checking the call succeeded sees the address of a contract that has
/// code.
contract MockAddressRevertingFactory {
    fallback() external {
        bytes20 self = bytes20(address(this));
        assembly ("memory-safe") {
            mstore(0, self)
            revert(0, 20)
        }
    }
}
