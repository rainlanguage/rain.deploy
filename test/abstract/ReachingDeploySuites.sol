// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeployDependency,
    DeploySuite,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ExternalDeployment, RainDeployDeclarationChecks} from "../../src/abstract/RainDeployDeclarationChecks.sol";
import {CloneDeploy, LibRainDeployClone} from "../../src/lib/LibRainDeployClone.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../../src/lib/LibRainDeployMechanism.sol";
import {MockCloneFactory} from "../concrete/MockCloneFactory.sol";
import {MockDeployable} from "../concrete/MockDeployable.sol";
import {
    MOCK_DEPLOYABLE_ADDRESS,
    MOCK_EXTERNAL_ADDRESS,
    MockReachingDeployable
} from "../concrete/MockReachingDeployable.sol";
import {exampleCloneFactory} from "./ExampleCloneDeploys.sol";

bytes constant MOCK_EXTERNAL_RUNTIME_CODE = hex"00c0ffee";

enum DeclarationDefect {
    None,
    ArtifactPathOfOtherSource,
    ZeroDependency,
    RepeatedDependency,
    AdjacentRepeatedDependency,
    UndeclaredSibling,
    UndeclaredExternal,
    UndeclaredMechanismDependency,
    UnreachedDependency,
    UnknownDependency,
    SiblingRuntimeCode,
    ExternalRuntimeCode,
    RuntimeCodeAtEip170,
    RuntimeCodeOverEip170
}

