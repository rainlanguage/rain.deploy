// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {RainDeployCloneSuitesBase} from "../../src/abstract/RainDeployCloneSuitesBase.sol";
import {DeployMechanism, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {CLONE_ARTIFACT_PATH, CloneDeploy, LibRainDeployClone} from "../../src/lib/LibRainDeployClone.sol";
import {DeployDependency, LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {MockCloneFactory} from "../concrete/MockCloneFactory.sol";
import {MockCloneable} from "../concrete/MockCloneable.sol";
import {
    BYTECODE_HASH as EXAMPLE_CLONE_BYTECODE_HASH,
    CREATION_CODE as EXAMPLE_CLONE_CREATION_CODE,
    DEPENDENCIES as EXAMPLE_CLONE_DEPENDENCIES,
    DEPLOYED_ADDRESS as EXAMPLE_CLONE_DEPLOYED_ADDRESS,
    MECHANISM_DATA as EXAMPLE_CLONE_MECHANISM_DATA,
    RUNTIME_CODE as EXAMPLE_CLONE_RUNTIME_CODE
} from "../fixture-clone-record/0_0_1/ExampleClone.sol";

/// The address the Zoltu factory derives for `MockCloneFactory`, which is where a test puts it.
/// @return The factory's deterministic address.
function exampleCloneFactory() pure returns (address) {
    return LibRainDeploy.zoltuAddress(type(MockCloneFactory).creationCode);
}

/// The address the Zoltu factory derives for `MockCloneable`, the implementation the example clones
/// delegate into.
/// @return The implementation's deterministic address.
function exampleCloneImplementation() pure returns (address) {
    return LibRainDeploy.zoltuAddress(type(MockCloneable).creationCode);
}

/// The factory and the implementation every example clone is made from, declared as dependencies
/// with the runtime code each MUST hold.
/// @return The factory, then the implementation.
function exampleCloneDependencies() pure returns (DeployDependency[] memory) {
    DeployDependency[] memory dependencies = new DeployDependency[](2);
    dependencies[0] =
        DeployDependency({deployedAddress: exampleCloneFactory(), runtimeCode: type(MockCloneFactory).runtimeCode});
    dependencies[1] =
        DeployDependency({deployedAddress: exampleCloneImplementation(), runtimeCode: type(MockCloneable).runtimeCode});
    return dependencies;
}

string constant EXAMPLE_CLONE_RECORD_ROOT = "test/fixture-clone-record";

string constant EXAMPLE_CLONE_RELEASE_TAG = "0_0_1";

string constant EXAMPLE_CLONE_RECORD_CONTRACT = "ExampleClone";

/// The declaration the committed release record of `example-clone` was written from.
/// @return The release's clone declaration.
function exampleCloneRelease() pure returns (CloneDeploy memory) {
    return CloneDeploy({
        suite: "example-clone@0_0_1",
        factory: exampleCloneFactory(),
        implementation: exampleCloneImplementation(),
        data: "",
        initDataPerNetwork: false,
        initData: LibRainDeployClone.noInitDataPerNetwork,
        salt: bytes32(uint256(3)),
        dependencies: exampleCloneDependencies()
    });
}

/// @title ExampleCloneDeploys
/// @notice A clone deploy repo's declaration, as the abstracts see it.
abstract contract ExampleCloneDeploys is RainDeployCloneSuitesBase {
    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = DeploySuite({
            suite: "example-clone@0_0_1",
            creationCode: EXAMPLE_CLONE_CREATION_CODE,
            storedDeployedAddress: EXAMPLE_CLONE_DEPLOYED_ADDRESS,
            storedBytecodeHash: EXAMPLE_CLONE_BYTECODE_HASH,
            storedRuntimeCode: EXAMPLE_CLONE_RUNTIME_CODE,
            artifactPath: CLONE_ARTIFACT_PATH,
            dependencies: abi.decode(EXAMPLE_CLONE_DEPENDENCIES, (DeployDependency[])),
            mechanism: DeployMechanism.Clone,
            mechanismData: EXAMPLE_CLONE_MECHANISM_DATA,
            describedByMeta: ""
        });
        return suites;
    }

    /// @inheritdoc RainDeployCloneSuitesBase
    function cloneDeploys() internal pure virtual override returns (CloneDeploy[] memory) {
        CloneDeploy[] memory clones = new CloneDeploy[](2);
        clones[0] = CloneDeploy({
            suite: "example-clone",
            factory: exampleCloneFactory(),
            implementation: exampleCloneImplementation(),
            data: "",
            initDataPerNetwork: false,
            initData: LibRainDeployClone.noInitDataPerNetwork,
            salt: bytes32(uint256(1)),
            dependencies: exampleCloneDependencies()
        });
        clones[1] = CloneDeploy({
            suite: "example-clone-second-salt",
            factory: exampleCloneFactory(),
            implementation: exampleCloneImplementation(),
            data: hex"abcd",
            initDataPerNetwork: false,
            initData: LibRainDeployClone.noInitDataPerNetwork,
            salt: bytes32(uint256(2)),
            dependencies: exampleCloneDependencies()
        });
        return clones;
    }
}
