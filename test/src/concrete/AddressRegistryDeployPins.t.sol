// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DeployCandidate, DeployVersion, RainDeployVerifyBase} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {RainDeployVerifyOffline} from "../../../src/abstract/RainDeployVerifyOffline.sol";
import {AddressRegistry} from "../../../src/concrete/AddressRegistry.sol";
import {LibAddressRegistryDeploy} from "../../../src/lib/LibAddressRegistryDeploy.sol";

/// @title AddressRegistryDeployVersions
/// @notice Every version of `AddressRegistry` this repo records, declared once
/// and inherited into one offline contract and one chain contract below.
///
/// This declaration is the whole of what a deploy repo writes. The verification
/// itself — the derivation from creation code, the comparisons against what is
/// recorded, the source anchor, the networks matrix — is `rain-deploy`'s and is
/// inherited rather than restated. There is deliberately nothing per version
/// and nothing per network here, so neither a new release nor a new supported
/// network adds a test.
///
/// From the first `sol-v*` release this declaration is what `script/Build.sol`
/// generates, so the frozen snapshot a release cuts is in the enumeration the
/// moment it exists rather than the next time somebody remembers to add a test.
abstract contract AddressRegistryDeployVersions is RainDeployVerifyBase {
    /// @inheritdoc RainDeployVerifyBase
    /// @dev Empty: no release has been cut, so no snapshot is frozen.
    /// `src/generated/<tag>/` is append-only and `ADDRESS_REGISTRY_ROOT` is
    /// still a placeholder, so a snapshot written now could never be corrected.
    function releasedVersions() internal pure override returns (DeployVersion[] memory) {
        return new DeployVersion[](0);
    }

    /// @inheritdoc RainDeployVerifyBase
    /// @dev The pins in `LibAddressRegistryDeploy` are hand-written literals,
    /// and they are what the internal group checks the derivation against.
    ///
    /// The creation code and runtime code come from source because nothing
    /// records them yet — there is no `src/generated/candidate/` pointers file
    /// to read them from. Until there is, the source anchor compares source
    /// against itself and can only pass: what it protects against is a RECORDED
    /// creation code drifting from the source it claims to be, and there is no
    /// recorded creation code here to drift. The address and code hash pins ARE
    /// recorded, and those are checked for real.
    function candidateVersion() internal pure override returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeployVersion({
                version: "candidate",
                creationCode: type(AddressRegistry).creationCode,
                storedDeployedAddress: LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
                storedBytecodeHash: LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH,
                storedRuntimeCode: type(AddressRegistry).runtimeCode
            }),
            sourceCreationCode: type(AddressRegistry).creationCode
        });
    }
}

/// @title AddressRegistryDeployPinsOfflineTest
/// @notice The deploy-pin assertions for `AddressRegistry` that need no
/// network. The pins are a pure function of the creation code, which is a pure
/// function of this repo's compiler settings — and the contract, the settings
/// and the pins are all in this repo, so this closes the loop rather than
/// asserting across a boundary.
///
/// The root authority is a constant in that creation code, so changing the root
/// moves both pins and turns this red until they follow.
contract AddressRegistryDeployPinsOfflineTest is AddressRegistryDeployVersions, RainDeployVerifyOffline {}

/// @title AddressRegistryDeployPinsChainTest
/// @notice Whether `AddressRegistry` is actually live, with the code this repo
/// compiles, on every supported network.
///
/// It is not. `AddressRegistry` has never been deployed and
/// `ADDRESS_REGISTRY_ROOT` is still a placeholder, so this fails on the first
/// network with `NotDeployedOnNetwork` and keeps failing until the contract is
/// deployed to all five.
///
/// That failure is the check working. "Nothing is deployed at the address
/// `LibAddressRegistry` reads" is true, it is the single most important fact
/// about these pins, and no offline assertion can discover it — a perfectly
/// consistent set of pins for a contract that exists nowhere passes every one
/// of them. A green here would only mean nobody asked.
///
/// It is a separate contract from the offline assertions precisely so that it
/// says this and nothing more: `forge test --no-match-contract Chain` still
/// verifies everything that holds offline, whether the deployment is missing or
/// the RPC endpoints are merely unreachable.
contract AddressRegistryDeployPinsChainTest is AddressRegistryDeployVersions, RainDeployVerifyChain {}
