// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";

/// @title ZoltuDeployOrAdopt
/// @notice Puts a clone fixture's factory or implementation at its Zoltu
/// address on a fork, for every fork test that broadcasts a clone through them.
abstract contract ZoltuDeployOrAdopt is Test {
    /// Puts the fixture's factory or implementation at its DECLARED Zoltu address
    /// on the selected fork, or confirms what is already there is it.
    ///
    /// A bare `deployZoltu` cannot be used, and the reason is a real property of
    /// this fixture rather than an inconvenience. `MockCloneFactory` is pure
    /// delegation into `LibICloneableFactoryV4`, which is also exactly how the
    /// factory `rain-factory-deploy` ships is written — and this repo compiles
    /// with `bytecode_hash = "none"` and `cbor_metadata = false`, so there is
    /// nothing left in the artifact to tell two identical sources apart. The
    /// Zoltu address is a pure function of the creation code, so the mock's
    /// declared address IS the production factory's, and the production factory
    /// is already deployed there on every network `rain-factory-deploy` has
    /// reached: measured at `0x12E8…Ac40` on both arbitrum and polygon, with the
    /// same code hash the mock's runtime code has.
    ///
    /// A second `CREATE2` at an occupied address is a `CreateCollision`, which
    /// consumes every unit of gas forwarded to it and surfaces as
    /// `DeployFailed(false, address(0))`.
    ///
    /// So: deploy where absent, and where present assert the code is the code
    /// the fixture derives its clone addresses from. The assertion is the point
    /// of the branch — skipping the deploy without it would let this test predict
    /// clone addresses against a factory it never checked, which is the one thing
    /// a clone has no source anchor to catch.
    /// @param creationCode The creation code whose Zoltu address is wanted.
    /// @param runtimeCode The runtime code that creation code leaves behind.
    /// @return The declared address, now holding that runtime code.
    function zoltuDeployOrAdopt(bytes memory creationCode, bytes memory runtimeCode) internal returns (address) {
        address declared = LibRainDeploy.zoltuAddress(creationCode);
        if (declared.code.length == 0) {
            assertEq(LibRainDeploy.deployZoltu(creationCode), declared, "zoltu deployed off its derived address");
        } else {
            assertEq(declared.codehash, keccak256(runtimeCode), "something else occupies the declared address");
        }
        return declared;
    }
}
