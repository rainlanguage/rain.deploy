// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {
    DeployCandidate,
    DeployDeclaration,
    DeployDependency,
    DeploySuite,
    RainDeploySuitesBase
} from "./RainDeploySuitesBase.sol";

/// A deterministic deployment outside the repo that a suite may reach.
struct ExternalDeployment {
    address deployedAddress;
    bytes32 codeHash;
}

/// The dispatch workflow has no `suite` input with an `options` list.
/// @param workflow The workflow path.
error DispatchChoicesUnreadable(string workflow);

/// @param choice A dispatch choice that names no declared suite.
error DispatchChoiceNotDeclared(string choice);

/// @param choice A dispatch choice listed more than once.
error DispatchChoiceRepeated(string choice);

/// @param suite A declared suite the dispatch workflow does not offer.
error SuiteNotDispatchable(string suite);

/// @param suite The candidate.
/// @param artifactPath Its artifact path, which compiles to other code than its source.
error CandidateArtifactNotSource(string suite, string artifactPath);

/// @param suite The suite declaring the zero address as a dependency.
error ZeroDependency(string suite);

/// @param suite The suite.
/// @param dependency The dependency it declares more than once.
error RepeatedDependency(string suite, address dependency);

/// @param suite The suite.
/// @param reached A sibling or external deployment its code embeds but it does not declare.
error UndeclaredDependency(string suite, address reached);

/// @param suite The suite.
/// @param dependency A declared dependency its code does not embed.
error UnreachedDependency(string suite, address dependency);

/// @param suite The suite.
/// @param dependency A declared dependency that is neither a sibling nor an external deployment.
error UnknownDependency(string suite, address dependency);

/// @param suite The suite.
/// @param dependency The dependency.
/// @param declaredCodeHash The hash of the runtime code the suite declares at it.
/// @param expectedCodeHash The hash its sibling or external declaration records.
error DependencyRuntimeCodeMismatch(
    string suite, address dependency, bytes32 declaredCodeHash, bytes32 expectedCodeHash
);

/// @param suite The candidate.
/// @param length Its runtime code length.
error RuntimeCodeExceedsEip170(string suite, uint256 length);

