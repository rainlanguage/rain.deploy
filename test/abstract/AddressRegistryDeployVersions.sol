// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DeployCandidate, DeployVersion, RainDeployVerifyBase} from "../../src/abstract/RainDeployVerifyBase.sol";
import {AddressRegistry} from "../../src/concrete/AddressRegistry.sol";
import {LibAddressRegistryDeploy} from "../../src/lib/LibAddressRegistryDeploy.sol";

/// @title AddressRegistryDeployVersions
/// @notice Every version of `AddressRegistry` this repo records, declared once
/// and inherited by `AddressRegistryDeployPinsOfflineTest` and
/// `AddressRegistryDeployPinsChainTest`.
///
/// This declaration is the whole of what a deploy repo writes. The verification
/// itself — the derivation from creation code, the comparisons against what is
/// recorded, the source anchor, the networks matrix — is
/// `src/abstract/RainDeployVerify*.sol`'s and is inherited rather than
/// restated. There is deliberately nothing per version and nothing per network
/// here, so neither a new release nor a new supported network adds a test.
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
