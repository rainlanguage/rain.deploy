// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeployDependency,
    DeployDeclaration,
    DeploySuite,
    RainDeploySuitesBase
} from "./RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "../lib/LibRainDeployDeclaration.sol";
import {
    CREATION_CODE as CONFIG_REGISTRY_CREATION_CODE_CANDIDATE,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE_CANDIDATE
} from "../generated/candidate/ConfigRegistry.sol";
import {
    CREATION_CODE as MIGRATION_REGISTRY_CREATION_CODE_CANDIDATE,
    RUNTIME_CODE as MIGRATION_REGISTRY_RUNTIME_CODE_CANDIDATE
} from "../generated/candidate/MigrationRegistry.sol";
import {LibConfigRegistryDeploy} from "../lib/LibConfigRegistryDeploy.sol";
import {LibMigrationRegistryDeploy} from "../lib/LibMigrationRegistryDeploy.sol";
import {LibRainDeploy} from "../lib/LibRainDeploy.sol";
import {LibReleasedSuites} from "../lib/LibReleasedSuites.sol";
import {LibTimelockController} from "../lib/LibTimelockController.sol";

/// A contract this repo records the code of but does not declare as a deploy
/// suite, because its constructor takes arguments: its Zoltu address is a
/// function of the creation code WITH those arguments, so every argument set
/// is its own deploy and there is no one address a suite could pin, broadcast
/// to or verify on every network. `script/Build.sol` writes its code to the
/// rolling snapshot with `LibRainDeploySnapshot.writeParameterisedSnapshot`,
/// and the library that picks the arguments derives the address and deploys.
struct ParameterisedContract {
    /// `<path>:<Name>`, the artifact the recorded code is compiled from. The
    /// name is the snapshot's file name.
    string artifactPath;
    /// Any valid constructor arguments, for the reference deploy the runtime
    /// code is read from.
    bytes referenceConstructorArgs;
    /// The SPDX licence identifier the snapshot declares: the upstream
    /// contract's own, not this repo's.
    string spdxLicenseIdentifier;
    /// The copyright text the snapshot declares, from the upstream licence.
    string copyrightText;
}

