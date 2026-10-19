// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript} from "../src/abstract/BuildScript.sol";
import {DeployCandidate} from "../src/abstract/RainDeploySuitesBase.sol";
import {ParameterisedContract, RegistryDeploySuites} from "../src/abstract/RegistryDeploySuites.sol";
import {LibRainDeploySnapshot} from "../src/lib/LibRainDeploySnapshot.sol";

/// One contract's generated files: the rolling snapshot, the alias lib that
/// re-exports its pins and the released-suites lib emitted from its record.
struct GeneratedContract {
    /// Places the snapshot inside `src/generated/<dir>/` and names both
    /// generated libs.
    string contractName;
    /// Prefix for the constants the alias lib exports, e.g. `CONFIG_REGISTRY`.
    string constantPrefix;
    DeployCandidate candidate;
}

/// @title Build
/// @notice Generates the deterministic-deploy pins for every contract this repo
/// deploys. `run()` and `cutRelease()` are inherited from `BuildScript`.
///
/// Alias libs always point at `candidate`, so `LibConfigRegistry` and
/// `LibMigrationRegistry` resolve against what this repo currently compiles.
/// The frozen `<tag>/` directories are what
/// `RegistryDeploySuites.releasedSuites()` enumerates.
///
/// `generatedContracts()` is the only list of deploy suites, read by every hook
/// below. `parameterisedContracts()` adds only rolling snapshots: see its
/// declaration.
contract Build is BuildScript, RegistryDeploySuites {
    /// Every contract this repo generates deploy pins for.
    /// @return The generated contracts.
    function generatedContracts() internal pure returns (GeneratedContract[] memory) {
        GeneratedContract[] memory contracts = new GeneratedContract[](2);
        contracts[0] = GeneratedContract({
            contractName: "ConfigRegistry", constantPrefix: "CONFIG_REGISTRY", candidate: configRegistryCandidate()
        });
        contracts[1] = GeneratedContract({
            contractName: "MigrationRegistry",
            constantPrefix: "MIGRATION_REGISTRY",
            candidate: migrationRegistryCandidate()
        });
        return contracts;
    }

    /// @inheritdoc BuildScript
    /// @dev In declaration order. Read by the freeze, and after
    /// retiredContractNames() by releasedContractNames().
    function snapshotContractNames() internal pure override returns (string[] memory) {
        GeneratedContract[] memory contracts = generatedContracts();
        string[] memory names = new string[](contracts.length);
        for (uint256 i = 0; i < contracts.length; i++) {
            names[i] = contracts[i].contractName;
        }
        return names;
    }

    /// @inheritdoc BuildScript
    /// @dev The deploy suites, then each parameterised contract's snapshot under
    /// the name `regenerateSnapshots` writes it as: the artifact's contract name.
    function releaseRecordNames() internal pure override returns (string[] memory) {
        string[] memory suites = snapshotContractNames();
        ParameterisedContract[] memory parameterised = parameterisedContracts();
        string[] memory names = new string[](suites.length + parameterised.length);
        for (uint256 i = 0; i < suites.length; i++) {
            names[i] = suites[i];
        }
        for (uint256 i = 0; i < parameterised.length; i++) {
            names[suites.length + i] = parameterisedContractName(parameterised[i]);
        }
        return names;
    }

    /// The directory every generated lib is written into.
    ///
    /// Overridable for the reason `BuildScript.recordRoot` is: a hook that can
    /// only be pointed at the committed tree can only be RUN by overwriting
    /// files the rest of the suite compiles and reads, and forge runs test
    /// contracts in parallel. Only the per-contract libs and the aggregate go
    /// here — `regenerateSnapshots` has no equivalent, because `LibFs` confines
    /// every snapshot it writes to `src/generated/`.
    /// @return The lib directory.
    function libDir() internal view virtual returns (string memory) {
        return LibRainDeploySnapshot.LIB_DIR;
    }

    /// @inheritdoc BuildScript
    /// @dev Every alias lib, every released-suites lib and the aggregate over
    /// them.
    function regenerateLibs() internal override {
        GeneratedContract[] memory contracts = generatedContracts();
        string memory dir = libDir();
        for (uint256 i = 0; i < contracts.length; i++) {
            LibRainDeploySnapshot.writeAliasLib(
                vm, dir, contracts[i].contractName, contracts[i].constantPrefix, LibRainDeploySnapshot.CANDIDATE
            );
            LibRainDeploySnapshot.writeReleasedSuitesLib(
                vm, dir, recordRoot(), contracts[i].contractName, contracts[i].candidate.snapshot
            );
        }
        LibRainDeploySnapshot.writeReleasedSuitesAggregate(vm, dir, releasedContractNames());
    }

    /// Contracts this repo no longer builds whose frozen releases stay
    /// declared. Their released-suites libs are generated from a record that
    /// can no longer grow, so they are never rewritten, and the artifact paths
    /// they declare name sources this repo no longer has: a frozen release is
    /// checked against its recorded bytecode, and its source is verified from
    /// the tag it was cut at.
    /// @return The retired contract names.
    function retiredContractNames() internal pure returns (string[] memory) {
        string[] memory names = new string[](1);
        names[0] = "AddressRegistry";
        return names;
    }

    /// Every contract with a released-suites lib: the retired ones first, in
    /// the order they were released, then the ones this repo builds.
    /// @return The contract names.
    function releasedContractNames() internal pure returns (string[] memory) {
        string[] memory retired = retiredContractNames();
        string[] memory current = snapshotContractNames();
        string[] memory names = new string[](retired.length + current.length);
        for (uint256 i = 0; i < retired.length; i++) {
            names[i] = retired[i];
        }
        for (uint256 i = 0; i < current.length; i++) {
            names[retired.length + i] = current[i];
        }
        return names;
    }

    /// @inheritdoc BuildScript
    function regenerateSnapshots() internal override {
        GeneratedContract[] memory contracts = generatedContracts();
        for (uint256 i = 0; i < contracts.length; i++) {
            LibRainDeploySnapshot.writeSnapshot(
                vm,
                recordRoot(),
                LibRainDeploySnapshot.CANDIDATE,
                contracts[i].contractName,
                vm.getCode(contracts[i].candidate.snapshot.artifactPath),
                contracts[i].candidate.snapshot.dependencies
            );
        }

        ParameterisedContract[] memory parameterised = parameterisedContracts();
        for (uint256 i = 0; i < parameterised.length; i++) {
            LibRainDeploySnapshot.writeParameterisedSnapshot(
                vm,
                recordRoot(),
                LibRainDeploySnapshot.CANDIDATE,
                parameterisedContractName(parameterised[i]),
                parameterised[i].spdxLicenseIdentifier,
                parameterised[i].copyrightText,
                vm.getCode(parameterised[i].artifactPath),
                parameterised[i].referenceConstructorArgs
            );
        }
    }
}
