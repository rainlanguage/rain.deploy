// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployDeclaration,
    DeployMechanismHandler,
    DeploySuite,
    DuplicateMechanism
} from "../abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "./LibRainDeploy.sol";

/// @title LibRainDeployDeclaration
/// @notice The core layer of a declaration, and what every layer composes with.
library LibRainDeployDeclaration {
    /// Sets `d.networks` to every one of Rain's networks when it names none, then gives every suite in `d` naming no
    /// networks `d.networks`.
    /// @param d The declaration, mutated.
    function extend(DeployDeclaration memory d) internal pure {
        if (d.networks.length == 0) {
            d.networks = LibRainDeploy.supportedNetworks();
        }
        for (uint256 i = 0; i < d.released.length; i++) {
            fillNetworks(d.released[i], d.networks);
        }
        for (uint256 i = 0; i < d.candidates.length; i++) {
            fillNetworks(d.candidates[i].snapshot, d.networks);
        }
    }

    function fillNetworks(DeploySuite memory suite, string[] memory networks) private pure {
        if (suite.networks.length == 0) {
            string[] memory copied = new string[](networks.length);
            for (uint256 i = 0; i < networks.length; i++) {
                copied[i] = networks[i];
            }
            suite.networks = copied;
        }
    }

    /// Appends `handler` to `d.mechanisms`, refusing `DuplicateMechanism` for an id already there.
    /// @param d The declaration, mutated.
    /// @param handler The mechanism.
    function addMechanism(DeployDeclaration memory d, DeployMechanismHandler memory handler) internal pure {
        DeployMechanismHandler[] memory mechanisms = new DeployMechanismHandler[](d.mechanisms.length + 1);
        for (uint256 i = 0; i < d.mechanisms.length; i++) {
            if (d.mechanisms[i].id == handler.id) {
                revert DuplicateMechanism(handler.id);
            }
            mechanisms[i] = d.mechanisms[i];
        }
        mechanisms[d.mechanisms.length] = handler;
        d.mechanisms = mechanisms;
    }
}
