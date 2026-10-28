// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ExternalDeployment} from "../../../src/abstract/RainDeployDeclarationChecks.sol";
import {RainDeployVerifyDeclaration} from "../../../src/abstract/RainDeployVerifyDeclaration.sol";
import {TwoMechanismDeploySuites} from "../../abstract/TwoMechanismDeploySuites.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";

/// @title RainDeployVerifyDeclarationTwoMechanismsTest
/// @notice The declaration group runs over a declaration of two non-Zoltu mechanisms with no mechanism override.
contract RainDeployVerifyDeclarationTwoMechanismsTest is TwoMechanismDeploySuites, RainDeployVerifyDeclaration {
    function sourceCreationCode(string memory suite) internal pure override returns (bytes memory) {
        if (keccak256(bytes(suite)) == keccak256("mock-create-two")) return type(MockDeployable).creationCode;
        return type(MockDeployableV2).creationCode;
    }

    function externalDeployments() internal pure override returns (ExternalDeployment[] memory) {
        return new ExternalDeployment[](0);
    }

    function dispatchWorkflow() internal pure override returns (string memory) {
        return "test/fixture-dispatch/two-mechanisms.yaml";
    }
}
