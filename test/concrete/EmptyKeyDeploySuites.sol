// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    DeployCandidate,
    DeployDependency,
    DeployDeclaration,
    DeploySuite,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {MockDeployableV2} from "./MockDeployableV2.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {
    BYTECODE_HASH as CONFIG_REGISTRY_BYTECODE_HASH,
    CREATION_CODE as CONFIG_REGISTRY_CREATION_CODE,
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "../../src/generated/candidate/ConfigRegistry.sol";

/// @title EmptyKeyDeploySuites
/// A declaration whose CANDIDATE is keyed on the empty string — the value an
/// unset `DEPLOYMENT_SUITE` arrives at `suiteByName` as.
///
/// Unique, anchored to source and correctly pinned; the key is the only thing
/// wrong with it, so nothing else in the registry can be what refuses it.
///
/// The empty key sits SECOND, behind a released suite that is spelled properly,
/// for two reasons. A check that only ever looked at the first entry answers
/// this declaration as if it were fine, and the position the refusal reports is
/// the only handle on which entry is at fault when the key itself is empty.
///
/// `MockDeployableV2` rather than the registry a second time: this is the
/// contract the empty key would select, and it exists on no chain, so a reader
/// of this fixture can see that the suite an unset variable reaches is a real
/// deployable one and not a harmless duplicate of the one beside it.
contract EmptyKeyDeploySuites is ExternalDeploySuites {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory declared = LibRainDeployDeclaration.zoltu();
        declared.released = declaredReleased();
        declared.candidates = declaredCandidates();
        return declared;
    }


    function declaredReleased() internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = DeploySuite({
            networks: new string[](0),
            suite: "config-registry@0_0_1",
            creationCode: CONFIG_REGISTRY_CREATION_CODE,
            storedDeployedAddress: CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            storedBytecodeHash: CONFIG_REGISTRY_BYTECODE_HASH,
            storedRuntimeCode: CONFIG_REGISTRY_RUNTIME_CODE,
            artifactPath: "src/concrete/ConfigRegistry.sol:ConfigRegistry",
            dependencies: new DeployDependency[](0),
            mechanismData: ""
        });
        return suites;
    }

    function declaredCandidates() internal pure returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                networks: new string[](0),
                suite: "",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
                dependencies: new DeployDependency[](0),
                mechanismData: ""
            }),
            unanchorableReason: ""
        });
        return candidates;
    }
}
