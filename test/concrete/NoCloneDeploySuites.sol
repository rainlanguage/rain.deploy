// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployCloneSuitesBase} from "../../src/abstract/RainDeployCloneSuitesBase.sol";
import {CloneDeploy} from "../../src/lib/LibRainDeployClone.sol";
import {ExternalCloneDeploySuites} from "../abstract/ExternalCloneDeploySuites.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";

/// @title NoCloneDeploySuites
/// A repo that inherited the clone machinery and declared nothing for it to
/// deploy.
///
/// The empty list has to be refused where the CONSUMER wrote it. Every loop over
/// an empty list passes, so without the guard this fixture's declaration would
/// sail through the candidate derivation, the source anchor and the chain matrix
/// while asserting nothing about anything — and the refusal it would eventually
/// get is `NoDeployCandidates`, which names the DERIVED list and sends a consumer
/// looking at `candidateSuites()`, a function a clone repo does not write.
contract NoCloneDeploySuites is ExternalCloneDeploySuites, ExternalDeploySuites {
    /// @inheritdoc RainDeployCloneSuitesBase
    function cloneDeploys() internal pure override returns (CloneDeploy[] memory) {
        return new CloneDeploy[](0);
    }
}
