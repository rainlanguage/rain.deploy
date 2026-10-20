// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {ICloneableFactoryV4} from "rain-factory-pr271-ab0fdca/src/interface/deprecated/ICloneableFactoryV4.sol";
import {LibICloneableFactoryV4} from "rain-factory-pr271-ab0fdca/src/lib/LibICloneableFactoryV4.sol";

import {DeployDependency} from "./LibRainDeploy.sol";

uint256 constant EIP1167_CREATION_CODE_PREFIX_LENGTH = 10;

string constant CLONE_ARTIFACT_PATH = "rain-factory/EIP1167Clone.sol:EIP1167Clone";

string constant CLONE_UNANCHORABLE_REASON = "An EIP-1167 minimal proxy, assembled by the clone factory from the "
    "implementation address. No compiler produces it, so there is no artifact to anchor it to; the implementation "
    "it delegates into is the anchored contract, and because that address is embedded in the proxy's runtime the "
    "recorded code hash is what says which implementation this clone delegates to.";

/// What a clone factory is asked to deploy.
struct CloneTarget {
    /// The `ICloneableFactoryV4` that deploys the clone.
    address factory;
    /// The contract the proxy delegates into.
    address implementation;
    /// The initialization data, passed verbatim to `ICloneableV2.initialize` and hashed into the
    /// open salt.
    bytes data;
    /// The caller-chosen salt, before the factory's open-salt domain tag and `keccak256(data)` are
    /// hashed in with it.
    bytes32 salt;
}

/// One network's clone, as a per-network clone suite records it.
struct CloneNetwork {
    /// The chain id of the network.
    uint256 chainId;
    /// The init data on that network.
    bytes data;
    /// The address recorded for the clone on that network.
    address deployedAddress;
}

/// A clone whose init data differs by network, and therefore whose address does.
struct CloneNetworks {
    /// See `CloneTarget.factory`.
    address factory;
    /// See `CloneTarget.implementation`.
    address implementation;
    /// See `CloneTarget.salt`.
    bytes32 salt;
    /// One entry per network, keyed by chain id.
    CloneNetwork[] networks;
}

/// One contract a repo deploys as an EIP-1167 clone, as a clone repo declares it.
struct CloneDeploy {
    /// The suite key, held to the key alphabet and to uniqueness by
    /// `RainDeploySuitesBase.allSuites` like any other — the candidate this becomes carries it, so
    /// there is no second rule for a clone's key.
    string suite;
    /// See `CloneTarget.factory`.
    address factory;
    /// See `CloneTarget.implementation`.
    address implementation;
    /// The init data on every network.
    bytes data;
    /// Whether the init data is `initData` per network rather than `data` on every network.
    bool initDataPerNetwork;
    /// The init data on the network with the given chain id.
    function(uint256) view returns (bytes memory) initData;
    /// See `CloneTarget.salt`.
    bytes32 salt;
    /// What MUST already be on a network, with exactly this code, before the clone is broadcast
    /// there.
    DeployDependency[] dependencies;
}

