// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript} from "../src/abstract/BuildScript.sol";
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
/// deploys. `run()` and `cutRelease()` are inherited from `BuildScript`.
///
/// Alias libs always point at `candidate`, so `LibAddressRegistry` and
/// `LibMigrationRegistry` resolve against what this repo currently compiles.
/// The frozen `<tag>/` directories are what
/// `RegistryDeploySuites.releasedSuites()` enumerates.
///
/// `generatedContracts()` is the only list, read by every hook below.
contract Build is BuildScript, RegistryDeploySuites {
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

    /// @inheritdoc BuildScript
    /// @dev In declaration order — the order the aggregate emits its entries
    /// in. Read by the freeze and the aggregate.
    function snapshotContractNames() internal pure override returns (string[] memory contractNames) {
        GeneratedContract[] memory contracts = generatedContracts();
        contractNames = new string[](contracts.length);
        for (uint256 i = 0; i < contracts.length; i++) {
            contractNames[i] = contracts[i].contractName;
        }
    }

    /// @inheritdoc BuildScript
    /// @dev Every alias lib, every released-suites lib and the aggregate over
    /// them.
    function regenerateLibs() internal override {
        GeneratedContract[] memory contracts = generatedContracts();
        for (uint256 i = 0; i < contracts.length; i++) {
            LibRainDeploySnapshot.writeAliasLib(
                vm, contracts[i].contractName, contracts[i].constantPrefix, LibRainDeploySnapshot.CANDIDATE
            );
            LibRainDeploySnapshot.writeReleasedSuitesLib(
                vm, recordRoot(), contracts[i].contractName, contracts[i].candidate.snapshot
            );
        }
        LibRainDeploySnapshot.writeReleasedSuitesAggregate(vm, LibRainDeploySnapshot.LIB_DIR, snapshotContractNames());
    }

    /// @inheritdoc BuildScript
    function regenerateSnapshots() internal override {
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
