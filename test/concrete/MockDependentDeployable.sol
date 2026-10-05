// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {MockDeployable} from "./MockDeployable.sol";

/// Thrown by `MockDependentDeployable`'s constructor when a dependency it was
/// handed holds no code.
/// @param dependency The address with no code.
error DependencyHasNoCode(address dependency);

/// Thrown by `MockDependentDeployable`'s constructor when a dependency holds
/// code that does not ANSWER `MockDeployable`'s getter — the call failed, or it
/// returned something that is not a `uint256`.
/// @param dependency The address that did not answer.
error DependencyDidNotAnswer(address dependency);

/// @title MockDependentDeployable
/// @notice A deployment target whose CONSTRUCTOR reads its dependencies — the
/// shape OZ's `UpgradeableBeacon` has, which reverts
/// `BeaconInvalidImplementation` on an implementation with no code.
///
/// It CALLS each dependency and requires an answer, rather than only checking
/// `code.length`. A length check alone is satisfied by a single non-zero byte,
/// so a derivation that planted anything at all at the address would pass it —
/// and a mock that could not tell those apart could not tell whether the
/// derivation etched the declared runtime code or merely something. A single
/// `0x00` byte is `STOP`: the call succeeds and returns nothing, so the SHAPE of
/// the answer is what separates etched code from a presence marker.
///
/// The answer's VALUE is deliberately not asserted. `vm.etch` plants code and
/// not storage, so `MockDeployable`'s getter over an etch answers zero rather
/// than the 42 its own constructor would have stored. A dependency etched from a
/// published `RUNTIME_CODE` is code without the state the real deployment has —
/// a property of etching, not a defect in it — and nothing about whether the
/// DECLARED code was etched is carried by that value.
///
/// The dependencies arrive as a constructor argument appended to the creation
/// code, which is the only way the Zoltu factory can pass one: its calldata IS
/// the creation code. A LIST rather than one address, so a derivation that
/// etched only the first entry of a declaration is a derivation this fails on.
///
/// Stored rather than `immutable`, so the runtime code does not vary with the
/// argument. A snapshot records ONE runtime code and one code hash, and these
/// tests assert the derived hash against `type(X).runtimeCode`, which it can
/// only be if the constructor argument stays out of the runtime code.
contract MockDependentDeployable {
    /// How many dependencies the constructor read, so the contract has
    /// non-trivial code and the read is observable.
    uint256 public sDependencyCount;

    /// @param dependencies The addresses that MUST already hold
    /// `MockDeployable`'s code, every one of which is read here.
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
