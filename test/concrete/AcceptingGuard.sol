// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// A guard v1.4.1 `setGuard` accepts: it checks only ERC-165 support.
contract AcceptingGuard {
    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}
