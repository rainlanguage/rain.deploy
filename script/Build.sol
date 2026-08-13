// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
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
/// `AddressRegistryDeploySuites.releasedSuites()` enumerates.
///
/// The tag, both snapshot paths, the freeze, the snapshot writer and the alias
/// lib writer all come from `LibRainDeploySnapshot`, which in turn emits every
/// constant through `LibCodeGen` and writes snapshots through `LibFs`. This
/// script is the declaration and the sequencing, nothing else.
contract Build is Script {
    /// @notice The prefix for the constants the alias lib exports. Passed
    /// rather than derived from the contract name; see `writeAliasLib`.
    string constant CONSTANT_PREFIX = "ADDRESS_REGISTRY";

    /// @notice Every build: regenerate the rolling snapshot and its alias lib.
    function run() external {
        regenerateCandidate();
        LibRainDeploySnapshot.writeAliasLib(vm, "AddressRegistry", CONSTANT_PREFIX, LibRainDeploySnapshot.CANDIDATE);
    }

    /// @notice A release: regenerate the rolling snapshot, then freeze it as
    /// this release's immutable record.
    ///
    /// One invocation, so the ordering is a property of the tool rather than of
    /// whoever wrote the release command. `LibRainDeploySnapshot.freeze` takes
    /// the regeneration and runs it FIRST; there is no entry point that freezes
    /// without regenerating, so a stale freeze has nowhere to come from.
    ///
    /// Not yet wired into `package-release.yaml`, whose `snapshot-generate-cmd`
    /// still calls `run()`. Changing that input is out of scope here.
    function cutRelease() external {
        string[] memory contractNames = new string[](1);
        contractNames[0] = "AddressRegistry";
        LibRainDeploySnapshot.freeze(vm, regenerateCandidate, contractNames);
        LibRainDeploySnapshot.writeAliasLib(vm, "AddressRegistry", CONSTANT_PREFIX, LibRainDeploySnapshot.CANDIDATE);
    }

    /// @notice Rewrite `src/generated/candidate/AddressRegistry.sol` from what
    /// this repo currently compiles.
    function regenerateCandidate() internal {
        LibRainDeploySnapshot.writeSnapshot(
            vm, LibRainDeploySnapshot.CANDIDATE, "AddressRegistry", type(AddressRegistry).creationCode
        );
    }
}
