// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {RegistryDeploySuites} from "../src/abstract/RegistryDeploySuites.sol";
import {LibRainDeploySnapshot} from "../src/lib/LibRainDeploySnapshot.sol";
import {AddressRegistry} from "../src/concrete/AddressRegistry.sol";

/// @title Build
/// @notice Generates the deterministic-deploy pins for `AddressRegistry`.
///
/// Two entry points, because there are two different things to do and only one
/// of them happens on an ordinary build:
///
/// - `run()` — every build. Regenerates the ROLLING snapshot
///   `src/generated/candidate/AddressRegistry.sol` from current source,
///   and the alias lib that points at it. Nothing here is frozen, so a source
///   change simply moves it.
/// - `cutRelease()` — a release. Regenerates the rolling snapshot and freezes
///   it as `src/generated/<tag>/`, in ONE call, in that order.
///
/// The alias lib always points at `candidate`, so consumers' import path never
/// moves and `LibAddressRegistry` always resolves against what this repo
/// currently compiles. The frozen `<tag>/` directories are the historical
/// record — what each release actually deployed — which is what
/// `RegistryDeploySuites.releasedSuites()` enumerates.
///
/// BOTH entry points also regenerate that released-suites lib from the record.
/// `run()` must: the lib is imported by ordinary source, so a repo before its
/// first release still has to have one, and with nothing frozen it declares an
/// empty set.
///
/// The metadata each released entry carries beyond its frozen snapshot comes
/// from the named candidate on the declaration, which is why this inherits the
/// declaration rather than restating it. There is one suite key, one artifact
/// path and one dependency list per contract in this repo, and a second copy of
/// them here is a second copy that drifts.
///
/// Named rather than indexed out of `candidateSuites()`: a released-suites lib
/// describes ONE contract, so this has to select the candidate for the contract
/// it is writing, and a positional read would silently write another contract's
/// metadata the moment the list is reordered.
///
/// The tag, both snapshot paths, the freeze, the snapshot writer and both
/// generated-lib writers all come from `LibRainDeploySnapshot`, which in turn
/// emits every constant through `LibCodeGen` and writes snapshots through
/// `LibFs`. This script is the declaration and the sequencing, nothing else.
contract Build is Script, RegistryDeploySuites {
    /// @notice The prefix for the constants the alias lib exports. Passed
    /// rather than derived from the contract name; see `writeAliasLib`.
    string constant CONSTANT_PREFIX = "ADDRESS_REGISTRY";

    /// @notice The contract this repo deploys. Named once, because the
    /// snapshot, the alias lib, the released-suites lib and the freeze all
    /// describe the same contract, and a second spelling of it is a second
    /// spelling that drifts.
    string constant CONTRACT_NAME = "AddressRegistry";

    /// @notice Every build: regenerate the rolling snapshot, its alias lib and
    /// the released-suites lib.
    function run() external {
        regenerateCandidate();
        regenerateLibs();
    }

    /// @notice A release: regenerate the rolling snapshot, freeze it as this
    /// release's immutable record, then regenerate the declaration of that
    /// record.
    ///
    /// One invocation, so the ordering is a property of the tool rather than of
    /// whoever wrote the release command. `LibRainDeploySnapshot.freeze` takes
    /// the regeneration and runs it FIRST; there is no entry point that freezes
    /// without regenerating, so a stale freeze has nowhere to come from.
    ///
    /// The released-suites lib is written from the record AFTER the freeze, so
    /// the release being cut is in it. A frozen tag no released suite declares
    /// is a release that drops out of every check there is, which is exactly
    /// what generating the two from one call removes.
    function cutRelease() external {
        string[] memory contractNames = new string[](1);
        contractNames[0] = CONTRACT_NAME;
        LibRainDeploySnapshot.freeze(vm, regenerateCandidate, contractNames);
        regenerateLibs();
    }

    /// @notice Rewrite the alias lib and the released-suites lib. Both entry
    /// points end here, so there is no entry point that regenerates one and not
    /// the other.
    function regenerateLibs() internal {
        LibRainDeploySnapshot.writeAliasLib(vm, CONTRACT_NAME, CONSTANT_PREFIX, LibRainDeploySnapshot.CANDIDATE);
        LibRainDeploySnapshot.writeReleasedSuitesLib(
            vm, LibRainDeploySnapshot.LIB_FS_ROOT, CONTRACT_NAME, addressRegistryCandidate().snapshot
        );
    }

    /// @notice Rewrite `src/generated/candidate/AddressRegistry.sol` from what
    /// this repo currently compiles.
    function regenerateCandidate() internal {
        LibRainDeploySnapshot.writeSnapshot(
            vm, LibRainDeploySnapshot.CANDIDATE, CONTRACT_NAME, type(AddressRegistry).creationCode
        );
    }
}
