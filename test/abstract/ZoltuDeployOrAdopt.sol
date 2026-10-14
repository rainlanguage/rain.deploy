// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";

/// @title ZoltuDeployOrAdopt
/// @notice Puts a clone fixture's factory or implementation at its Zoltu address on a fork, for
/// every fork test that broadcasts a clone through them.
abstract contract ZoltuDeployOrAdopt is Test {
    /// Puts the fixture's factory or implementation at its DECLARED Zoltu address on the selected
    /// fork, or confirms what is already there is it.
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
