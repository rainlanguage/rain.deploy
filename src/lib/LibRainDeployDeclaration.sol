// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeployDeclaration,
    DeployMechanismHandler,
    DeploySuite,
    DuplicateMechanism,
    MechanismUnclaimed
} from "../abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "./LibRainDeploy.sol";

/// @title LibRainDeployDeclaration
/// @notice The core layer of a declaration, and what every layer composes with.
library LibRainDeployDeclaration {
    /// The workflow `extend` declares the dispatch choices in.
    string constant DISPATCH_WORKFLOW = ".github/workflows/manual-sol-artifacts.yaml";

    /// Sets `d.networks` and `d.deployNetworks` to every one of Rain's networks and `d.dispatchWorkflow` to
    /// `DISPATCH_WORKFLOW`.
    /// @param d The declaration, mutated.
    function extend(DeployDeclaration memory d) internal pure {
        setNetworks(d, LibRainDeploy.supportedNetworks());
        d.dispatchWorkflow = DISPATCH_WORKFLOW;
    }

    /// Sets `d.networks` and `d.deployNetworks` each to its own copy of `networks`.
    /// @param d The declaration, mutated.
    /// @param networks The networks.
    function setNetworks(DeployDeclaration memory d, string[] memory networks) internal pure {
        d.networks = copy(networks);
        d.deployNetworks = copy(networks);
    }

    /// Sets `d.deployNetworks` to a copy of `networks`, leaving `d.networks`.
    /// @param d The declaration, mutated.
    /// @param networks The networks a run deploys to.
    function setDeployNetworks(DeployDeclaration memory d, string[] memory networks) internal pure {
        d.deployNetworks = copy(networks);
    }

    /// @param d The declaration.
    /// @return A copy of `d.networks`.
    function everyNetwork(DeployDeclaration memory d) internal pure returns (string[] memory) {
        return copy(d.networks);
    }

    function copy(string[] memory networks) private pure returns (string[] memory) {
        string[] memory copied = new string[](networks.length);
        for (uint256 i = 0; i < copied.length; i++) {
            copied[i] = networks[i];
        }
        return copied;
    }

    /// Appends `suites` to `d.released`, giving each naming no networks a copy of `d.networks`.
    /// @param d The declaration, mutated.
    /// @param suites The released suites, copied before that fill.
    function addReleased(DeployDeclaration memory d, DeploySuite[] memory suites) internal pure {
        DeploySuite[] memory released = new DeploySuite[](d.released.length + suites.length);
        for (uint256 i = 0; i < d.released.length; i++) {
            released[i] = d.released[i];
        }
        for (uint256 i = 0; i < suites.length; i++) {
            DeploySuite memory suite = abi.decode(abi.encode(suites[i]), (DeploySuite));
            fillNetworks(suite, d);
            released[d.released.length + i] = suite;
        }
        d.released = released;
    }

    /// Appends `candidates` to `d.candidates`, giving each snapshot naming no networks a copy of `d.networks`.
    /// @param d The declaration, mutated.
    /// @param candidates The candidates, copied before that fill.
    function addCandidates(DeployDeclaration memory d, DeployCandidate[] memory candidates) internal pure {
        DeployCandidate[] memory all = new DeployCandidate[](d.candidates.length + candidates.length);
        for (uint256 i = 0; i < d.candidates.length; i++) {
            all[i] = d.candidates[i];
        }
        for (uint256 i = 0; i < candidates.length; i++) {
            DeployCandidate memory candidate = abi.decode(abi.encode(candidates[i]), (DeployCandidate));
            fillNetworks(candidate.snapshot, d);
            all[d.candidates.length + i] = candidate;
        }
        d.candidates = all;
    }

    function fillNetworks(DeploySuite memory suite, DeployDeclaration memory d) private pure {
        if (suite.networks.length == 0) {
            suite.networks = everyNetwork(d);
        }
    }

    /// The one of `d.mechanisms` whose id is `id`, refusing `DuplicateMechanism` for a list repeating an id and
    /// `MechanismUnclaimed` for none.
    /// @param d The declaration.
    /// @param id The mechanism id.
    /// @param subject The suite key or record file `MechanismUnclaimed` names.
    /// @return A copy of its handler.
    function mechanismById(DeployDeclaration memory d, bytes32 id, string memory subject)
        internal
        pure
        returns (DeployMechanismHandler memory)
    {
        DeployMechanismHandler[] memory handlers = d.mechanisms;
        uint256 found = handlers.length;
        for (uint256 i = 0; i < handlers.length; i++) {
            for (uint256 j = 0; j < i; j++) {
                if (handlers[j].id == handlers[i].id) {
                    revert DuplicateMechanism(handlers[i].id);
                }
            }
            if (handlers[i].id == id) {
                found = i;
            }
        }
        if (found == handlers.length) {
            revert MechanismUnclaimed(subject);
        }
        return copyHandler(handlers[found]);
    }

    /// @param h The handler.
    /// @return A copy of `h`, `config` included.
    function copyHandler(DeployMechanismHandler memory h) internal pure returns (DeployMechanismHandler memory) {
        return DeployMechanismHandler(
            h.id,
            bytes.concat(h.config),
            h.deployedAddress,
            h.recordedAddress,
            h.deployStepData,
            h.deployStep,
            h.deployLocally,
            h.deployLocallyOnChain,
            h.addUnrecordedNetworks,
            h.addRecordedNetworks,
            h.checkNetworkFrozen,
            h.checkOnChain,
            h.checkBroadcastSeat,
            h.logVerification,
            h.writeSuiteSnapshot,
            h.releasedMechanismData,
            h.releasedImport
        );
    }

    /// Appends a copy of `handler` to `d.mechanisms`, refusing `DuplicateMechanism` for an id already there.
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
        mechanisms[d.mechanisms.length] = copyHandler(handler);
        d.mechanisms = mechanisms;
    }
}
