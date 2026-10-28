// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {RainDeployDeclarationChecks} from "./RainDeployDeclarationChecks.sol";

/// @title RainDeployVerifyDeclaration
/// @notice Runs every `RainDeployDeclarationChecks` check as a test.
abstract contract RainDeployVerifyDeclaration is RainDeployDeclarationChecks {
    function testDispatchChoicesAreTheSuiteKeys() external view {
        checkDispatchChoicesAreTheSuiteKeys(declaration());
    }

    function testCandidateArtifactPathsAreSource() external view {
        checkCandidateArtifactPathsAreSource(declaration());
    }

    function testDependenciesAreNonZeroAndUnique() external view {
        checkDependenciesAreNonZeroAndUnique(declaration());
    }

    function testDependenciesAreTheEmbeddedDeployments() external view {
        checkDependenciesAreTheEmbeddedDeployments(declaration());
    }

    function testDependencyRuntimeCodeIsKnown() external view {
        checkDependencyRuntimeCodeIsKnown(declaration());
    }

    function testCandidateRuntimeCodeFitsEip170() external view {
        checkCandidateRuntimeCodeFitsEip170(declaration());
    }
}
