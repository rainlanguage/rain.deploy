// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployCandidate, DeployDeclaration} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {TwoMechanismDeploySuites} from "../abstract/TwoMechanismDeploySuites.sol";
import {LibMockCreate2Mechanism} from "../lib/LibMockCreate2Mechanism.sol";
import {LibMockSaltMechanism} from "../lib/LibMockSaltMechanism.sol";

/// The two mock candidates declared salt first, create2 second.
contract ReversedSuitesDeploy is TwoMechanismDeploySuites, ExternalDeploySuites {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibMockSaltMechanism.extend(d);
        LibMockCreate2Mechanism.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        DeployCandidate[] memory candidates = new DeployCandidate[](2);
        candidates[0] = DeployCandidate({snapshot: saltCandidate(), unanchorableReason: ""});
        candidates[1] = DeployCandidate({snapshot: create2Candidate(), unanchorableReason: ""});
        LibRainDeployDeclaration.addCandidates(d, candidates);
        return d;
    }
}
