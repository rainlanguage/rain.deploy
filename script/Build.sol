// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {DeployCandidate} from "../src/abstract/RainDeploySuitesBase.sol";
import {RegistryDeploySuites} from "../src/abstract/RegistryDeploySuites.sol";
import {ADDRESS_REGISTRY_ROOT} from "../src/concrete/AddressRegistry.sol";
import {LibRainDeploySnapshot} from "../src/lib/LibRainDeploySnapshot.sol";

/// Thrown when a release is cut while `ADDRESS_REGISTRY_ROOT` is zero.
///
/// Nothing calls from the zero address, so a registry compiled under a zero
/// root can never bind a name and `get` reverts on every read for that build,
/// forever. DEPLOYING one is harmless and is what rollout does. FREEZING one is
/// not: a frozen snapshot is a released suite, `RainDeployVerifyChain` requires
/// every released suite live on every supported network, and that obligation
/// outlives the mistake — it extends to networks added years later.
///
/// Setting a real root afterwards does not retire it. The root is a
/// compile-time constant in the creation code, so the working registry is a
/// DIFFERENT address: the dead one does not go away, it stays declared, stays
/// required to be live, and stays what a consumer pinned to that release
/// resolves against. So the irreversible step is the one that is gated, and
/// only that one — `run()`, the tests and the manual broadcast are untouched.
///
/// The refusal covers the whole release rather than `AddressRegistry` alone,
/// because a release IS the whole of `generatedContracts()` frozen into one
/// tag. There is no per-contract release to let `MigrationRegistry` through,
/// and a tag whose contents depended on which contracts happened to be ready is
/// exactly the record that cannot say what a version deployed.
error InertRegistryRelease();

/// The root a release requires: some account, rather than none.
///
/// Split from `cutRelease` so the rule can be exercised at every root rather
/// than only at the one value this repo currently compiles. The rule is that
/// the root is ABSENT, not that it is any particular account — every non-zero
/// address is one that can bind a name, so every non-zero address releases, and
/// a gate that admitted only some of them would be a second, unwritten policy
/// about who root may be.
/// @param root The root `AddressRegistry` compiles against.
function checkReleasableRoot(address root) pure {
    if (root == address(0)) {
        revert InertRegistryRelease();
    }
}

/// One contract's generated files: the rolling snapshot, the alias lib that
/// re-exports its pins and the released-suites lib emitted from its record.
///
/// The candidate carries the creation code the snapshot is written from and the
/// declaration metadata the released lib copies, so the only things a generated
/// contract adds to it are the two names codegen needs.
struct GeneratedContract {
    /// The contract's name, which places its snapshot inside
    /// `src/generated/<dir>/` and names both generated libs.
    string contractName;
    /// The prefix for the constants the alias lib exports, e.g.
    /// `ADDRESS_REGISTRY`. Passed rather than derived; see `writeAliasLib`.
    string constantPrefix;
    /// The rolling candidate from the declaration. Its `sourceCreationCode` is
    /// what the snapshot is generated from, and its `snapshot` is the template
    /// the released lib takes its key, artifact path and dependencies from.
    DeployCandidate candidate;
}

