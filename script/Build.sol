// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript, GeneratedContract, RetiredContract} from "../src/abstract/BuildScript.sol";
import {DeployDeclaration, DeployDependency, DeploySuite} from "../src/abstract/RainDeploySuitesBase.sol";
import {ParameterisedContract, RegistryDeploySuites} from "../src/abstract/RegistryDeploySuites.sol";
import {LibRainDeploySnapshot} from "../src/lib/LibRainDeploySnapshot.sol";

/// @title Build
/// @notice Generates the deterministic-deploy pins for every contract this repo
/// deploys. `run()`, `cutRelease()` and every generated lib are inherited from
/// `BuildScript`.
///
/// Alias libs always point at `candidate`, so `LibConfigRegistry` and
/// `LibMigrationRegistry` resolve against what this repo currently compiles.
/// The frozen `<tag>/` directories are what
/// `RegistryDeploySuites.releasedSuites()` enumerates.
///
/// `parameterisedContracts()` adds only rolling snapshots: see its
/// declaration.
contract Build is BuildScript, RegistryDeploySuites {
    /// @inheritdoc BuildScript
    function generatedContracts(DeployDeclaration memory d)
        internal
        pure
        override
        returns (GeneratedContract[] memory)
    {
        GeneratedContract[] memory contracts = new GeneratedContract[](2);
        contracts[0] = GeneratedContract({
            contractName: "ConfigRegistry",
            constantPrefix: "CONFIG_REGISTRY",
            candidate: declaredCandidate(d, configRegistryCandidate().snapshot.suite)
        });
        contracts[1] = GeneratedContract({
            contractName: "MigrationRegistry",
            constantPrefix: "MIGRATION_REGISTRY",
            candidate: declaredCandidate(d, migrationRegistryCandidate().snapshot.suite)
        });
        return contracts;
    }

    /// @inheritdoc BuildScript
    /// @dev The artifact path names a source this repo no longer has: a frozen
    /// release is checked against its recorded bytecode, and its source is
    /// verified from the tag it was cut at.
    function retiredContracts() internal pure override returns (RetiredContract[] memory) {
        RetiredContract[] memory retired = new RetiredContract[](1);
        retired[0] = RetiredContract({
            contractName: "AddressRegistry",
            template: DeploySuite({
                networks: new string[](0),
                suite: ADDRESS_REGISTRY_SUITE,
                creationCode: "",
                storedDeployedAddress: address(0),
                storedBytecodeHash: bytes32(0),
                storedRuntimeCode: "",
                artifactPath: "src/concrete/AddressRegistry.sol:AddressRegistry",
                dependencies: new DeployDependency[](0),
                mechanismData: ""
            })
        });
        return retired;
    }

    /// @inheritdoc BuildScript
    /// @dev The deploy suites, then each parameterised contract's snapshot under
    /// the name `regenerateSnapshots` writes it as: the artifact's contract name.
    function releaseRecordNames(DeployDeclaration memory, GeneratedContract[] memory generated)
        internal
        pure
        override
        returns (string[] memory)
    {
        string[] memory suites = snapshotContractNames(generated);
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
    function regenerateSnapshots() internal override {
        GeneratedContract[] memory contracts = checkedGeneratedContracts(declaration());
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
