// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {BuildScript, GeneratedContract} from "../../src/abstract/BuildScript.sol";
import {DeployDeclaration} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {TwoMechanismDeploySuites} from "../abstract/TwoMechanismDeploySuites.sol";
import {LibMockCreate2Mechanism} from "../lib/LibMockCreate2Mechanism.sol";
import {LibMockSaltMechanism} from "../lib/LibMockSaltMechanism.sol";

contract TwoMechanismBuildScriptHarness is TwoMechanismDeploySuites, ExternalDeploySuites, BuildScript {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibMockSaltMechanism.extend(d);
        LibMockCreate2Mechanism.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        addTwoMechanismCandidates(d);
        return d;
    }

    function generatedContracts(DeployDeclaration memory d)
        internal
        pure
        override
        returns (GeneratedContract[] memory)
    {
        GeneratedContract[] memory generated = new GeneratedContract[](2);
        generated[0] = GeneratedContract({
            contractName: "MockDeployable",
            constantPrefix: "",
            candidate: declaredCandidate(d, create2Candidate().suite)
        });
        generated[1] = GeneratedContract({
            contractName: "MockDeployableV2", constantPrefix: "", candidate: declaredCandidate(d, saltCandidate().suite)
        });
        return generated;
    }

    function regenerateSnapshots() internal override {}
}
