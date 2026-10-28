// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployCandidate} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RegistryDeploySuites} from "../../../src/abstract/RegistryDeploySuites.sol";

/// @title RegistryDeploySuitesOptimizerRunsTest
/// @notice Every candidate is pinned by exactly one `compilation_restrictions`
/// entry in foundry.toml, and every first-party candidate's entry is the
/// default optimizer runs.
contract RegistryDeploySuitesOptimizerRunsTest is RegistryDeploySuites, Test {
    function testEveryCandidateRestrictedToItsRuns() external view {
        string memory toml = vm.readFile("foundry.toml");
        uint256 defaultRuns = vm.parseTomlUint(toml, ".profile.default.optimizer_runs");
        DeployCandidate[] memory candidates = declaration().candidates;
        assertGt(candidates.length, 0);
        for (uint256 c = 0; c < candidates.length; c++) {
            string memory source = vm.split(candidates[c].snapshot.artifactPath, ":")[0];
            uint256 matches = 0;
            for (uint256 i = 0;; i++) {
                string memory key = string.concat(".profile.default.compilation_restrictions[", vm.toString(i), "]");
                if (!vm.keyExistsToml(toml, key)) break;
                if (
                    keccak256(bytes(vm.parseTomlString(toml, string.concat(key, ".paths")))) != keccak256(bytes(source))
                ) {
                    continue;
                }
                matches++;
                if (vm.indexOf(source, "src/") == 0) {
                    assertEq(vm.parseTomlUint(toml, string.concat(key, ".optimizer_runs")), defaultRuns, source);
                }
            }
            assertEq(matches, 1, source);
        }
    }
}
