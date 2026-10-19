// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

/// @title RegistryOptimizerRunsTest
/// @notice foundry.toml states the registries' optimizer runs three times: the
/// default and one compilation restriction per registry. Holds them equal.
contract RegistryOptimizerRunsTest is Test {
    function testRegistryRestrictionsMatchDefaultRuns() external view {
        string memory toml = vm.readFile("foundry.toml");
        uint256 defaultRuns = vm.parseTomlUint(toml, ".profile.default.optimizer_runs");
        bool sawConfig;
        bool sawMigration;
        for (uint256 i = 0;; i++) {
            string memory key = string.concat(".profile.default.compilation_restrictions[", vm.toString(i), "]");
            if (!vm.keyExistsToml(toml, key)) break;
            string memory path = vm.parseTomlString(toml, string.concat(key, ".paths"));
            bool isConfig = keccak256(bytes(path)) == keccak256("src/concrete/ConfigRegistry.sol");
            bool isMigration = keccak256(bytes(path)) == keccak256("src/concrete/MigrationRegistry.sol");
            if (isConfig || isMigration) {
                assertEq(vm.parseTomlUint(toml, string.concat(key, ".optimizer_runs")), defaultRuns, path);
                sawConfig = sawConfig || isConfig;
                sawMigration = sawMigration || isMigration;
            }
        }
        assertTrue(sawConfig, "ConfigRegistry restriction");
        assertTrue(sawMigration, "MigrationRegistry restriction");
    }
}