/// @title ReachingDeploySuites
/// @notice A declaration whose suites embed a sibling, an external deployment
/// with a leading zero byte, and a clone factory reached only through
/// mechanism data, with one `DeclarationDefect` applied to its candidates.
abstract contract ReachingDeploySuites is RainDeployDeclarationChecks {
    DeclarationDefect internal sDefect;
    string internal sWorkflow = "test/fixture-dispatch/dispatchable.yaml";

    function leafSuite(string memory key) internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: key,
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: MOCK_DEPLOYABLE_ADDRESS,
            storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
            storedRuntimeCode: type(MockDeployable).runtimeCode,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new DeployDependency[](0),
            mechanismData: ""
        });
    }

    function reachingSuite(string memory key) internal pure returns (DeploySuite memory) {
        DeployDependency[] memory deps = new DeployDependency[](2);
        deps[0] =
            DeployDependency({deployedAddress: MOCK_DEPLOYABLE_ADDRESS, runtimeCode: type(MockDeployable).runtimeCode});
        deps[1] = DeployDependency({deployedAddress: MOCK_EXTERNAL_ADDRESS, runtimeCode: MOCK_EXTERNAL_RUNTIME_CODE});
        return DeploySuite({
            suite: key,
            creationCode: type(MockReachingDeployable).creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockReachingDeployable).creationCode),
            storedBytecodeHash: keccak256(type(MockReachingDeployable).runtimeCode),
            storedRuntimeCode: type(MockReachingDeployable).runtimeCode,
            artifactPath: "test/concrete/MockReachingDeployable.sol:MockReachingDeployable",
            dependencies: deps,
            mechanismData: ""
        });
    }

    function cloneCandidate() internal view returns (DeployCandidate memory) {
        DeployDependency[] memory deps = new DeployDependency[](2);
        deps[0] =
            DeployDependency({deployedAddress: exampleCloneFactory(), runtimeCode: type(MockCloneFactory).runtimeCode});
        deps[1] =
            DeployDependency({deployedAddress: MOCK_DEPLOYABLE_ADDRESS, runtimeCode: type(MockDeployable).runtimeCode});
        return LibRainDeployMechanism.cloneCandidate(
            CloneDeploy({
                suite: "mock-clone",
                factory: exampleCloneFactory(),
                implementation: MOCK_DEPLOYABLE_ADDRESS,
                data: "",
                initDataPerNetwork: false,
                initData: LibRainDeployClone.noInitDataPerNetwork,
                salt: bytes32(uint256(1)),
                dependencies: deps
            }),
            new uint256[](0)
        );
    }

    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure virtual override returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = leafSuite("mock-deployable@0_0_1");
        return suites;
    }

    /// @inheritdoc RainDeploySuitesBase
    function candidateSuites() internal view override returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](3);
        candidates[0] = DeployCandidate({snapshot: leafSuite("mock-deployable"), unanchorableReason: ""});
        candidates[1] = DeployCandidate({snapshot: reachingSuite("mock-reaching-deployable"), unanchorableReason: ""});
        candidates[2] = cloneCandidate();

        DeploySuite memory leaf = candidates[0].snapshot;
        DeploySuite memory reaching = candidates[1].snapshot;
        DeclarationDefect defect = sDefect;
        if (defect == DeclarationDefect.ArtifactPathOfOtherSource) {
            reaching.artifactPath = leaf.artifactPath;
        } else if (defect == DeclarationDefect.ZeroDependency) {
            leaf.dependencies = new DeployDependency[](1);
        } else if (defect == DeclarationDefect.RepeatedDependency) {
            DeployDependency[] memory deps = new DeployDependency[](3);
            deps[0] = reaching.dependencies[0];
            deps[1] = reaching.dependencies[1];
            deps[2] = reaching.dependencies[0];
            reaching.dependencies = deps;
        } else if (defect == DeclarationDefect.AdjacentRepeatedDependency) {
            DeployDependency[] memory deps = new DeployDependency[](3);
            deps[0] = reaching.dependencies[0];
            deps[1] = reaching.dependencies[1];
            deps[2] = reaching.dependencies[1];
            reaching.dependencies = deps;
        } else if (defect == DeclarationDefect.UndeclaredSibling) {
            DeployDependency[] memory deps = new DeployDependency[](1);
            deps[0] = reaching.dependencies[1];
            reaching.dependencies = deps;
        } else if (defect == DeclarationDefect.UndeclaredExternal) {
            DeployDependency[] memory deps = new DeployDependency[](1);
            deps[0] = reaching.dependencies[0];
            reaching.dependencies = deps;
        } else if (defect == DeclarationDefect.UndeclaredMechanismDependency) {
            DeployDependency[] memory deps = new DeployDependency[](1);
            deps[0] = candidates[2].snapshot.dependencies[1];
            candidates[2].snapshot.dependencies = deps;
        } else if (defect == DeclarationDefect.UnreachedDependency) {
            leaf.dependencies = new DeployDependency[](1);
            leaf.dependencies[0] = DeployDependency({
                deployedAddress: reaching.storedDeployedAddress, runtimeCode: reaching.storedRuntimeCode
            });
        } else if (defect == DeclarationDefect.UnknownDependency) {
            leaf.dependencies = new DeployDependency[](1);
            leaf.dependencies[0] = DeployDependency({deployedAddress: address(0xdead), runtimeCode: ""});
        } else if (defect == DeclarationDefect.SiblingRuntimeCode) {
            reaching.dependencies[0].runtimeCode = type(MockReachingDeployable).runtimeCode;
        } else if (defect == DeclarationDefect.ExternalRuntimeCode) {
            reaching.dependencies[1].runtimeCode = hex"00";
        } else if (defect == DeclarationDefect.RuntimeCodeAtEip170) {
            leaf.storedRuntimeCode = new bytes(0x6000);
        } else if (defect == DeclarationDefect.RuntimeCodeOverEip170) {
            leaf.storedRuntimeCode = new bytes(0x6001);
        }
        return candidates;
    }

    /// @inheritdoc RainDeployDeclarationChecks
    function sourceCreationCode(string memory suite) internal pure override returns (bytes memory) {
        bytes32 key = keccak256(bytes(suite));
        if (key == keccak256("mock-deployable")) return type(MockDeployable).creationCode;
        if (key == keccak256("mock-reaching-deployable")) return type(MockReachingDeployable).creationCode;
        revert(string.concat("no source for suite: ", suite));
    }

    /// @inheritdoc RainDeployDeclarationChecks
    function externalDeployments() internal pure override returns (ExternalDeployment[] memory) {
        ExternalDeployment[] memory externals = new ExternalDeployment[](2);
        externals[0] = ExternalDeployment({
            deployedAddress: MOCK_EXTERNAL_ADDRESS, codeHash: keccak256(MOCK_EXTERNAL_RUNTIME_CODE)
        });
        externals[1] = ExternalDeployment({
            deployedAddress: exampleCloneFactory(), codeHash: keccak256(type(MockCloneFactory).runtimeCode)
        });
        return externals;
    }

    /// @inheritdoc RainDeployDeclarationChecks
    function dispatchWorkflow() internal view virtual override returns (string memory) {
        return sWorkflow;
    }
}
