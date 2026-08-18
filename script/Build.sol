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
///   the alias libs pointing at them, the released-suites libs and the
///   aggregate over them.
/// - `cutRelease()` does the same, freezing the rolling snapshots as
///   `src/generated/<tag>/` in between.
///
/// Alias libs always point at `candidate`, so `LibAddressRegistry` and
/// `LibMigrationRegistry` resolve against what this repo currently compiles.
/// The frozen `<tag>/` directories are what
/// `RegistryDeploySuites.releasedSuites()` enumerates.
///
/// `generatedContracts()` is the only list, read by the regeneration, all three
/// lib writers and the freeze.
contract Build is Script, RegistryDeploySuites {
    /// Every contract this repo generates deploy pins for.
    /// @return The generated contracts.
    function generatedContracts() internal pure returns (GeneratedContract[] memory) {
        GeneratedContract[] memory contracts = new GeneratedContract[](2);
        contracts[0] = GeneratedContract({
            contractName: "AddressRegistry", constantPrefix: "ADDRESS_REGISTRY", candidate: addressRegistryCandidate()
        });
        contracts[1] = GeneratedContract({
            contractName: "MigrationRegistry",
            constantPrefix: "MIGRATION_REGISTRY",
            candidate: migrationRegistryCandidate()
        });
        return contracts;
    }

    /// Every generated contract's name, in declaration order — the order the
    /// aggregate emits its entries in. Read by the freeze and the aggregate.
    /// @return The contract names.
    function generatedContractNames() internal pure returns (string[] memory) {
        GeneratedContract[] memory contracts = generatedContracts();
        string[] memory names = new string[](contracts.length);
        for (uint256 i = 0; i < contracts.length; i++) {
            names[i] = contracts[i].contractName;
        }
        return names;
    }

    /// @notice Regenerate the rolling snapshots, their alias libs, the
    /// released-suites libs and the aggregate over them.
    function run() external {
        regenerateCandidates();
        regenerateLibs();
    }

    /// @notice Regenerate the rolling snapshots, freeze them as
    /// `src/generated/<tag>/`, then rewrite the libs from the record, so the
    /// release being cut is in them.
    function cutRelease() external {
        LibRainDeploySnapshot.freeze(
            vm, LibRainDeploySnapshot.LIB_FS_ROOT, regenerateCandidates, generatedContractNames()
        );
        regenerateLibs();
    }

    /// @notice Rewrite every alias lib, every released-suites lib and the
    /// aggregate over them.
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
        LibRainDeploySnapshot.writeReleasedSuitesAggregate(vm, LibRainDeploySnapshot.LIB_DIR, generatedContractNames());
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
