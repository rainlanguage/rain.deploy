// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {RainDeployCloneSuitesBase} from "../../src/abstract/RainDeployCloneSuitesBase.sol";
import {DeployMechanism, DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {
    CLONE_ARTIFACT_PATH,
    CloneDeploy,
    CloneNetwork,
    CloneNetworks,
    CloneTarget,
    LibRainDeployClone
} from "../../src/lib/LibRainDeployClone.sol";
import {DeployDependency, LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {exampleCloneDependencies, exampleCloneFactory, exampleCloneImplementation} from "./ExampleCloneDeploys.sol";
import {
    BYTECODE_HASH as PER_NETWORK_CLONE_BYTECODE_HASH,
    CREATION_CODE as PER_NETWORK_CLONE_CREATION_CODE,
    DEPENDENCIES as PER_NETWORK_CLONE_DEPENDENCIES,
    MECHANISM_DATA as PER_NETWORK_CLONE_MECHANISM_DATA,
    RUNTIME_CODE as PER_NETWORK_CLONE_RUNTIME_CODE
} from "../fixture-clone-per-network-record/0_0_1/PerNetworkClone.sol";

/// Thrown by `perNetworkCloneAdmin` for a chain id it names no admin for.
/// @param chainId The chain id.
error NoPerNetworkCloneAdmin(uint256 chainId);

uint256 constant PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID = 42161;

uint256 constant PER_NETWORK_CLONE_POLYGON_CHAIN_ID = 137;

address constant PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN = address(0xA1A1a1a1A1A1A1A1A1a1a1a1a1a1A1A1a1A1a1a1);

address constant PER_NETWORK_CLONE_POLYGON_ADMIN = address(0xb2b2b2b2b2B2b2B2B2b2b2B2B2b2B2B2b2b2b2b2);

string constant PER_NETWORK_CLONE_RECORD_ROOT = "test/fixture-clone-per-network-record";

string constant PER_NETWORK_CLONE_RELEASE_TAG = "0_0_1";

string constant PER_NETWORK_CLONE_RECORD_CONTRACT = "PerNetworkClone";

/// The admin a network's clone is initialized with.
/// @param chainId The network's chain id.
/// @return The admin on that network.
function perNetworkCloneAdmin(uint256 chainId) pure returns (address) {
    if (chainId == PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID) {
        return PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN;
    }
    if (chainId == PER_NETWORK_CLONE_POLYGON_CHAIN_ID) {
        return PER_NETWORK_CLONE_POLYGON_ADMIN;
    }
    revert NoPerNetworkCloneAdmin(chainId);
}

/// The per-network init data.
/// @param chainId The network's chain id.
/// @return The init data on that network.
function perNetworkCloneInitData(uint256 chainId) pure returns (bytes memory) {
    return abi.encode(perNetworkCloneAdmin(chainId));
}

/// The chain ids of `PerNetworkCloneDeploys.supportedNetworks()`, in order, as literals.
/// @return Arbitrum One's, then Polygon's.
function perNetworkCloneChainIds() pure returns (uint256[] memory) {
    uint256[] memory chainIds = new uint256[](2);
    chainIds[0] = PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID;
    chainIds[1] = PER_NETWORK_CLONE_POLYGON_CHAIN_ID;
    return chainIds;
}

/// A per-network clone declaration over the example factory and implementation.
/// @param suite The suite key.
/// @param salt The salt.
/// @return The clone declaration.
function perNetworkClone(string memory suite, bytes32 salt) pure returns (CloneDeploy memory) {
    return CloneDeploy({
        suite: suite,
        factory: exampleCloneFactory(),
        implementation: exampleCloneImplementation(),
        data: "",
        initDataPerNetwork: true,
        initData: perNetworkCloneInitData,
        salt: salt,
        dependencies: exampleCloneDependencies()
    });
}

/// The declaration the committed release record of `per-network-clone` was written from.
/// @return The release's clone declaration.
function perNetworkCloneRelease() pure returns (CloneDeploy memory) {
    return perNetworkClone("per-network-clone@0_0_1", bytes32(uint256(5)));
}

/// A per-network release with only its first recorded network.
/// @param release The release.
/// @return The release, recording its first network alone.
function onlyFirstRecordedNetwork(DeploySuite memory release) pure returns (DeploySuite memory) {
    CloneNetworks memory clones = abi.decode(release.mechanismData, (CloneNetworks));
    CloneNetwork memory first = clones.networks[0];
    clones.networks = new CloneNetwork[](1);
    clones.networks[0] = first;
    release.mechanismData = abi.encode(clones);
    return release;
}

/// Where the `per-network-clone` release's factory, implementation and salt put a clone initialized
/// with `data`, derived from a `CloneTarget` built here rather than through any per-network code.
/// @param data The clone's init data.
/// @return The clone address.
function perNetworkCloneReleaseAddressAt(bytes memory data) pure returns (address) {
    CloneDeploy memory release = perNetworkCloneRelease();
    return LibRainDeployClone.cloneDeployedAddress(
        CloneTarget({factory: release.factory, implementation: release.implementation, data: data, salt: release.salt})
    );
}

/// Where the `per-network-clone` release puts a clone initialized with a network's admin.
/// @param chainId The network's chain id.
/// @return The clone address.
function perNetworkCloneReleaseAddress(uint256 chainId) pure returns (address) {
    return perNetworkCloneReleaseAddressAt(abi.encode(perNetworkCloneAdmin(chainId)));
}

/// `perNetworkCloneReleaseAddress` on Arbitrum One, then on Polygon.
/// @return The two clone addresses.
function perNetworkCloneReleaseAddresses() pure returns (address[] memory) {
    address[] memory addresses = new address[](2);
    addresses[0] = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
    addresses[1] = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
    return addresses;
}

/// Etches a release's dependencies, and its runtime code at each of `addresses`, persistent across forks.
/// @param vm The cheatcodes.
/// @param release The release.
/// @param addresses Where its clone is live.
function etchPerNetworkCloneRelease(Vm vm, DeploySuite memory release, address[] memory addresses) {
    for (uint256 i = 0; i < release.dependencies.length; i++) {
        vm.etch(release.dependencies[i].deployedAddress, release.dependencies[i].runtimeCode);
        vm.makePersistent(release.dependencies[i].deployedAddress);
    }
    for (uint256 i = 0; i < addresses.length; i++) {
        vm.etch(addresses[i], release.storedRuntimeCode);
        vm.makePersistent(addresses[i]);
    }
}

/// A release recording its first network alone, as the one suite to check.
/// @param release The release.
/// @return The suites.
function onlyFirstRecordedNetworkSuites(DeploySuite memory release) pure returns (DeploySuite[] memory) {
    DeploySuite[] memory suites = new DeploySuite[](1);
    suites[0] = onlyFirstRecordedNetwork(release);
    return suites;
}

/// @title PerNetworkCloneDeploys
/// @notice A clone deploy repo whose clone is initialized with a different admin on each network —
/// an issuer's authoriser whose admin is that chain's Safe — so the clone lands at a different
/// address on each.
abstract contract PerNetworkCloneDeploys is RainDeployCloneSuitesBase {
    /// @inheritdoc RainDeploySuitesBase
    function supportedNetworks() internal view virtual override returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        return networks;
    }

    /// @inheritdoc RainDeploySuitesBase
    function releasedSuites() internal pure virtual override returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = DeploySuite({
            suite: "per-network-clone@0_0_1",
            creationCode: PER_NETWORK_CLONE_CREATION_CODE,
            storedDeployedAddress: address(0),
            storedBytecodeHash: PER_NETWORK_CLONE_BYTECODE_HASH,
            storedRuntimeCode: PER_NETWORK_CLONE_RUNTIME_CODE,
            artifactPath: CLONE_ARTIFACT_PATH,
            dependencies: abi.decode(PER_NETWORK_CLONE_DEPENDENCIES, (DeployDependency[])),
            mechanism: DeployMechanism.ClonePerNetwork,
            mechanismData: PER_NETWORK_CLONE_MECHANISM_DATA,
            describedByMeta: ""
        });
        return suites;
    }

    /// @inheritdoc RainDeployCloneSuitesBase
    function cloneDeploys() internal pure virtual override returns (CloneDeploy[] memory) {
        CloneDeploy[] memory clones = new CloneDeploy[](1);
        clones[0] = perNetworkClone("per-network-clone", bytes32(uint256(4)));
        return clones;
    }
}