/// @title LibRainDeployClone
/// @notice The CLONE mechanism.
library LibRainDeployClone {
    /// Thrown when the clone factory on a network does not derive the address this package derives
    /// for the same clone.
    /// @param network The network whose factory was read, for the refusal to name.
    /// @param factory The factory that was asked.
    /// @param expected The address this package derives for the clone.
    /// @param predicted The address the factory says it would deploy to.
    error CloneFactoryPredictionMismatch(string network, address factory, address expected, address predicted);

    /// Thrown when a clone's factory or implementation is not among the dependencies declared
    /// beside it.
    /// @param dependency The factory or implementation address no declared dependency names.
    error CloneDependencyUndeclared(address dependency);

    /// Thrown when a per-network clone names no network at all.
    error NoCloneNetworks();

    /// Thrown when a per-network clone names one chain id twice, so which init data that network
    /// gets would depend on which entry a reader happened to stop at.
    /// @param chainId The chain id named more than once.
    error DuplicateCloneNetwork(uint256 chainId);

    /// Thrown when a per-network clone is asked for a network it has no entry for.
    /// @param chainId The chain id with no entry.
    error CloneNetworkUndeclared(uint256 chainId);

    /// Thrown by `noInitDataPerNetwork`, the `initData` of a clone whose init data is `data` on
    /// every network.
    /// @param chainId The chain id it was asked for.
    error NoInitDataPerNetwork(uint256 chainId);

    /// The `CloneDeploy.initData` of a clone whose init data is `data` on every network.
    /// @param chainId The chain id asked for.
    /// @return Never returns.
    function noInitDataPerNetwork(uint256 chainId) internal pure returns (bytes memory) {
        revert NoInitDataPerNetwork(chainId);
    }

    /// The clone's creation code.
    /// @param implementation The contract the proxy delegates into.
    /// @return The creation code.
    function cloneCreationCode(address implementation) internal pure returns (bytes memory) {
        return LibICloneableFactoryV4.cloneCreationCode(implementation);
    }

    /// The clone's runtime code.
    /// @param implementation The contract the proxy delegates into.
    /// @return The runtime code, with `implementation` embedded in it.
    function cloneRuntimeCode(address implementation) internal pure returns (bytes memory) {
        bytes memory creation = cloneCreationCode(implementation);
        bytes memory runtime = new bytes(creation.length - EIP1167_CREATION_CODE_PREFIX_LENGTH);
        for (uint256 i = 0; i < runtime.length; i++) {
            runtime[i] = creation[i + EIP1167_CREATION_CODE_PREFIX_LENGTH];
        }
        return runtime;
    }

    /// The code hash a deployed clone reports.
    /// @param implementation The contract the proxy delegates into.
    /// @return `keccak256` of the runtime code.
    function cloneDeployedCodehash(address implementation) internal pure returns (bytes32) {
        return keccak256(cloneRuntimeCode(implementation));
    }

    /// The address the clone lands at — the same one on every network where both the factory and
    /// the implementation are at the same address, which is what deploying both deterministically
    /// buys.
    /// @param target The clone being deployed.
    /// @return The predicted clone address.
    function cloneDeployedAddress(CloneTarget memory target) internal pure returns (address) {
        return LibICloneableFactoryV4.predictCloneAddress(
            target.factory, target.implementation, LibICloneableFactoryV4.effectiveOpenSalt(target.salt, target.data)
        );
    }

    /// Requires the clone's factory AND implementation to be among the declared dependencies.
    /// @param target The clone.
    /// @param dependencies The dependencies declared beside it.
    function checkCloneDependencies(CloneTarget memory target, DeployDependency[] memory dependencies) internal pure {
        bool factoryDeclared = false;
        bool implementationDeclared = false;
        for (uint256 i = 0; i < dependencies.length; i++) {
            if (dependencies[i].deployedAddress == target.factory) {
                factoryDeclared = true;
            }
            if (dependencies[i].deployedAddress == target.implementation) {
                implementationDeclared = true;
            }
        }
        if (!factoryDeclared) {
            revert CloneDependencyUndeclared(target.factory);
        }
        if (!implementationDeclared) {
            revert CloneDependencyUndeclared(target.implementation);
        }
    }

    /// Requires a per-network clone to name at least one network, no chain id twice, and its
    /// factory and implementation among the declared dependencies.
    /// @param clones The per-network clone.
    /// @param dependencies The dependencies declared beside it.
    function checkCloneNetworks(CloneNetworks memory clones, DeployDependency[] memory dependencies) internal pure {
        if (clones.networks.length == 0) {
            revert NoCloneNetworks();
        }
        for (uint256 i = 0; i < clones.networks.length; i++) {
            for (uint256 j = 0; j < i; j++) {
                if (clones.networks[j].chainId == clones.networks[i].chainId) {
                    revert DuplicateCloneNetwork(clones.networks[i].chainId);
                }
            }
        }
        checkCloneDependencies(cloneNetworkTarget(clones, 0), dependencies);
    }

    /// Where a chain id's entry is in a per-network clone.
    /// @param clones The per-network clone.
    /// @param chainId The chain id to find.
    /// @return The index of its entry in `clones.networks`.
    function cloneNetworkIndex(CloneNetworks memory clones, uint256 chainId) internal pure returns (uint256) {
        for (uint256 i = 0; i < clones.networks.length; i++) {
            if (clones.networks[i].chainId == chainId) {
                return i;
            }
        }
        revert CloneNetworkUndeclared(chainId);
    }

    /// The `CloneTarget` one entry of a per-network clone describes.
    /// @param clones The per-network clone.
    /// @param index The entry's index in `clones.networks`.
    /// @return The target.
    function cloneNetworkTarget(CloneNetworks memory clones, uint256 index) internal pure returns (CloneTarget memory) {
        return CloneTarget({
            factory: clones.factory,
            implementation: clones.implementation,
            data: clones.networks[index].data,
            salt: clones.salt
        });
    }

    /// The CLONE mechanism as a `LibRainDeploy.deployStepToNetworks` step.
    /// @param vm The Vm instance to broadcast with.
    /// @param network The network being deployed to, for a refusal to name.
    /// @param deployer The deployer address to broadcast as.
    /// @param targetData The step data.
    /// @return The address the factory deployed the clone to.
    function cloneDeployStep(Vm vm, string memory network, address deployer, bytes memory targetData)
        internal
        returns (address)
    {
        CloneTarget memory target = abi.decode(targetData, (CloneTarget));

        console2.log(" - Clone Factory:", target.factory);
        address expectedAddress = cloneDeployedAddress(target);
        address factoryPredictedAddress = ICloneableFactoryV4(target.factory)
            .predictDeterministicAddressOpenSalt(target.implementation, target.data, target.salt);
        if (factoryPredictedAddress != expectedAddress) {
            revert CloneFactoryPredictionMismatch(network, target.factory, expectedAddress, factoryPredictedAddress);
        }

        console2.log(" - Cloning implementation:", target.implementation);
        vm.startBroadcast(deployer);
        address cloneDeployedAddr = ICloneableFactoryV4(target.factory)
            .cloneDeterministicOpenSalt(target.implementation, target.data, target.salt);
        vm.stopBroadcast();
        return cloneDeployedAddr;
    }
}
