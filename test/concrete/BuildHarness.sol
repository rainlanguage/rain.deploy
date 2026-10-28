// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Build} from "../../script/Build.sol";
import {BuildScript, GeneratedContract, RetiredContract} from "../../src/abstract/BuildScript.sol";
import {DeployDeclaration, DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ParameterisedContract} from "../../src/abstract/RegistryDeploySuites.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";

/// Thrown when a harness left pointed at `Build`'s own lib directory is asked
/// to run the lib half of a build. That write lands on the committed libs the
/// rest of the suite compiles and reads, which forge runs in parallel with it.
error BuildHarnessWouldWriteTheCommittedLibs();

/// @title BuildHarness
/// @notice An external seam onto `Build`'s declarations, and onto
/// `regenerateLibs()` pointed somewhere nothing compiles, so a test can RUN it.
contract BuildHarness is Build {
    /// The lib directory the hooks write into. Empty defers to `Build`'s own,
    /// which is what makes the default assertable and the write refusable.
    string internal sLibDir;

    /// @param libDirectory The directory `regenerateLibs` writes into, or empty
    /// for `Build`'s own.
    constructor(string memory libDirectory) {
        sLibDir = libDirectory;
    }

    /// @inheritdoc BuildScript
    function libDir() internal view override returns (string memory) {
        return bytes(sLibDir).length > 0 ? sLibDir : super.libDir();
    }

    function externalLibDir() external view returns (string memory) {
        return libDir();
    }

    /// Runs the lib half of a build, into the fixture directory this harness
    /// was handed. The directory has to exist already, as it does for every
    /// writer `regenerateLibs` calls.
    function externalRegenerateLibs() external {
        if (bytes(sLibDir).length == 0) {
            revert BuildHarnessWouldWriteTheCommittedLibs();
        }
        DeployDeclaration memory d = declaration();
        regenerateLibs(d, checkedGeneratedContracts(d));
    }

    function externalGeneratedContracts() external view returns (GeneratedContract[] memory) {
        return checkedGeneratedContracts(declaration());
    }

    function externalSnapshotContractNames() external view returns (string[] memory) {
        return snapshotContractNames(checkedGeneratedContracts(declaration()));
    }

    function externalRetiredContracts() external pure returns (RetiredContract[] memory) {
        return retiredContracts();
    }

    function externalGeneratedPaths() external view returns (string[] memory) {
        DeployDeclaration memory d = declaration();
        return generatedPaths(d, checkedGeneratedContracts(d));
    }

    /// The rolling snapshot name of every parameterised contract, which the
    /// regeneration writes beside the candidates' and a release does not
    /// freeze.
    /// @return The parameterised contract names.
    function externalParameterisedContractNames() external pure returns (string[] memory) {
        ParameterisedContract[] memory parameterised = parameterisedContracts();
        string[] memory names = new string[](parameterised.length);
        for (uint256 i = 0; i < parameterised.length; i++) {
            names[i] = parameterisedContractName(parameterised[i]);
        }
        return names;
    }

    /// `LibRainDeploySnapshot.releasedLibraryBlock` under this build's declaration.
    /// @param libraryName The library name.
    /// @param contractName The contract the lib is for.
    /// @param paths The record paths.
    /// @param template The template the entries are emitted from.
    /// @return The library block.
    function externalReleasedLibraryBlock(
        string memory libraryName,
        string memory contractName,
        string[] memory paths,
        DeploySuite memory template
    ) external view returns (string memory) {
        return LibRainDeploySnapshot.releasedLibraryBlock(vm, libraryName, contractName, paths, template, declaration());
    }

    /// `LibRainDeploySnapshot.releasedImportBlock` under this build's declaration.
    /// @param paths The record paths.
    /// @return The import block.
    function externalReleasedImportBlock(string[] memory paths) external view returns (string memory) {
        return LibRainDeploySnapshot.releasedImportBlock(vm, paths, declaration());
    }
}
