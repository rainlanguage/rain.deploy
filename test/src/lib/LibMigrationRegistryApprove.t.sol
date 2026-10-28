// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibMigrationRegistryApprove} from "../../../src/lib/LibMigrationRegistryApprove.sol";
import {LibMigrationRegistryDeploy} from "../../../src/lib/LibMigrationRegistryDeploy.sol";
import {RegistryDelegation} from "../../../src/lib/LibRegistryDelegatesApprove.sol";

/// @title LibMigrationRegistryApproveTest
/// The migration registry the approval run drives is the pinned one.
contract LibMigrationRegistryApproveTest is Test {
    function testDelegationIsThePinnedRegistry() external pure {
        RegistryDelegation memory r = LibMigrationRegistryApprove.delegation();
        assertEq(r.registry, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(r.codehash, LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH);
    }
}
