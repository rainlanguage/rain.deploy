// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.2/src/Script.sol";
import {DeployCandidate} from "../src/abstract/RainDeploySuitesBase.sol";
import {RegistryDeploySuites} from "../src/abstract/RegistryDeploySuites.sol";
import {LibRainDeploySnapshot} from "../src/lib/LibRainDeploySnapshot.sol";

/// One contract's generated files: the rolling snapshot, the alias lib that
/// re-exports its pins and the released-suites lib emitted from its record.
struct GeneratedContract {
    /// Places the snapshot inside `src/generated/<dir>/` and names both
    /// generated libs.
    string contractName;
    /// Prefix for the constants the alias lib exports, e.g. `ADDRESS_REGISTRY`.
    string constantPrefix;
    /// Snapshots are written from its `sourceCreationCode` and
    /// `snapshot.dependencies`; the released lib takes its suite key and
    /// artifact path from its `snapshot`.
    DeployCandidate candidate;
}

/// @title Build
/// @notice Generates the deterministic-deploy pins for every contract this repo
/// deploys.
///
/// - `run()` rewrites the rolling snapshots under `src/generated/candidate/`,
///   the alias libs pointing at them, and the released-suites libs.
/// - `cutRelease()` does the same, freezing the rolling snapshots as
///   `src/generated/<tag>/` in between.
///
/// Alias libs always point at `candidate`, so `LibAddressRegistry` and
/// `LibMigrationRegistry` resolve against what this repo currently compiles.
/// The frozen `<tag>/` directories are what
/// `RegistryDeploySuites.releasedSuites()` enumerates.
///
/// `generatedContracts()` is the only list, read by the regeneration, both lib
/// writers and the freeze.
contract Build is Script, RegistryDeploySuites {
    /// Every contract this repo generates deploy pins for.
    /// @return contracts The generated contracts.
    function generatedContracts() internal pure returns (GeneratedContract[] memory contracts) {
        contracts = new GeneratedContract[](2);
        contracts[0] = GeneratedContract({
            contractName: "AddressRegistry", constantPrefix: "ADDRESS_REGISTRY", candidate: addressRegistryCandidate()
        });
        contracts[1] = GeneratedContract({
            contractName: "MigrationRegistry",
            constantPrefix: "MIGRATION_REGISTRY",
            candidate: migrationRegistryCandidate()
        });
    }

    /// @notice Regenerate the rolling snapshots, their alias libs and the
    /// released-suites libs.
    function run() external {
        regenerateCandidates();
        regenerateLibs();
    }

    /// @notice Regenerate the rolling snapshots, freeze them as
    /// `src/generated/<tag>/`, then rewrite the libs from the record, so the
    /// release being cut is in them.
    function cutRelease() external {
        GeneratedContract[] memory contracts = generatedContracts();
        string[] memory contractNames = new string[](contracts.length);
        for (uint256 i = 0; i < contracts.length; i++) {
            contractNames[i] = contracts[i].contractName;
        }
        LibRainDeploySnapshot.freeze(vm, LibRainDeploySnapshot.LIB_FS_ROOT, regenerateCandidates, contractNames);
        regenerateLibs();
    }

    /// @notice Rewrite every alias lib and every released-suites lib.
    function regenerateLibs() internal {
        GeneratedContract[] memory contracts = generatedContracts();
        for (uint256 i = 0; i < contracts.length; i++) {
            LibRainDeploySnapshot.writeAliasLib(
                vm, contracts[i].contractName, contracts[i].constantPrefix, LibRainDeploySnapshot.CANDIDATE
            );
            LibRainDeploySnapshot.writeReleasedSuitesLib(
                vm, LibRainDeploySnapshot.LIB_FS_ROOT, contracts[i].contractName, contracts[i].candidate.snapshot
            );
        }
    }

    /// @notice Rewrite every `src/generated/candidate/` snapshot from what this
    /// repo currently compiles.
    function regenerateCandidates() internal {
        GeneratedContract[] memory contracts = generatedContracts();
        for (uint256 i = 0; i < contracts.length; i++) {
            LibRainDeploySnapshot.writeSnapshot(
                vm,
                LibRainDeploySnapshot.CANDIDATE,
                contracts[i].contractName,
                contracts[i].candidate.sourceCreationCode,
                contracts[i].candidate.snapshot.dependencies
            );
        }
    }
}
