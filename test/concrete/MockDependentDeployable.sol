// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {MockDeployable} from "./MockDeployable.sol";

/// Thrown when a dependency the constructor was handed holds no code.
/// @param dependency The address with no code.
error DependencyHasNoCode(address dependency);

/// Thrown when a dependency does not ANSWER `MockDeployable`'s getter.
/// @param dependency The address that did not answer.
error DependencyDidNotAnswer(address dependency);

/// @title MockDependentDeployable
/// @notice A deployment target whose CONSTRUCTOR reads its dependencies, the
/// shape OZ's `UpgradeableBeacon` has. It CALLS each one and requires an answer
/// of the right SHAPE, because a `code.length` check alone is satisfied by a
/// single non-zero byte; the answer's VALUE is not asserted, because `vm.etch`
/// plants code and not storage, so the getter over an etch answers zero. Stored
/// rather than `immutable`, so the runtime code does not vary with the
/// constructor argument.
contract MockDependentDeployable {
    /// How many dependencies the constructor read.
    uint256 public sDependencyCount;

    /// @param dependencies Addresses that MUST already hold `MockDeployable`'s
    /// code.
    constructor(address[] memory dependencies) {
        for (uint256 i = 0; i < dependencies.length; i++) {
            if (dependencies[i].code.length == 0) {
                revert DependencyHasNoCode(dependencies[i]);
            }
            (bool success, bytes memory answer) =
                dependencies[i].staticcall(abi.encodeWithSelector(MockDeployable(dependencies[i]).sValue.selector));
            if (!success || answer.length != 32) {
                revert DependencyDidNotAnswer(dependencies[i]);
            }
        }
        sDependencyCount = dependencies.length;
    }
}
