// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeployDeclaration,
    DeployMechanismHandler,
    DeploySuite,
    DuplicateMechanism,
    MechanismUnclaimed,
    NoDeployCandidates,
    UnqualifiedCandidateArtifactPath
} from "../abstract/RainDeploySuitesBase.sol";
import {DeployDependency, LibRainDeploy} from "./LibRainDeploy.sol";

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
            h.checkDeclaration,
            h.checkNetwork,
            h.logVerification,
            h.writeSuiteSnapshot,
            h.releasedMechanismData,
            h.releasedImport,
            h.legacyRecordId
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

    /// The name half of a suite key.
    /// @param suite The suite key.
    /// @return The name half.
    function suiteKeyName(string memory suite) internal pure returns (string memory) {
        bytes memory key = bytes(suite);
        uint256 length = key.length;
        for (uint256 i = 0; i < key.length; i++) {
            if (key[i] == "@") {
                length = i;
                break;
            }
        }
        bytes memory name = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            name[i] = key[i];
        }
        return string(name);
    }

    /// The declared candidates, refusing an empty list and an `artifactPath`
    /// that is not `<path>:<Name>`.
    ///
    /// The ONE place `NoDeployCandidates` and
    /// `UnqualifiedCandidateArtifactPath` are raised, and the only way anything
    /// reads the candidates. `allSuites` goes through it, and so does
    /// `checkCandidatesAnchoredToSource` — which matters, because the source
    /// anchor loops over the candidates and a loop over an empty list passes.
    /// Guarding each reader separately would be two spellings of one rule, and
    /// the reader that got the second spelling wrong is the one that silently
    /// stops asserting.
    function checkCandidates(DeployDeclaration memory d) internal pure {
        DeployCandidate[] memory candidates = d.candidates;
        if (candidates.length == 0) {
            revert NoDeployCandidates();
        }
        for (uint256 i = 0; i < candidates.length; i++) {
            bytes memory path = bytes(candidates[i].snapshot.artifactPath);
            // `.sol:` and not merely a colon, because forge reads `Name:0.8.25`
            // as a contract name plus a compiler version — a colon that
            // qualifies nothing, and a path that still resolves to whichever
            // same-named artifact comes first. Measured: `Dup2:0.8.25` resolves
            // to the same bytes as `File.sol:Dup2` with two `Dup2` compiled.
            bool qualified = false;
            for (uint256 j = 0; j + 5 <= path.length; j++) {
                if (
                    path[j] == "." && path[j + 1] == "s" && path[j + 2] == "o" && path[j + 3] == "l"
                        && path[j + 4] == ":"
                ) {
                    qualified = true;
                    break;
                }
            }
            if (!qualified) {
                revert UnqualifiedCandidateArtifactPath(i, candidates[i].snapshot.artifactPath);
            }
        }
    }

    /// The candidate a suite key names.
    /// @param d The declaration.
    /// @param suite The suite key.
    /// @return The snapshot of the candidate whose key is `suite`'s name half, freshly read from the declaration.
    /// @return Whether there is one.
    function candidateOf(DeployDeclaration memory d, string memory suite)
        internal
        pure
        returns (DeploySuite memory, bool)
    {
        bytes32 name = keccak256(bytes(suiteKeyName(suite)));
        checkCandidates(d);
        DeployCandidate[] memory candidates = d.candidates;
        uint256 i = 0;
        while (i < candidates.length && keccak256(bytes(candidates[i].snapshot.suite)) != name) {
            i++;
        }
        bool found = i < candidates.length;
        if (!found) {
            return (
                DeploySuite({
                    suite: "",
                    creationCode: "",
                    storedDeployedAddress: address(0),
                    storedBytecodeHash: bytes32(0),
                    storedRuntimeCode: "",
                    artifactPath: "",
                    dependencies: new DeployDependency[](0),
                    mechanismData: "",
                    networks: new string[](0)
                }),
                found
            );
        }
        return (abi.decode(abi.encode(candidates[i].snapshot), (DeploySuite)), found);
    }

    /// The mechanism id a suite's `mechanismData` declares: its first word. Refuses `MechanismUnclaimed` for data
    /// shorter than a word.
    /// @param suite The suite.
    /// @return The id.
    function mechanismIdOf(DeploySuite memory suite) internal pure returns (bytes32) {
        bytes memory data = suite.mechanismData;
        if (data.length < 0x20) {
            revert MechanismUnclaimed(suite.suite);
        }
        bytes32 id;
        assembly ("memory-safe") {
            id := mload(add(data, 0x20))
        }
        return id;
    }

    /// @param d The declaration.
    /// @param suite The suite.
    /// @return The handler of the mechanism its data declares.
    function mechanismOf(DeployDeclaration memory d, DeploySuite memory suite)
        internal
        pure
        returns (DeployMechanismHandler memory)
    {
        return mechanismById(d, mechanismIdOf(suite), suite.suite);
    }

    function addUnrecordedNetworks(
        DeployDeclaration memory d,
        DeploySuite memory suite,
        DeploySuite memory candidate,
        uint256[] memory chainIds
    ) internal view {
        mechanismOf(d, suite).addUnrecordedNetworks(d, suite, candidate, chainIds);
    }

    /// Adds to `suite` the networks among `chainIds` its candidate takes it to, the candidate being a copy of `suite`
    /// when its key names none.
    /// @param d The declaration.
    /// @param suite The suite, mutated.
    /// @param chainIds The chain ids in play.
    function addCandidateNetworks(DeployDeclaration memory d, DeploySuite memory suite, uint256[] memory chainIds)
        internal
        view
    {
        (DeploySuite memory candidate, bool found) = candidateOf(d, suite.suite);
        if (!found) {
            candidate = abi.decode(abi.encode(suite), (DeploySuite));
        }
        addUnrecordedNetworks(d, suite, candidate, chainIds);
    }

    /// @param suites The suites to search.
    /// @param requested The key to select.
    /// @return The index in `suites` of the suite `requested` selects, `suites.length` if none.
    function suiteIndex(DeploySuite[] memory suites, string memory requested) internal pure returns (uint256) {
        bytes32 requestedHash = keccak256(bytes(requested));
        for (uint256 i = 0; i < suites.length; i++) {
            if (keccak256(bytes(suites[i].suite)) == requestedHash) {
                return i;
            }
        }
        return suites.length;
    }
}
