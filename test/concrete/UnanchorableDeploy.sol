// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {DeployCandidate, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {
    BYTECODE_HASH as ADDRESS_REGISTRY_BYTECODE_HASH,
    CREATION_CODE as ADDRESS_REGISTRY_CREATION_CODE,
    DEPLOYED_ADDRESS as ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as ADDRESS_REGISTRY_RUNTIME_CODE
} from "../../src/generated/candidate/AddressRegistry.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";

/// @dev Creation code no compiler here produces: `PUSH1 0 PUSH1 0 RETURN`,
/// which deploys empty runtime code. The vendored case in miniature — these
/// bytes are the whole statement of what the code is, and nothing in `out/`
/// holds them.
bytes constant VENDORED_CREATION_CODE = hex"60006000f3";

/// @dev A second one, so the two unanchorable entries are two snapshots rather
/// than one under two keys. Writes `0x01` into memory and returns it, so its
/// runtime code is that one byte.
bytes constant ASSEMBLED_CREATION_CODE = hex"600160005360016000f3";

/// @title UnanchorableDeploy
/// @notice A deploy script declaring candidates whose source NO compiler
/// produces, beside one it does.
///
/// A real script rather than a declaration fixture for the reason
/// `SourceMismatchDeploy` is one: the claim is about `run()`. The anchor is the
/// first statement of the irreversible path, so a candidate it cannot resolve
/// is a suite that cannot be broadcast at all — and the suites that look like
/// this are a vendored third party deployment and a generated data contract,
/// which is to say the ones a repo has no other way to put on chain.
///
/// BOTH shapes an artifact-less path takes are declared: a bare contract name
/// and nothing at all. Neither resolves, and the mechanism treats them the
/// same, so a change that special-cased the empty string is caught.
///
/// The ordinary candidate is first and real, so this is the mixed declaration a
/// repo actually has rather than one where nothing is anchored.
contract UnanchorableDeploy is ExternalDeploySuites, RainDeployBroadcast {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal pure override returns (DeployCandidate[] memory candidates) {
        candidates = new DeployCandidate[](3);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "compiled-candidate",
                creationCode: ADDRESS_REGISTRY_CREATION_CODE,
                storedDeployedAddress: ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
                storedBytecodeHash: ADDRESS_REGISTRY_BYTECODE_HASH,
                storedRuntimeCode: ADDRESS_REGISTRY_RUNTIME_CODE,
                artifactPath: "src/concrete/AddressRegistry.sol:AddressRegistry",
                dependencies: new address[](0)
            }),
            unanchorableReason: ""
        });
        candidates[1] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "vendored-candidate",
                creationCode: VENDORED_CREATION_CODE,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(VENDORED_CREATION_CODE),
                storedBytecodeHash: keccak256(hex""),
                storedRuntimeCode: hex"",
                // A bare contract name: this repo compiles no such source, so
                // it resolves to no artifact.
                artifactPath: "VendoredDeployable",
                dependencies: new address[](0)
            }),
            unanchorableReason: "Vendored third party deployment: the pinned creation code is the source."
        });
        candidates[2] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "generated-candidate",
                creationCode: ASSEMBLED_CREATION_CODE,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(ASSEMBLED_CREATION_CODE),
                storedBytecodeHash: keccak256(hex"01"),
                storedRuntimeCode: hex"01",
                // Nothing at all, the other shape: a data contract assembled at
                // build time names no file to point anything at.
                artifactPath: "",
                dependencies: new address[](0)
            }),
            unanchorableReason: "Assembled from generated tables: there is no source file to compile."
        });
    }
}
