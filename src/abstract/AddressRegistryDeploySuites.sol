// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "./RainDeploySuitesBase.sol";
import {AddressRegistry} from "../concrete/AddressRegistry.sol";
import {LibAddressRegistryDeploy} from "../lib/LibAddressRegistryDeploy.sol";

/// @title AddressRegistryDeploySuites
/// @notice Everything this repo deploys, declared ONCE.
///
/// Three contracts inherit this and nothing else declares a suite:
///
/// - `script/Deploy.sol` broadcasts from it
/// - `AddressRegistryDeployPinsOfflineTest` checks its records against its
///   creation code
/// - `AddressRegistryDeployPinsChainTest` checks it against every chain
///
/// So "the deploy script broadcasts one contract while the tests verify
/// another" is not a thing that can be true here. Not because something checks
/// for it — because there is only one list, and all three read it.
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
/// From the first `sol-v*` release this is what `script/Build.sol` generates.
abstract contract AddressRegistryDeploySuites is RainDeploySuitesBase {
    /// @inheritdoc RainDeploySuitesBase
    /// @dev Empty: no release has been cut, so no snapshot is frozen.
    /// `src/generated/<tag>/` is append-only and `ADDRESS_REGISTRY_ROOT` is
    /// still a placeholder, so a snapshot written now could never be corrected.
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        return new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    /// @dev The pins in `LibAddressRegistryDeploy` are hand-written literals,
    /// and they are what the internal group checks the derivation against and
    /// what the broadcast asserts against before it forks anything.
    ///
    /// The creation code and runtime code come from source because nothing
    /// records them yet — there is no `src/generated/candidate/` pointers file
    /// to read them from. Until there is, the source anchor compares source
    /// against itself and can only pass: what it protects against is a RECORDED
    /// creation code drifting from the source it claims to be, and there is no
    /// recorded creation code here to drift. The address and code hash pins ARE
    /// recorded, and those are checked for real.
    ///
    /// `AddressRegistry` reads nothing and calls nothing at construction, so it
    /// has no dependency that must already be on chain.
    function candidateSuite() internal pure override returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "address-registry",
                creationCode: type(AddressRegistry).creationCode,
                storedDeployedAddress: LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
                storedBytecodeHash: LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH,
                storedRuntimeCode: type(AddressRegistry).runtimeCode,
                artifactPath: "src/concrete/AddressRegistry.sol:AddressRegistry",
                dependencies: new address[](0)
            }),
            sourceCreationCode: type(AddressRegistry).creationCode
        });
    }
}
