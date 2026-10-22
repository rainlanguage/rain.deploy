// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    ApproveRegistryDelegateWiringTest,
    ILocalApproveRegistryDelegate
} from "../abstract/ApproveRegistryDelegateWiringTest.sol";
import {LibMigrationRegistryDeploy} from "../../src/lib/LibMigrationRegistryDeploy.sol";
import {MigrationRegistry} from "../../src/concrete/MigrationRegistry.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LocalApproveMigrationDelegate} from "../concrete/LocalApproveMigrationDelegate.sol";

/// @title ApproveMigrationDelegateTest
/// `ApproveRegistryDelegateWiringTest` on `ApproveMigrationDelegate`.
contract ApproveMigrationDelegateTest is ApproveRegistryDelegateWiringTest {
    function newScript() internal override returns (ILocalApproveRegistryDelegate) {
        return ILocalApproveRegistryDelegate(address(new LocalApproveMigrationDelegate()));
    }

    function prefix() internal pure override returns (string memory) {
        return "MIGRATION_DELEGATE";
    }

    function pinned() internal pure override returns (address, bytes32) {
        return (
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
            LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH
        );
    }

    function deployRegistry() internal override {
        LibRainDeploy.etchAndDeployZoltu(vm, type(MigrationRegistry).creationCode);
    }
}
