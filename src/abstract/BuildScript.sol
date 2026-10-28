// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {RAIN_COPYRIGHT_TEXT, RAIN_SPDX_LICENSE_IDENTIFIER} from "rain-sol-codegen-0.1.39/src/lib/LibCodeGen.sol";
import {
    DeployCandidate,
    DeployDeclaration,
    DeploySuite,
    DuplicateDeploySuite,
    RainDeploySuitesBase
} from "./RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../lib/LibRainDeploy.sol";
import {LibRainDeployConfig} from "../lib/LibRainDeployConfig.sol";
import {LibRainDeploySnapshot} from "../lib/LibRainDeploySnapshot.sol";

/// One contract a deploy repo generates pins for.
struct GeneratedContract {
    /// Names its rolling snapshot and every lib generated for it. For an
    /// anchored candidate, the contract its `artifactPath` names.
    string contractName;
    /// Prefix for the constants its alias lib exports, e.g. `CONFIG_REGISTRY`.
    /// Empty for no alias lib.
    string constantPrefix;
    /// The declared candidate it is generated from.
    DeployCandidate candidate;
}

/// A contract a repo no longer builds, whose released-suites lib is still
/// generated from its frozen record.
struct RetiredContract {
    /// Names its record files and its released-suites lib.
    string contractName;
    /// The suite key and artifact path its released entries are emitted with.
    /// Every other field is read from the record.
    DeploySuite template;
}

/// Thrown when a generated contract's key is no declared candidate's.
/// @param contractName The generated contract.
/// @param suite Its key.
error GeneratedContractNotDeclared(string contractName, string suite);

/// Thrown when a declared candidate is not generated, so no release would
/// freeze it.
/// @param suite The candidate's key.
error DeclaredCandidateNotGenerated(string suite);

/// Thrown when a generated contract carries something other than the candidate
/// declared under its key.
/// @param suite The key.
error GeneratedCandidateNotDeclared(string suite);

/// Thrown when an anchored candidate is generated under a name other than the
/// contract its artifact path names, so its pins land in another contract's
/// files.
/// @param contractName The generated name.
/// @param artifactPath The candidate's artifact path.
error GeneratedContractNameNotArtifact(string contractName, string artifactPath);

/// Thrown when two generated or retired contracts share a name, so one file is
/// written for both.
/// @param contractName The shared name.
error DuplicateGeneratedContractName(string contractName);

/// Thrown when two alias libs would export their constants under one prefix.
/// @param constantPrefix The shared prefix.
error DuplicateConstantPrefix(string constantPrefix);

