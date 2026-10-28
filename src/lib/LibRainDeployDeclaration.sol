// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeployDeclaration,
    DeployMechanismHandler,
    DeploySuite
} from "../abstract/RainDeploySuitesBase.sol";
import {ChainBeacon} from "./LibRainDeployBeacon.sol";
import {LibRainDeploy} from "./LibRainDeploy.sol";
import {LibRainDeploySnapshot} from "./LibRainDeploySnapshot.sol";
import {LibRainDeployZoltuMechanism} from "./LibRainDeployZoltuMechanism.sol";

/// @title LibRainDeployDeclaration
/// @notice The declaration a repo starts from.
library LibRainDeployDeclaration {
    /// @return Every one of Rain's networks, Zoltu its one mechanism, no suites, no beacons, and the repo's own
    /// record root.
    function zoltu() internal pure returns (DeployDeclaration memory) {
        DeployMechanismHandler[] memory mechanisms = new DeployMechanismHandler[](1);
        mechanisms[0] = LibRainDeployZoltuMechanism.handler();
        return DeployDeclaration({
            released: new DeploySuite[](0),
            candidates: new DeployCandidate[](0),
            mechanisms: mechanisms,
            networks: LibRainDeploy.supportedNetworks(),
            beacons: new ChainBeacon[](0),
            extendedNetworksRoot: LibRainDeploySnapshot.LIB_FS_ROOT
        });
    }
}
