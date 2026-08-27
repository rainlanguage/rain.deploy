// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibStringSet
/// @notice Membership over a `string[]`, for an assertion about a set whose
/// order it does not fix.
///
/// Solidity has no string equality and no set, so a caller that wants "this
/// list holds this string" writes a keccak loop. WHY a caller wants membership
/// rather than an index or an ordering is the caller's own reasoning and stays
/// with the caller; what happens here is only the comparison, which is the same
/// comparison wherever it is asked for.
library LibStringSet {
    /// Whether `haystack` holds `needle`.
    ///
    /// Compared by hash rather than by length-then-bytes because `keccak256`
    /// over the whole string is one call per element and cannot disagree with
    /// itself about what equality is.
    /// @param haystack The strings to search.
    /// @param needle The string to find.
    /// @return Whether it is present.
    function holds(string[] memory haystack, string memory needle) internal pure returns (bool) {
        for (uint256 i = 0; i < haystack.length; i++) {
            if (keccak256(bytes(haystack[i])) == keccak256(bytes(needle))) {
                return true;
            }
        }
        return false;
    }
}