/// @title BuildScript
/// @notice The two entry points of a deploy repo's `script/Build.sol`, concrete
/// here:
///
/// - `run()` regenerates and freezes nothing. This is the one CI runs.
/// - `cutRelease()` regenerates, freezes the rolling snapshots as
///   `<recordRoot()>/<tag>/`, then regenerates the libs from the record that
///   now holds the release being cut.
///
/// Neither is `virtual`, so a repo inheriting this implements the hooks below
/// and has no entry point to cut a release from other than `cutRelease()`.
///
/// The network config is generated here rather than through a hook a repo
/// implements: the facts come out of `LibRainDeploy.supportedNetworkConfigs()`,
/// this package's own catalogue, and which of them are emitted comes out of
/// `supportedNetworks()` — the one hook on the declaration this inherits, which
/// `RainDeployBroadcast` deploys to and the chain group forks. So a network
/// arrives in a consumer's `foundry.toml` and `.env.example` by a version bump,
/// a repo narrowing the set narrows what it deploys to and what it is verified
/// on by the same answer, and there is no second place to spell either.
///
/// Inheriting the declaration is what makes that one answer: a hook of its own
/// here would be a second statement of the repo's network set, and the config
/// generated from it could cover networks nothing verifies with nothing red.
///
/// `run()` stages those two files rather than writing them, because foundry
/// refuses a cheatcode write to the project root's own `foundry.toml`.
/// `rainix-copy-artifacts` installs what was staged — see `LibRainDeployConfig`.
abstract contract BuildScript is RainDeploySuitesBase, Script {
    /// Rewrite the rolling `candidate/` snapshots from what this repo currently
    /// compiles. Run by `cutRelease()` inside `freeze`, after its guards and
    /// before it copies anything.
    function regenerateSnapshots() internal virtual;

    /// Every contract this repo generates pins for, in the order its libs are
    /// aggregated. Read through `checkedGeneratedContracts`.
    /// @return The generated contracts.
    function generatedContracts() internal view virtual returns (GeneratedContract[] memory);

    /// Contracts this repo no longer builds whose frozen releases stay
    /// declared, in the order they were released. Defaults to none.
    /// @return The retired contracts.
    function retiredContracts() internal view virtual returns (RetiredContract[] memory) {
        return new RetiredContract[](0);
    }

    /// The SPDX licence identifier the generated libs declare. Defaults to
    /// `RAIN_SPDX_LICENSE_IDENTIFIER`, for a repo this org owns.
    /// @return The SPDX licence identifier.
    function libSpdxLicenseIdentifier() internal view virtual returns (string memory) {
        return RAIN_SPDX_LICENSE_IDENTIFIER;
    }

    /// The copyright text the generated libs declare. Defaults to
    /// `RAIN_COPYRIGHT_TEXT`, for a repo this org owns.
    /// @return The copyright text.
    function libCopyrightText() internal view virtual returns (string memory) {
        return RAIN_COPYRIGHT_TEXT;
    }

    /// `generatedContracts()`, refusing a list that is not exactly `d`'s
    /// candidates, an anchored candidate named for another contract, a name
    /// shared with another generated or retired contract, and a non-empty
    /// constant prefix shared by two contracts.
    /// @param d The declaration.
    /// @return The generated contracts.
    function checkedGeneratedContracts(DeployDeclaration memory d) internal view returns (GeneratedContract[] memory) {
        GeneratedContract[] memory generated = generatedContracts();
        checkCandidates(d);
        DeployCandidate[] memory candidates = d.candidates;
        for (uint256 i = 0; i < generated.length; i++) {
            checkGeneratedContract(generated[i], candidates);
            for (uint256 j = i + 1; j < generated.length; j++) {
                if (
                    keccak256(bytes(generated[j].candidate.snapshot.suite))
                        == keccak256(bytes(generated[i].candidate.snapshot.suite))
                ) {
                    revert DuplicateDeploySuite(generated[i].candidate.snapshot.suite);
                }
                if (keccak256(bytes(generated[j].contractName)) == keccak256(bytes(generated[i].contractName))) {
                    revert DuplicateGeneratedContractName(generated[i].contractName);
                }
                if (
                    bytes(generated[i].constantPrefix).length > 0
                        && keccak256(bytes(generated[j].constantPrefix))
                            == keccak256(bytes(generated[i].constantPrefix))
                ) {
                    revert DuplicateConstantPrefix(generated[i].constantPrefix);
                }
            }
        }
        for (uint256 j = 0; j < candidates.length; j++) {
            bytes32 suite = keccak256(bytes(candidates[j].snapshot.suite));
            bool found = false;
            for (uint256 i = 0; i < generated.length; i++) {
                if (keccak256(bytes(generated[i].candidate.snapshot.suite)) == suite) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                revert DeclaredCandidateNotGenerated(candidates[j].snapshot.suite);
            }
        }
        RetiredContract[] memory retired = retiredContracts();
        for (uint256 i = 0; i < retired.length; i++) {
            for (uint256 j = i + 1; j < retired.length; j++) {
                if (keccak256(bytes(retired[j].contractName)) == keccak256(bytes(retired[i].contractName))) {
                    revert DuplicateGeneratedContractName(retired[i].contractName);
                }
            }
            for (uint256 j = 0; j < generated.length; j++) {
                if (keccak256(bytes(generated[j].contractName)) == keccak256(bytes(retired[i].contractName))) {
                    revert DuplicateGeneratedContractName(retired[i].contractName);
                }
            }
        }
        return generated;
    }

    /// Refuses a generated contract whose candidate is not the one declared
    /// under its key, or whose anchored artifact path names another contract.
    /// @param generated The generated contract.
    /// @param candidates The declared candidates.
    function checkGeneratedContract(GeneratedContract memory generated, DeployCandidate[] memory candidates)
        internal
        pure
    {
        bytes32 suite = keccak256(bytes(generated.candidate.snapshot.suite));
        bool found = false;
        for (uint256 j = 0; j < candidates.length; j++) {
            if (keccak256(bytes(candidates[j].snapshot.suite)) == suite) {
                if (keccak256(abi.encode(candidates[j])) != keccak256(abi.encode(generated.candidate))) {
                    revert GeneratedCandidateNotDeclared(generated.candidate.snapshot.suite);
                }
                found = true;
                break;
            }
        }
        if (!found) {
            revert GeneratedContractNotDeclared(generated.contractName, generated.candidate.snapshot.suite);
        }
        if (bytes(generated.candidate.unanchorableReason).length == 0) {
            checkGeneratedContractName(generated);
        }
    }

    /// Refuses a generated contract whose name is not the contract its
    /// artifact path names.
    /// @param generated The generated contract.
    function checkGeneratedContractName(GeneratedContract memory generated) internal pure {
        string[] memory components = vm.split(generated.candidate.snapshot.artifactPath, ":");
        if (keccak256(bytes(components[components.length - 1])) != keccak256(bytes(generated.contractName))) {
            revert GeneratedContractNameNotArtifact(generated.contractName, generated.candidate.snapshot.artifactPath);
        }
    }

    /// The names of `generated`, in order: the contracts whose rolling
    /// snapshots a release freezes.
    /// @param d The declaration.
    /// @param generated `checkedGeneratedContracts(d)`.
    /// @return The contract names.
    function snapshotContractNames(DeployDeclaration memory d, GeneratedContract[] memory generated)
        internal
        pure
        returns (string[] memory)
    {
        (d);
        string[] memory names = new string[](generated.length);
        for (uint256 i = 0; i < generated.length; i++) {
            names[i] = generated[i].contractName;
        }
        return names;
    }

    /// Every contract with a released-suites lib, in the order the aggregate
    /// lists them: `retiredContracts()`, then `generated`.
    /// @param generated `checkedGeneratedContracts(d)`.
    /// @return The contract names.
    function releasedContractNames(GeneratedContract[] memory generated) internal view returns (string[] memory) {
        RetiredContract[] memory retired = retiredContracts();
        string[] memory names = new string[](retired.length + generated.length);
        for (uint256 i = 0; i < retired.length; i++) {
            names[i] = retired[i].contractName;
        }
        for (uint256 i = 0; i < generated.length; i++) {
            names[retired.length + i] = generated[i].contractName;
        }
        return names;
    }

    /// Rewrite every generated lib under `libDir()`: each retired contract's
    /// released-suites lib, each generated contract's alias lib (when it has a
    /// prefix) and released-suites lib, then the aggregate over
    /// `releasedContractNames(generated)`. Run last, after a `cutRelease()`
    /// freeze has written the record, so a lib emitted from that record holds
    /// the release just cut.
    /// @param d The declaration.
    /// @param generated `checkedGeneratedContracts(d)`.
    function regenerateLibs(DeployDeclaration memory d, GeneratedContract[] memory generated) internal {
        (d);
        RetiredContract[] memory retired = retiredContracts();
        string memory dir = libDir();
        string memory spdxLicenseIdentifier = libSpdxLicenseIdentifier();
        string memory copyrightText = libCopyrightText();
        for (uint256 i = 0; i < retired.length; i++) {
            LibRainDeploySnapshot.writeReleasedSuitesLib(
                vm,
                dir,
                recordRoot(),
                retired[i].contractName,
                spdxLicenseIdentifier,
                copyrightText,
                retired[i].template
            );
        }
        for (uint256 i = 0; i < generated.length; i++) {
            if (bytes(generated[i].constantPrefix).length > 0) {
                LibRainDeploySnapshot.writeAliasLib(
                    vm,
                    dir,
                    generated[i].contractName,
                    generated[i].constantPrefix,
                    LibRainDeploySnapshot.CANDIDATE,
                    spdxLicenseIdentifier,
                    copyrightText
                );
            }
            LibRainDeploySnapshot.writeReleasedSuitesLib(
                vm,
                dir,
                recordRoot(),
                generated[i].contractName,
                spdxLicenseIdentifier,
                copyrightText,
                generated[i].candidate.snapshot
            );
        }
        LibRainDeploySnapshot.writeReleasedSuitesAggregate(
            vm, dir, spdxLicenseIdentifier, copyrightText, releasedContractNames(generated)
        );
    }

    /// Every rolling snapshot a release freezes into its record: the
    /// `snapshotContractNames()` deploy suites and any other snapshot the repo
    /// regenerates into the candidate, so the frozen record holds the WHOLE
    /// candidate the release guard compares it against. Defaults to
    /// `snapshotContractNames()` for a repo whose candidate holds nothing else.
    /// @return The snapshot names.
    /// @param d The declaration.
    /// @param generated `checkedGeneratedContracts(d)`.
    function releaseRecordNames(DeployDeclaration memory d, GeneratedContract[] memory generated)
        internal
        view
        virtual
        returns (string[] memory)
    {
        return snapshotContractNames(d, generated);
    }

    /// The record root a release is frozen into, and the one the rolling
    /// snapshots are read from.
    ///
    /// Overridable so a `cutRelease()` can be exercised against a record other
    /// than the repo's own, which is append-only and cannot hold a test's
    /// release.
    /// @return The record root.
    function recordRoot() internal view virtual returns (string memory) {
        return LibRainDeploySnapshot.LIB_FS_ROOT;
    }

    /// The root holding the `foundry.toml` and `.env.example` whose network
    /// blocks are generated, and the parent of the staging directory they are
    /// written to.
    ///
    /// Overridable for the same reason `recordRoot` is: a writer that can only
    /// be pointed at the committed tree can only be exercised against it. The
    /// hazard is the same too — a repo pointing this anywhere but its own root
    /// generates config nothing reads, and `Git is clean` then sees a tree that
    /// never drifts because nothing regenerates it.
    /// @return The config root.
    function configRoot() internal view virtual returns (string memory) {
        return LibRainDeployConfig.CONFIG_ROOT;
    }

    /// Rewrite the delimited network config blocks from the declared networks'
    /// catalogue entries.
    ///
    /// Run by `run()` and not by `cutRelease()`: the config is not part of a
    /// release record, and `run()` is what `Git is clean` calls on every push,
    /// so a tree whose config has drifted from the declaration it pins fails
    /// there.
    ///
    /// This STAGES the files; `rainix-copy-artifacts` installs them. See
    /// `LibRainDeployConfig` for why a script cannot write `foundry.toml`
    /// itself.
    function regenerateConfig(DeployDeclaration memory d) internal {
        LibRainDeployConfig.writeStagedConfig(vm, configRoot(), LibRainDeploy.declaredNetworkConfigs(d.networks));
    }

    /// The directory `regenerateLibs` writes every generated lib into, and the
    /// one `generatedPaths()` declares them under.
    ///
    /// Overridable for the reason `recordRoot` is: a hook that can only be
    /// pointed at the committed tree can only be RUN by overwriting files the
    /// rest of the suite compiles and reads, and forge runs test contracts in
    /// parallel. Only the per-contract libs and the aggregate go here —
    /// `regenerateSnapshots` has no equivalent, because `LibFs` confines every
    /// snapshot it writes to `src/generated/`.
    /// @return The lib directory.
    function libDir() internal view virtual returns (string memory) {
        return LibRainDeploySnapshot.LIB_DIR;
    }

    /// Every path the repo's own hooks write that `generatedPaths()` does not
    /// already name, e.g. alias libs or retired contracts' released-suites libs.
    /// Defaults to none.
    /// @return The paths.
    function buildGeneratedPaths() internal view virtual returns (string[] memory) {
        return new string[](0);
    }

    /// Every path `run()` must rewrite, the installed staged config included.
    /// @return The paths.
    function generatedPaths(DeployDeclaration memory d, GeneratedContract[] memory generated)
        internal
        view
        returns (string[] memory)
    {
        string[] memory base = LibRainDeploySnapshot.generatedPaths(
            libDir(), recordRoot(), releaseRecordNames(d, generated), releasedContractNames(generated)
        );
        string[] memory aliases = aliasLibPaths(generated);
        string[] memory own = buildGeneratedPaths();
        string[] memory paths = new string[](base.length + aliases.length + 2 + own.length);
        uint256 offset = 0;
        for (uint256 i = 0; i < base.length; i++) {
            paths[offset++] = base[i];
        }
        for (uint256 i = 0; i < aliases.length; i++) {
            paths[offset++] = aliases[i];
        }
        paths[offset++] = LibRainDeployConfig.CONFIG_NAME;
        paths[offset++] = LibRainDeployConfig.ENV_EXAMPLE_NAME;
        for (uint256 i = 0; i < own.length; i++) {
            paths[offset++] = own[i];
        }
        return paths;
    }

    /// The alias lib `regenerateLibs` writes for each generated contract with
    /// a constant prefix.
    /// @param generated `checkedGeneratedContracts(d)`.
    /// @return The paths.
    function aliasLibPaths(GeneratedContract[] memory generated) internal view returns (string[] memory) {
        string memory dir = libDir();
        string[] memory written = new string[](generated.length);
        uint256 count = 0;
        for (uint256 i = 0; i < generated.length; i++) {
            if (bytes(generated[i].constantPrefix).length > 0) {
                written[count++] =
                    LibRainDeploySnapshot.pathForLib(dir, LibRainDeploySnapshot.aliasLibraryName(generated[i].contractName));
            }
        }
        string[] memory paths = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            paths[i] = written[i];
        }
        return paths;
    }

    /// Prints `generatedPaths()` for `rainix-copy-artifacts` to fail a run that
    /// leaves one unwritten.
    function declareGeneratedPaths(DeployDeclaration memory d, GeneratedContract[] memory generated) internal view {
        LibRainDeploySnapshot.declareGenerated(generatedPaths(d, generated));
    }

    /// @notice Regenerate everything this repo generates. Freezes nothing.
    function run() external {
        DeployDeclaration memory d = declaration();
        GeneratedContract[] memory generated = checkedGeneratedContracts(d);
        declareGeneratedPaths(d, generated);
        regenerateConfig(d);
        regenerateSnapshots();
        regenerateLibs(d, generated);
    }

    /// @notice Regenerate the rolling snapshots, freeze them as this release's
    /// record, then regenerate the libs from the record.
    function cutRelease() external {
        DeployDeclaration memory d = declaration();
        GeneratedContract[] memory generated = checkedGeneratedContracts(d);
        LibRainDeploySnapshot.freeze(vm, recordRoot(), regenerateSnapshots, releaseRecordNames(d, generated));
        regenerateLibs(d, generated);
    }
}