/// @title RegistryDeploySuites
/// @notice Everything this repo deploys, declared ONCE.
///
/// These contracts inherit it, and nothing else declares a suite:
///
/// - `script/Deploy.sol` broadcasts from it
/// - `script/Build.sol` generates the snapshots, the alias libs and the
///   released-suites libs from it — the named candidates below are the
///   templates it emits from, which is why it inherits the declaration rather
///   than restating the key, the artifact path and the dependency list
/// - `RegistryDeployVerifyTest` checks its records against its creation code
///   and against every chain
/// - `GeneratedSnapshotShapeTest` checks the shape of the files that generation
///   writes
///
/// So "the deploy script broadcasts one contract while the tests verify
/// another" is not a thing that can be true here. Not because something checks
/// for it — because there is only one list, and they all read it.
///
/// It lives in `src/` rather than `test/` for two reasons. `.soldeerignore`
/// excludes `test/`, and a downstream `script/` has to import its own
/// equivalent. And in THIS repo the deployment process is the product: see the
/// scoped exception recorded in `CLAUDE.md`.
///
/// This declaration is the whole of what a deploy repo writes. The derivation,
/// the comparisons, the source anchor, the networks matrix and the broadcast
/// are all inherited. There is deliberately nothing per suite beyond an array
/// entry and nothing per network at all.
///
/// Half of it is written by hand and half is generated: the candidates below
/// are the declaration, and the whole released side — the per-contract libs and
/// the aggregate that concatenates them — comes from `script/Build.sol`, which
/// emits it from the frozen record. Nothing about a release is written here.
abstract contract RegistryDeploySuites is RainDeploySuitesBase {
    /// This repo's declaration: every Rain network, Zoltu, the generated releases with each `AddressRegistry`
    /// release required only on `addressRegistryNetworks()`, and `registryCandidates()`.
    /// @return The declaration.
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory declared = LibRainDeployDeclaration.zoltu();
        declared.released = registryReleasedSuites();
        declared.candidates = registryCandidates();
        return declared;
    }

    /// The suite key of the retired `AddressRegistry` releases.
    string constant ADDRESS_REGISTRY_SUITE = "address-registry";

    /// The networks the `AddressRegistry` releases were live on when it was
    /// retired. Frozen: no candidate carries its bytecode, so nothing can
    /// deploy it to a network added since.
    /// @return The network names.
    function addressRegistryNetworks() internal pure returns (string[] memory) {
        string[] memory networks = new string[](9);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.BASE;
        networks[2] = LibRainDeploy.BASE_SEPOLIA;
        networks[3] = LibRainDeploy.BSC;
        networks[4] = LibRainDeploy.ETHEREUM;
        networks[5] = LibRainDeploy.FLARE;
        networks[6] = LibRainDeploy.HYPEREVM;
        networks[7] = LibRainDeploy.POLYGON;
        networks[8] = LibRainDeploy.ROBINHOOD;
        return networks;
    }

    /// Generated by `script/Build.sol` from the frozen
    /// `src/generated/<tag>/` record, in the same call that writes it. The
    /// record and the declaration of it therefore cannot disagree — which
    /// matters because a release missing from the declaration is a release
    /// every check quietly stops asking about, while the whole suite stays
    /// green.
    ///
    /// There is one generated lib per deployed contract, because
    /// `writeReleasedSuitesLib` emits the releases of ONE contract: a release
    /// freezes every contract it names into a single tag directory, so a lib
    /// that took the record whole would give another contract's snapshot this
    /// contract's suite key and collide with its own entry for that tag.
    /// `LibReleasedSuites` concatenates them, generated from
    /// `releasedContractNames()`: the retired contracts' libs first, then the
    /// libs written from the generated list.
    ///
    /// The rolling `candidate/` snapshots are not releases.
    /// @return The releases, each `AddressRegistry` one declaring `addressRegistryNetworks()`.
    function registryReleasedSuites() internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory released = LibReleasedSuites.releasedSuites();
        for (uint256 i = 0; i < released.length; i++) {
            if (keccak256(bytes(suiteKeyName(released[i].suite))) == keccak256(bytes(ADDRESS_REGISTRY_SUITE))) {
                released[i].networks = addressRegistryNetworks();
            }
        }
        return released;
    }

    /// One entry per contract this repo deploys. A third deployed contract
    /// is a third named candidate below and a third entry here, each enforced
    /// by a test:
    ///
    /// - a third entry in `script/Build.sol`'s generated-contract list
    /// - a third `suite` option in `.github/workflows/manual-sol-artifacts.yaml`
    ///   and the matching length and key in
    ///   `testCandidateKeysAreTheDispatchOptions`
    /// - a third `compilation_restrictions` entry in `foundry.toml`
    ///
    /// The released declaration follows from the generated-contract entry:
    /// `script/Build.sol` generates the per-contract released lib from that
    /// list, and the aggregate `releasedSuites()` reads from
    /// `releasedContractNames()`, its retired contracts then that list.
    function registryCandidates() internal pure returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](2);
        candidates[0] = configRegistryCandidate();
        candidates[1] = migrationRegistryCandidate();
        return candidates;
    }

    /// This repo's rolling `ConfigRegistry` candidate.
    ///
    /// The pins in `LibConfigRegistryDeploy` are aliased from the generated
    /// snapshot, and they are what the internal group checks the derivation
    /// against and what the broadcast asserts against before it forks anything.
    ///
    /// The creation code and runtime code are RECORDED, read from the rolling
    /// `src/generated/candidate/` snapshot. That is what makes the source
    /// anchor mean something: it compares the recorded creation code against
    /// whatever the `artifactPath` below currently compiles to, so editing the
    /// contract without re-running `script/Build.sol` fails.
    ///
    /// `ConfigRegistry` reads nothing and calls nothing at construction, so it
    /// has no dependency that must already be on chain.
    ///
    /// Named rather than reached by index into `registryCandidates`, because
    /// `script/Build.sol` needs THIS candidate specifically — a released-suites
    /// lib describes one contract — and a positional read silently describes a
    /// different contract the moment the list is reordered. Naming it here also
    /// keeps the suite key, the artifact path and the dependency list spelled
    /// once: `Build.sol` inherits this rather than restating them.
    /// @return The candidate.
    function configRegistryCandidate() internal pure returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                networks: new string[](0),
                suite: "config-registry",
                creationCode: CONFIG_REGISTRY_CREATION_CODE_CANDIDATE,
                storedDeployedAddress: LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
                storedBytecodeHash: LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                storedRuntimeCode: CONFIG_REGISTRY_RUNTIME_CODE_CANDIDATE,
                artifactPath: "src/concrete/ConfigRegistry.sol:ConfigRegistry",
                dependencies: new DeployDependency[](0),
                mechanismData: ""
            }),
            unanchorableReason: ""
        });
    }

    /// This repo's rolling `MigrationRegistry` candidate.
    ///
    /// Everything said about the `ConfigRegistry` candidate holds here
    /// unchanged: the pins are aliased from the generated snapshot, the
    /// creation and runtime code are recorded rather than derived, and the
    /// source anchor is what says the record describes THIS contract.
    ///
    /// `MigrationRegistry` has no constructor argument, no compile-time
    /// authority and no dependency to be on chain first, so there is nothing to
    /// configure and nothing to resolve.
    /// That is also why it is deployable to a new network the day the network
    /// is added, with no follow-up transaction to make it useful.
    /// @return The candidate.
    function migrationRegistryCandidate() internal pure returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                networks: new string[](0),
                suite: "migration-registry",
                creationCode: MIGRATION_REGISTRY_CREATION_CODE_CANDIDATE,
                storedDeployedAddress: LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_ADDRESS,
                storedBytecodeHash: LibMigrationRegistryDeploy.MIGRATION_REGISTRY_DEPLOYED_CODEHASH,
                storedRuntimeCode: MIGRATION_REGISTRY_RUNTIME_CODE_CANDIDATE,
                artifactPath: "src/concrete/MigrationRegistry.sol:MigrationRegistry",
                dependencies: new DeployDependency[](0),
                mechanismData: ""
            }),
            unanchorableReason: ""
        });
    }

    /// Every contract this repo records the code of without declaring it as a
    /// deploy suite. Its snapshot is in `src/generated/candidate/` beside the
    /// candidates', so `GeneratedSnapshotShapeTest` matches that directory
    /// against both lists.
    ///
    /// Frozen by `cutRelease()` beside the suites' records (`releaseRecordNames`),
    /// so each release states the generation of this code it shipped: a
    /// compiler-profile or dependency change regenerates the candidate and moves
    /// every address derived from it, and the frozen copy is what still names
    /// the generation production was deployed from. Not in the released suites,
    /// which record a deploy at one address on every network; a frozen code
    /// record is held to itself by `testEveryFrozenCodeRecordIsConsistent`, and
    /// the frozen generation production was deployed from is held to production
    /// by deriving the deployed timelocks' addresses from it.
    /// @return The parameterised contracts.
    function parameterisedContracts() internal pure returns (ParameterisedContract[] memory) {
        ParameterisedContract[] memory contracts = new ParameterisedContract[](1);
        contracts[0] = ParameterisedContract({
            artifactPath: "dependencies/@openzeppelin-contracts-5.7.0/governance/TimelockController.sol:TimelockController",
            // `TimelockController` has no immutables, so any proposer and delay
            // deploy the same runtime code.
            referenceConstructorArgs: LibTimelockController.timelockConstructorArgs(0, address(1)),
            // OpenZeppelin's licence: the dependency's SPDX header and the
            // LICENSE of its v5.7.0 release.
            spdxLicenseIdentifier: "MIT",
            copyrightText: "Copyright (c) 2016-2026 Zeppelin Group Ltd"
        });
        return contracts;
    }

    /// The contract a parameterised contract declaration describes, taken from
    /// its `<path>:<Name>` artifact path: the text after the last `:`. It is
    /// also the name its snapshot is written and frozen under.
    /// @param declared The declaration to name.
    /// @return The contract name.
    function parameterisedContractName(ParameterisedContract memory declared) internal pure returns (string memory) {
        bytes memory path = bytes(declared.artifactPath);
        uint256 start = 0;
        for (uint256 i = path.length; i > 0; i--) {
            if (path[i - 1] == ":") {
                start = i;
                break;
            }
        }
        bytes memory name = new bytes(path.length - start);
        for (uint256 i = 0; i < name.length; i++) {
            name[i] = path[start + i];
        }
        return string(name);
    }

    /// Every parameterised contract's name, in declaration order: the names
    /// a release freezes their code records under.
    /// @return The names.
    function parameterisedContractNames() internal pure returns (string[] memory) {
        ParameterisedContract[] memory parameterised = parameterisedContracts();
        string[] memory names = new string[](parameterised.length);
        for (uint256 i = 0; i < parameterised.length; i++) {
            names[i] = parameterisedContractName(parameterised[i]);
        }
        return names;
    }
}
