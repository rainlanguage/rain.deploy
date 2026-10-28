// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {RainDeployVerifySnapshotBase} from "../../../src/abstract/RainDeployVerifySnapshotBase.sol";
import {DeployDeclaration} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {TwoMechanismDeploySuites} from "../../abstract/TwoMechanismDeploySuites.sol";
import {LibMockCreate2Mechanism} from "../../lib/LibMockCreate2Mechanism.sol";
import {LibMockSaltMechanism} from "../../lib/LibMockSaltMechanism.sol";

/// @title RainDeployVerifyTwoMechanismsTest
/// @notice The chain and snapshot groups run over a declaration of two non-Zoltu mechanisms with no override. The
/// frozen-record walk is left out: it reads this repo's own `src/generated`, which this declaration does not release.
contract RainDeployVerifyTwoMechanismsTest is
    TwoMechanismDeploySuites,
    RainDeployVerifyChain,
    RainDeployVerifySnapshotBase
{
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibMockSaltMechanism.extend(d);
        LibMockCreate2Mechanism.extend(d);
        addTwoMechanismCandidates(d);
        return d;
    }
}
