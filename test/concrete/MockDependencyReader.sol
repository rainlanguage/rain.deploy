// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

address constant READ_DEPENDENCY = address(0xdef2);

error ReadDependencyHasNoCode(address dependency);

/// A constant, not an immutable, so `type(MockDependencyReader).runtimeCode` exists and embeds the dependency.
contract MockDependencyReader {
    function readDependency() external view {
        if (READ_DEPENDENCY.code.length == 0) {
            revert ReadDependencyHasNoCode(READ_DEPENDENCY);
        }
    }
}