/// @title RainDeployDeclarationChecks
/// @notice Offline checks of the declaration fields only a dispatch, a verifier
/// or a broadcast reads: suite keys against the dispatch workflow, candidate
/// artifact paths against source, and dependency lists against the addresses
/// each suite's code embeds.
abstract contract RainDeployDeclarationChecks is RainDeploySuitesBase, Test {
    uint256 constant EIP170_MAX_RUNTIME_CODE_SIZE = 0x6000;

    /// @param suite An anchored candidate's key.
    /// @return The creation code of the contract the key names, from its type.
    function sourceCreationCode(string memory suite) internal view virtual returns (bytes memory);

    /// @return Every deterministic deployment outside this repo that a suite may embed.
    function externalDeployments() internal view virtual returns (ExternalDeployment[] memory);

    /// @return The workflow whose `suite` input lists the dispatch choices.
    function dispatchWorkflow() internal view virtual returns (string memory) {
        return ".github/workflows/manual-sol-artifacts.yaml";
    }

    /// @param line A line of YAML.
    /// @return Its count of leading spaces.
    function indentation(string memory line) internal pure returns (uint256) {
        bytes memory raw = bytes(line);
        uint256 i = 0;
        while (i < raw.length && raw[i] == " ") {
            i++;
        }
        return i;
    }

    /// @param line A line of YAML.
    /// @return Whether it is blank or a comment.
    function isInert(string memory line) internal pure returns (bool) {
        bytes memory trimmed = bytes(vm.trim(line));
        return trimmed.length == 0 || trimmed[0] == "#";
    }

    /// @return The `options` of the dispatch workflow's `suite` input.
    function dispatchChoices() internal view returns (string[] memory) {
        string memory workflow = dispatchWorkflow();
        string[] memory lines = vm.split(vm.readFile(workflow), "\n");
        uint256 i = 0;
        while (i < lines.length && keccak256(bytes(vm.trim(lines[i]))) != keccak256("suite:")) {
            i++;
        }
        if (i == lines.length) {
            revert DispatchChoicesUnreadable(workflow);
        }
        uint256 inputIndentation = indentation(lines[i]);
        i++;
        while (i < lines.length && keccak256(bytes(vm.trim(lines[i]))) != keccak256("options:")) {
            if (!isInert(lines[i]) && indentation(lines[i]) <= inputIndentation) {
                revert DispatchChoicesUnreadable(workflow);
            }
            i++;
        }
        if (i == lines.length) {
            revert DispatchChoicesUnreadable(workflow);
        }
        i++;
        string[] memory choices = new string[](lines.length - i);
        uint256 count = 0;
        for (; i < lines.length; i++) {
            if (isInert(lines[i])) {
                continue;
            }
            bytes memory item = bytes(vm.trim(lines[i]));
            if (item.length < 2 || item[0] != "-" || item[1] != " ") {
                break;
            }
            bytes memory choice = new bytes(item.length - 2);
            for (uint256 j = 0; j < choice.length; j++) {
                choice[j] = item[j + 2];
            }
            choices[count] = vm.trim(string(choice));
            count++;
        }
        if (count == 0) {
            revert DispatchChoicesUnreadable(workflow);
        }
        assembly ("memory-safe") {
            mstore(choices, count)
        }
        return choices;
    }

    /// The dispatch choices MUST be exactly the declared suite keys, each once.
    function checkDispatchChoicesAreTheSuiteKeys(DeployDeclaration memory d) internal view {
        DeploySuite[] memory suites = allSuites(d);
        string[] memory choices = dispatchChoices();
        for (uint256 i = 0; i < choices.length; i++) {
            if (suiteIndex(suites, choices[i]) == suites.length) {
                revert DispatchChoiceNotDeclared(choices[i]);
            }
            for (uint256 j = i + 1; j < choices.length; j++) {
                if (keccak256(bytes(choices[i])) == keccak256(bytes(choices[j]))) {
                    revert DispatchChoiceRepeated(choices[i]);
                }
            }
        }
        for (uint256 i = 0; i < suites.length; i++) {
            bool offered = false;
            for (uint256 j = 0; j < choices.length; j++) {
                offered = offered || keccak256(bytes(suites[i].suite)) == keccak256(bytes(choices[j]));
            }
            if (!offered) {
                revert SuiteNotDispatchable(suites[i].suite);
            }
        }
    }

    /// Every anchored candidate's artifact path MUST compile to the source its key names.
    function checkCandidateArtifactPathsAreSource(DeployDeclaration memory d) internal view {
        DeployCandidate[] memory candidates = checkedCandidateSuites(d);
        for (uint256 i = 0; i < candidates.length; i++) {
            if (bytes(candidates[i].unanchorableReason).length != 0) {
                continue;
            }
            DeploySuite memory suite = candidates[i].snapshot;
            if (keccak256(vm.getCode(suite.artifactPath)) != keccak256(sourceCreationCode(suite.suite))) {
                revert CandidateArtifactNotSource(suite.suite, suite.artifactPath);
            }
        }
    }

    /// No suite MAY declare the zero address, or one address twice, as a dependency.
    function checkDependenciesAreNonZeroAndUnique(DeployDeclaration memory d) internal view {
        DeploySuite[] memory suites = allSuites(d);
        for (uint256 i = 0; i < suites.length; i++) {
            DeployDependency[] memory deps = suites[i].dependencies;
            for (uint256 j = 0; j < deps.length; j++) {
                if (deps[j].deployedAddress == address(0)) {
                    revert ZeroDependency(suites[i].suite);
                }
                for (uint256 k = j + 1; k < deps.length; k++) {
                    if (deps[j].deployedAddress == deps[k].deployedAddress) {
                        revert RepeatedDependency(suites[i].suite, deps[j].deployedAddress);
                    }
                }
            }
        }
    }

    /// Every sibling or external deployment a suite's code embeds MUST be a
    /// declared dependency, and every declared dependency MUST be embedded.
    function checkDependenciesAreTheEmbeddedDeployments(DeployDeclaration memory d) internal view {
        DeploySuite[] memory suites = allSuites(d);
        ExternalDeployment[] memory externals = externalDeployments();
        for (uint256 i = 0; i < suites.length; i++) {
            for (uint256 j = 0; j < suites.length; j++) {
                checkDeclaredIfEmbedded(suites[i], suites[j].storedDeployedAddress);
            }
            for (uint256 j = 0; j < externals.length; j++) {
                checkDeclaredIfEmbedded(suites[i], externals[j].deployedAddress);
            }
            DeployDependency[] memory deps = suites[i].dependencies;
            for (uint256 j = 0; j < deps.length; j++) {
                if (!embeds(suites[i], deps[j].deployedAddress)) {
                    revert UnreachedDependency(suites[i].suite, deps[j].deployedAddress);
                }
            }
        }
    }

    /// @param suite The suite.
    /// @param deployment An address the suite MUST declare if its code embeds it.
    function checkDeclaredIfEmbedded(DeploySuite memory suite, address deployment) internal pure {
        if (embeds(suite, deployment) && !declares(suite.dependencies, deployment)) {
            revert UndeclaredDependency(suite.suite, deployment);
        }
    }

    /// Every declared dependency MUST be a sibling or external deployment, with
    /// the runtime code that declaration records.
    function checkDependencyRuntimeCodeIsKnown(DeployDeclaration memory d) internal view {
        DeploySuite[] memory suites = allSuites(d);
        ExternalDeployment[] memory externals = externalDeployments();
        for (uint256 i = 0; i < suites.length; i++) {
            DeployDependency[] memory deps = suites[i].dependencies;
            for (uint256 j = 0; j < deps.length; j++) {
                address dependency = deps[j].deployedAddress;
                bytes32 declared = keccak256(deps[j].runtimeCode);
                bool known = false;
                for (uint256 k = 0; k < suites.length; k++) {
                    if (suites[k].storedDeployedAddress == dependency) {
                        known = true;
                        checkCodeHash(suites[i].suite, dependency, declared, suites[k].storedBytecodeHash);
                    }
                }
                for (uint256 k = 0; k < externals.length; k++) {
                    if (externals[k].deployedAddress == dependency) {
                        known = true;
                        checkCodeHash(suites[i].suite, dependency, declared, externals[k].codeHash);
                    }
                }
                if (!known) {
                    revert UnknownDependency(suites[i].suite, dependency);
                }
            }
        }
    }

    /// @param suite The suite declaring the dependency.
    /// @param dependency The dependency.
    /// @param declared The hash of the runtime code declared at it.
    /// @param expected The hash recorded for it.
    function checkCodeHash(string memory suite, address dependency, bytes32 declared, bytes32 expected) internal pure {
        if (declared != expected) {
            revert DependencyRuntimeCodeMismatch(suite, dependency, declared, expected);
        }
    }

    /// Every candidate's runtime code MUST fit EIP-170.
    function checkCandidateRuntimeCodeFitsEip170(DeployDeclaration memory d) internal pure {
        DeployCandidate[] memory candidates = checkedCandidateSuites(d);
        for (uint256 i = 0; i < candidates.length; i++) {
            uint256 length = candidates[i].snapshot.storedRuntimeCode.length;
            if (length > EIP170_MAX_RUNTIME_CODE_SIZE) {
                revert RuntimeCodeExceedsEip170(candidates[i].snapshot.suite, length);
            }
        }
    }

    /// @param suite The suite.
    /// @param needle The address.
    /// @return Whether the suite's creation code or mechanism data embeds it.
    function embeds(DeploySuite memory suite, address needle) internal pure returns (bool) {
        return containsAddress(suite.creationCode, needle) || containsAddress(suite.mechanismData, needle);
    }

    /// @param deps A dependency list.
    /// @param needle The address.
    /// @return Whether the list declares it.
    function declares(DeployDependency[] memory deps, address needle) internal pure returns (bool) {
        for (uint256 i = 0; i < deps.length; i++) {
            if (deps[i].deployedAddress == needle) {
                return true;
            }
        }
        return false;
    }

    /// Searches for the address with its leading zero bytes stripped, as solc
    /// pushes a constant address.
    /// @param haystack The bytes to search.
    /// @param needle The address.
    /// @return Whether `haystack` contains it. Never for the zero address.
    function containsAddress(bytes memory haystack, address needle) internal pure returns (bool) {
        uint256 value = uint256(uint160(needle));
        uint256 width = 0;
        for (uint256 remaining = value; remaining != 0; remaining >>= 8) {
            width++;
        }
        if (width == 0 || haystack.length < width) {
            return false;
        }
        uint256 shift = 256 - width * 8;
        bytes32 target = bytes32(value << shift);
        bytes32 mask = bytes32(~uint256(0) << shift);
        uint256 last = haystack.length - width;
        for (uint256 i = 0; i <= last; i++) {
            bytes32 window;
            assembly ("memory-safe") {
                window := mload(add(add(haystack, 0x20), i))
            }
            if (window & mask == target) {
                return true;
            }
        }
        return false;
    }
}
