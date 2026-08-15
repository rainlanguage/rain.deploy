// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {Build, InertRegistryRelease, checkReleasableRoot} from "../../script/Build.sol";
import {ADDRESS_REGISTRY_ROOT} from "../../src/concrete/AddressRegistry.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";

/// @title BuildTest
/// @notice The gate that keeps an inert `AddressRegistry` out of a release.
///
/// A release is the one step in the rollout that cannot be taken back — it
/// freezes a record, publishes a package and commits the repo to keeping that
/// address live on every network it will ever support. `run()`, the tests and
/// the manual broadcast are all repeatable, so none of them is gated and none
/// of them is asserted about here.
contract BuildTest is Test {
    /// External wrapper so `vm.expectRevert` lands at the right call depth.
    /// @param root The root to check.
    function externalCheckReleasableRoot(address root) external pure {
        checkReleasableRoot(root);
    }

    /// A build with no root MUST NOT be releasable. It can never answer a read,
    /// so freezing it declares a suite that is required live forever and is
    /// useful to nobody.
    function testCheckReleasableRootRefusesNoRoot() external {
        vm.expectRevert(InertRegistryRelease.selector);
        this.externalCheckReleasableRoot(address(0));
    }

    /// The rule is that the root is ABSENT, not that it is one particular
    /// account: EVERY other address is one that can bind a name, so every other
    /// address releases. A gate that admitted only some of them would be a
    /// second, unwritten policy about who root may be.
    function testCheckReleasableRootAcceptsEveryOtherRoot(address root) external view {
        vm.assume(root != address(0));

        this.externalCheckReleasableRoot(root);
    }

    /// The gate MUST be wired to the constant `AddressRegistry` actually
    /// compiles against, and it MUST fire before `cutRelease` writes anything:
    /// filesystem cheatcodes are not undone by a revert, so a refusal that
    /// landed after `freeze` created `<tag>/` would leave the tag frozen and
    /// every retry of that release refused as already cut.
    ///
    /// This test is also the marker for the rollout step itself.
    /// `ADDRESS_REGISTRY_ROOT` is zero today; the moment it is set this goes
    /// red and should be DELETED rather than repaired, because a real root IS
    /// releasable and that is the whole point of the gate. The assertion comes
    /// first so that failure cannot cut a real release on its way to being
    /// reported: under a real root the call below succeeds, and succeeding is
    /// what freezes a tag.
    function testCutReleaseRefusesTheInertRoot() external {
        assertEq(
            ADDRESS_REGISTRY_ROOT,
            address(0),
            "ADDRESS_REGISTRY_ROOT is set, so releases are permitted: delete this test"
        );

        string memory frozenDir = LibRainDeploySnapshot.dirForSnapshot(LibRainDeploySnapshot.deployTag(vm));
        bool frozenBefore = vm.exists(frozenDir);

        Build build = new Build();

        vm.expectRevert(InertRegistryRelease.selector);
        build.cutRelease();

        assertEq(vm.exists(frozenDir), frozenBefore, "refused release still touched the record");
    }
}
