// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

import {
    DependencyCycle,
    DeployCandidate,
    DeployDeclaration,
    DeployMechanismHandler,
    DeploySuite,
    DuplicateDeploySuite,
    DuplicateMechanism,
    ExternalDeployment,
    InvalidDeploySuiteKey,
    MechanismUnclaimed,
    NoDeployCandidates,
    UnknownDependency,
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
            h.legacyRecordId,
            h.checkNetworks
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
    /// `UnqualifiedCandidateArtifactPath` are raised. `allSuites` goes through it, and so does
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
                    networks: new string[](0),
                    describedByMeta: ""
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

    /// Refuses `InvalidDeploySuiteKey` for a key outside the registry's alphabet.
    function checkSuiteKey(uint256 index, string memory suite) internal pure {
        bytes memory key = bytes(suite);
        // Where the tag starts, and zero until an `@` is seen. Zero is not a
        // position a tag can start at, because an `@` opening the key leaves
        // the name half empty and is refused below.
        uint256 tagStart = 0;

        for (uint256 i = 0; i < key.length; i++) {
            bytes1 char = key[i];
            if (char == "@") {
                if (i == 0 || tagStart != 0) {
                    revert InvalidDeploySuiteKey(index, suite);
                }
                tagStart = i + 1;
            } else {
                bool nameAlphabet = (char >= "a" && char <= "z") || char == "-";
                bool tagAlphabet = (char >= "0" && char <= "9") || char == "_";
                if (!(nameAlphabet || (tagStart != 0 && tagAlphabet))) {
                    revert InvalidDeploySuiteKey(index, suite);
                }
            }
        }

        // The empty key and a trailing at sign: the loop only refuses bytes that are there.
        if (tagStart == key.length) {
            revert InvalidDeploySuiteKey(index, suite);
        }
    }

    /// The released suites then a copy of each candidate snapshot, refusing an invalid or repeated key.
    function allSuites(DeployDeclaration memory d) internal pure returns (DeploySuite[] memory) {
        checkCandidates(d);
        DeploySuite[] memory suites = releasedThenCandidates(d);

        for (uint256 i = 0; i < suites.length; i++) {
            checkSuiteKey(i, suites[i].suite);
            for (uint256 j = i + 1; j < suites.length; j++) {
                if (keccak256(bytes(suites[i].suite)) == keccak256(bytes(suites[j].suite))) {
                    revert DuplicateDeploySuite(suites[i].suite);
                }
            }
        }

        return suites;
    }

    /// The released suites then a copy of each candidate snapshot, unchecked.
    function releasedThenCandidates(DeployDeclaration memory d) private pure returns (DeploySuite[] memory) {
        DeploySuite[] memory released = d.released;
        DeployCandidate[] memory candidates = d.candidates;
        DeploySuite[] memory suites = new DeploySuite[](released.length + candidates.length);
        for (uint256 i = 0; i < released.length; i++) {
            suites[i] = released[i];
        }
        for (uint256 i = 0; i < candidates.length; i++) {
            suites[released.length + i] = abi.decode(abi.encode(candidates[i].snapshot), (DeploySuite));
        }
        return suites;
    }

    /// @param suite The suite.
    /// @return The address its mechanism records for it on each of its `networks`, in order.
    function recordedAddresses(DeployDeclaration memory d, DeploySuite memory suite)
        internal
        view
        returns (address[] memory)
    {
        uint256[] memory chainIds = LibRainDeploy.networkChainIds(LibRainDeploy.declaredNetworkConfigs(suite.networks));
        DeployMechanismHandler memory mechanism = mechanismOf(d, suite);
        address[] memory addresses = new address[](chainIds.length);
        for (uint256 i = 0; i < chainIds.length; i++) {
            addresses[i] = mechanism.recordedAddress(d, suite, chainIds[i]);
        }
        return addresses;
    }

    /// @param addresses The addresses.
    /// @param needle The address.
    /// @return Whether `addresses` holds `needle`.
    function holds(address[] memory addresses, address needle) internal pure returns (bool) {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == needle) {
                return true;
            }
        }
        return false;
    }

    /// The indexes of every suite recording `dependency` on one of its networks and of every external deployment at
    /// it, refusing `UnknownDependency` naming `declaring` where there is neither.
    /// @param recorded Each suite's `recordedAddresses`.
    function resolveDependency(
        address[][] memory recorded,
        ExternalDeployment[] memory externals,
        string memory declaring,
        address dependency
    ) internal pure returns (uint256[] memory, uint256[] memory) {
        uint256[] memory suiteIndexes = new uint256[](recorded.length);
        uint256 suiteCount = 0;
        for (uint256 i = 0; i < recorded.length; i++) {
            if (holds(recorded[i], dependency)) {
                suiteIndexes[suiteCount++] = i;
            }
        }
        uint256[] memory externalIndexes = new uint256[](externals.length);
        uint256 externalCount = 0;
        for (uint256 i = 0; i < externals.length; i++) {
            if (externals[i].deployedAddress == dependency) {
                externalIndexes[externalCount++] = i;
            }
        }
        if (suiteCount + externalCount == 0) {
            revert UnknownDependency(declaring, dependency);
        }
        assembly ("memory-safe") {
            mstore(suiteIndexes, suiteCount)
            mstore(externalIndexes, externalCount)
        }
        return (suiteIndexes, externalIndexes);
    }

    /// `suite`'s dependencies then every suite dependency's own, transitively and first entry winning per address,
    /// refusing `DependencyCycle` where they reach one of `own`.
    /// @param own Every address `suite` occupies on the networks it is deployed to.
    function dependencyClosure(DeployDeclaration memory d, DeploySuite memory suite, address[] memory own)
        internal
        view
        returns (DeployDependency[] memory)
    {
        if (suite.dependencies.length == 0) {
            return new DeployDependency[](0);
        }
        DeploySuite[] memory suites = releasedThenCandidates(d);
        ExternalDeployment[] memory externals = d.externalDeployments;
        address[][] memory recorded;
        uint256 bound = suite.dependencies.length;
        for (uint256 i = 0; i < suites.length; i++) {
            bound += suites[i].dependencies.length;
        }
        DeployDependency[] memory closure = new DeployDependency[](bound);
        string[] memory declarers = new string[](bound);
        uint256 count = appendNew(closure, declarers, 0, suite.dependencies, suite.suite);
        for (uint256 i = 0; i < count; i++) {
            if (holds(own, closure[i].deployedAddress)) {
                revert DependencyCycle(suite.suite);
            }
            if (i == 0) {
                recorded = recordedAddressesOfEach(d, suites);
            }
            (uint256[] memory suiteIndexes,) =
                resolveDependency(recorded, externals, declarers[i], closure[i].deployedAddress);
            for (uint256 j = 0; j < suiteIndexes.length; j++) {
                DeploySuite memory reached = suites[suiteIndexes[j]];
                count = appendNew(closure, declarers, count, reached.dependencies, reached.suite);
            }
        }
        assembly ("memory-safe") {
            mstore(closure, count)
            mstore(declarers, count)
        }
        return closure;
    }

    function recordedAddressesOfEach(DeployDeclaration memory d, DeploySuite[] memory suites)
        private
        view
        returns (address[][] memory)
    {
        address[][] memory recorded = new address[][](suites.length);
        for (uint256 i = 0; i < suites.length; i++) {
            recorded[i] = recordedAddresses(d, suites[i]);
        }
        return recorded;
    }

    function appendNew(
        DeployDependency[] memory closure,
        string[] memory declarers,
        uint256 count,
        DeployDependency[] memory deps,
        string memory declarer
    ) private pure returns (uint256) {
        for (uint256 i = 0; i < deps.length; i++) {
            uint256 j = 0;
            while (j < count && closure[j].deployedAddress != deps[i].deployedAddress) {
                j++;
            }
            if (j == count) {
                closure[count] = deps[i];
                declarers[count] = declarer;
                count++;
            }
        }
        return count;
    }

    /// Etches each dependency in `suite`'s dependency closure at its address.
    /// @param own Every address `suite` occupies on the networks it is deployed to.
    function etchDependencyClosure(DeployDeclaration memory d, Vm vm, DeploySuite memory suite, address[] memory own)
        internal
    {
        DeployDependency[] memory closure = dependencyClosure(d, suite, own);
        for (uint256 i = 0; i < closure.length; i++) {
            vm.etch(closure[i].deployedAddress, closure[i].runtimeCode);
        }
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