/// @title Build
/// @notice Generates the deterministic-deploy pins for every contract this repo
/// deploys.
///
/// Two entry points, because there are two different things to do and only one
/// of them happens on an ordinary build:
///
/// - `run()` — every build. Regenerates the ROLLING snapshots under
///   `src/generated/candidate/` from current source, and the alias libs that
///   point at them. Nothing here is frozen, so a source change simply moves it.
/// - `cutRelease()` — a release. Regenerates the rolling snapshots and freezes
///   them as `src/generated/<tag>/`, in ONE call, in that order.
///
/// The alias libs always point at `candidate`, so consumers' import paths never
/// move and `LibAddressRegistry` and `LibMigrationRegistry` always resolve
/// against what this repo currently compiles. The frozen `<tag>/` directories
/// are the historical record — what each release actually deployed — which is
/// what `RegistryDeploySuites.releasedSuites()` enumerates.
///
/// BOTH entry points also regenerate the released-suites libs from the record.
/// `run()` must: they are imported by ordinary source, so a repo before its
/// first release still has to have them, and with nothing frozen they declare
/// an empty set.
///
/// ## One list, three readers
///
/// `generatedContracts()` is the whole of what this script declares, and the
/// regeneration, the lib writers and the freeze all read it. A contract added
/// to it is generated, aliased, released and frozen; there is no second list to
/// add it to and therefore no way to add it to one and not the other. That
/// matters most for the freeze: a contract regenerated but left out of the
/// names `freeze` is given is a contract silently absent from the release,
/// which nothing downstream can notice, because a tag that never held it has
/// nothing missing from it.
///
/// The metadata each released entry carries beyond its frozen snapshot comes
/// from the named candidate on the declaration, which is why this inherits the
/// declaration rather than restating it. There is one suite key, one artifact
/// path and one dependency list per contract in this repo, and a second copy of
/// them here is a second copy that drifts.
///
/// Candidates are reached by NAME rather than by index into `candidateSuites()`
/// for the same reason: a released-suites lib describes one contract, so a
/// positional read would silently write another contract's metadata the moment
/// the list is reordered.
///
/// The tag, both snapshot paths, the freeze, the snapshot writer and both
/// generated-lib writers all come from `LibRainDeploySnapshot`, which in turn
/// emits every constant through `LibCodeGen` and writes snapshots through
/// `LibFs`. This script is the declaration and the sequencing, nothing else.
contract Build is Script, RegistryDeploySuites {
    /// Every contract this repo generates deploy pins for, declared ONCE.
    /// @return contracts The generated contracts.
    function generatedContracts() internal pure returns (GeneratedContract[] memory contracts) {
        contracts = new GeneratedContract[](2);
        contracts[0] = GeneratedContract({
            contractName: "AddressRegistry", constantPrefix: "ADDRESS_REGISTRY", candidate: addressRegistryCandidate()
        });
        contracts[1] = GeneratedContract({
            contractName: "MigrationRegistry",
            constantPrefix: "MIGRATION_REGISTRY",
            candidate: migrationRegistryCandidate()
        });
    }

    /// @notice Every build: regenerate the rolling snapshots, their alias libs
    /// and the released-suites libs.
    function run() external {
        regenerateCandidates();
        regenerateLibs();
    }

    /// @notice A release: regenerate the rolling snapshots, freeze them as this
    /// release's immutable record, then regenerate the declaration of that
    /// record.
    ///
    /// One invocation, so the ordering is a property of the tool rather than of
    /// whoever wrote the release command. `LibRainDeploySnapshot.freeze` takes
    /// the regeneration and runs it FIRST; there is no entry point that freezes
    /// without regenerating, so a stale freeze has nowhere to come from.
    ///
    /// The released-suites libs are written from the record AFTER the freeze,
    /// so the release being cut is in them. A frozen tag no released suite
    /// declares is a release that drops out of every check there is, which is
    /// exactly what generating the two from one call removes.
    ///
    /// Refused outright while `ADDRESS_REGISTRY_ROOT` is zero; see
    /// `InertRegistryRelease` for what freezing that build would commit the
    /// repo to. The check is the FIRST thing here, before anything is read or
    /// written, because filesystem cheatcodes are not undone by a revert — the
    /// same rule `freeze` orders its own guards by.
    function cutRelease() external {
        checkReleasableRoot(ADDRESS_REGISTRY_ROOT);

        GeneratedContract[] memory contracts = generatedContracts();
        string[] memory contractNames = new string[](contracts.length);
        for (uint256 i = 0; i < contracts.length; i++) {
            contractNames[i] = contracts[i].contractName;
        }
        LibRainDeploySnapshot.freeze(vm, regenerateCandidates, contractNames);
        regenerateLibs();
    }

    /// @notice Rewrite every alias lib and every released-suites lib. Both
    /// entry points end here, so there is no entry point that regenerates one
    /// and not the other.
    function regenerateLibs() internal {
        GeneratedContract[] memory contracts = generatedContracts();
        for (uint256 i = 0; i < contracts.length; i++) {
            LibRainDeploySnapshot.writeAliasLib(
                vm, contracts[i].contractName, contracts[i].constantPrefix, LibRainDeploySnapshot.CANDIDATE
            );
            LibRainDeploySnapshot.writeReleasedSuitesLib(
                vm, LibRainDeploySnapshot.LIB_FS_ROOT, contracts[i].contractName, contracts[i].candidate.snapshot
            );
        }
    }

    /// @notice Rewrite every `src/generated/candidate/` snapshot from what this
    /// repo currently compiles.
    function regenerateCandidates() internal {
        GeneratedContract[] memory contracts = generatedContracts();
        for (uint256 i = 0; i < contracts.length; i++) {
            LibRainDeploySnapshot.writeSnapshot(
                vm,
                LibRainDeploySnapshot.CANDIDATE,
                contracts[i].contractName,
                contracts[i].candidate.sourceCreationCode
            );
        }
    }
}
