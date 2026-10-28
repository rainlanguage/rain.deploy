// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript} from "../src/abstract/BuildScript.sol";
import {DeployCandidate, DeployDependency, DeploySuite} from "../src/abstract/RainDeploySuitesBase.sol";
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

/// A contract this repo no longer builds, whose released-suites lib is still
/// generated from its frozen record.
struct RetiredContract {
    /// Names the record files and the released-suites lib.
    string contractName;
    /// The suite key every released entry is emitted under.
    string suite;
    /// The artifact path every released entry is emitted with.
    string artifactPath;
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

    /// @inheritdoc BuildScript
    /// @dev Every alias lib, every released-suites lib, retired ones included,
    /// and the aggregate over them.
    function regenerateLibs() internal override {
        GeneratedContract[] memory contracts = generatedContracts();
        string memory dir = libDir();
        RetiredContract[] memory retired = retiredContracts();
        for (uint256 i = 0; i < retired.length; i++) {
            LibRainDeploySnapshot.writeReleasedSuitesLib(
                vm, dir, recordRoot(), retired[i].contractName, retiredTemplate(retired[i]), releasedMechanismData
            );
        }
        for (uint256 i = 0; i < contracts.length; i++) {
            LibRainDeploySnapshot.writeAliasLib(
                vm, dir, contracts[i].contractName, contracts[i].constantPrefix, LibRainDeploySnapshot.CANDIDATE
            );
            LibRainDeploySnapshot.writeReleasedSuitesLib(
                vm, dir, recordRoot(), contracts[i].contractName, contracts[i].candidate.snapshot, releasedMechanismData
            );
        }
        LibRainDeploySnapshot.writeReleasedSuitesAggregate(vm, dir, releasedContractNames());
    }

    /// @inheritdoc BuildScript
    /// @dev Each retired contract's released-suites lib, then each alias lib.
    function buildGeneratedPaths() internal view override returns (string[] memory) {
        RetiredContract[] memory retired = retiredContracts();
        GeneratedContract[] memory contracts = generatedContracts();
        string memory dir = libDir();
        string[] memory paths = new string[](retired.length + contracts.length);
        for (uint256 i = 0; i < retired.length; i++) {
            paths[i] = LibRainDeploySnapshot.pathForLib(
                dir, LibRainDeploySnapshot.releasedLibraryName(retired[i].contractName)
            );
        }
        for (uint256 i = 0; i < contracts.length; i++) {
            paths[retired.length + i] = LibRainDeploySnapshot.pathForLib(
                dir, LibRainDeploySnapshot.aliasLibraryName(contracts[i].contractName)
            );
        }
        return paths;
    }

    /// Contracts this repo no longer builds whose frozen releases stay
    /// declared, in the order they were released. Their record can no longer
    /// grow, so regenerating their released-suites libs is a no-op that keeps
    /// them in step with the emitter. The artifact paths name sources this repo
    /// no longer has: a frozen release is checked against its recorded
    /// bytecode, and its source is verified from the tag it was cut at.
    /// @return The retired contracts.
    function retiredContracts() internal pure returns (RetiredContract[] memory) {
        RetiredContract[] memory retired = new RetiredContract[](1);
        retired[0] = RetiredContract({
            contractName: "AddressRegistry",
            suite: ADDRESS_REGISTRY_SUITE,
            artifactPath: "src/concrete/AddressRegistry.sol:AddressRegistry"
        });
        return retired;
    }

    /// The template a retired contract's released entries take their key and
    /// artifact path from. Every other field is read from the record.
    /// @param retired The retired contract.
    /// @return The template.
    function retiredTemplate(RetiredContract memory retired) internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: retired.suite,
            creationCode: "",
            storedDeployedAddress: address(0),
            storedBytecodeHash: bytes32(0),
            storedRuntimeCode: "",
            artifactPath: retired.artifactPath,
            dependencies: new DeployDependency[](0),
            mechanismData: ""
        });
    }

    /// The names of `retiredContracts()`, in order.
    /// @return The retired contract names.
    function retiredContractNames() internal pure returns (string[] memory) {
        RetiredContract[] memory retired = retiredContracts();
        string[] memory names = new string[](retired.length);
        for (uint256 i = 0; i < retired.length; i++) {
            names[i] = retired[i].contractName;
        }
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
