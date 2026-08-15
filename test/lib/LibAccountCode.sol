// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev The two bytes that open an EIP-7702 delegation designator, and the only
/// thing that separates one from ordinary contract code.
bytes2 constant DELEGATION_PREFIX = 0xef01;

/// @dev The one length EIP-7702 gives a delegation designator: the three-byte
/// `0xef0100` header and a twenty-byte address.
uint256 constant DELEGATION_DESIGNATOR_LENGTH = 23;

/// @title LibAccountCode
/// @notice What an account's code is allowed to BE, for tests that fuzz whatever
/// occupies a pinned address.
///
/// An account holds one of exactly two kinds of code, and a test that fuzzes
/// `bytes` alone does not have that domain — it has every byte string, most of
/// which no EVM can put in an account:
///
/// 1. ordinary contract code, which is any byte string that does not open with
///    `DELEGATION_PREFIX`;
/// 2. an EIP-7702 delegation designator, which opens with that prefix and is
///    `DELEGATION_DESIGNATOR_LENGTH` bytes, never any other length.
///
/// `vm.etch` enforces exactly that: a byte string opening `0xef01` at any other
/// length is refused with `Eip7702 is not 23 bytes long`, so a fuzzer that
/// reaches one fails the run on the cheatcode rather than finding anything
/// about the code under test. That failure is seed-dependent, so it arrives as a
/// test that was green yesterday and is red today over a fixture nobody touched.
///
/// The two kinds are covered by two tests rather than one, split on
/// `hasDelegationPrefix`, because they are different kinds of account and not
/// merely different values. The designator carries 23 bytes while the account
/// executes whatever the delegate holds, so it is the shape a test over
/// arbitrary `bytes` can never construct and the one an attacker reaches for.
library LibAccountCode {
    /// Whether `code` opens with the delegation designator prefix, and is
    /// therefore in kind 2 rather than kind 1.
    ///
    /// The prefix alone decides it. A byte string that opens `0xef01` at the
    /// wrong length is not ordinary code that happens to start awkwardly — it is
    /// a malformed designator, which is why `vm.etch` refuses it rather than
    /// storing it.
    /// @param code The candidate account code.
    /// @return True when `code` is in the delegation-designator family.
    function hasDelegationPrefix(bytes memory code) internal pure returns (bool) {
        return code.length >= 2 && code[0] == DELEGATION_PREFIX[0] && code[1] == DELEGATION_PREFIX[1];
    }

    /// The delegation designator that points an account at `delegate`.
    ///
    /// `delegate` of zero is the CLEARING form: it leaves the account with no
    /// code at all rather than 23 bytes of designator, so it is the empty-account
    /// case and not this one. Callers fuzzing a delegate assume it away.
    /// @param delegate The account being delegated to.
    /// @return designator The 23-byte designator.
    function delegationDesignator(address delegate) internal pure returns (bytes memory designator) {
        designator = abi.encodePacked(DELEGATION_PREFIX, bytes1(0), delegate);
    }
}
