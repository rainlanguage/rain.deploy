// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {ICloneableFactoryV4} from "rain-factory-0.1.30/src/interface/ICloneableFactoryV4.sol";

import {DeployCandidate, DeployMechanism, DeploySuite} from "../abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy, NetworkDeploys, SupportedNetwork} from "./LibRainDeploy.sol";
import {
    CLONE_ARTIFACT_PATH,
    CLONE_UNANCHORABLE_REASON,
    CloneDeploy,
    CloneNetwork,
    CloneNetworks,
    CloneTarget,
    LibRainDeployClone
} from "./LibRainDeployClone.sol";

/// Thrown when the state snapshot taken around a local deploy could not be
/// reverted. A local deploy plants code at the derived address, clears its
/// nonce and etches the suite's declared dependencies; if that cannot be
/// undone, every later local deploy reads state this one created, and the
/// chain-anchored checks compare a locally planted deployment against itself.
/// There is no safe way to continue.
/// @param suite The suite deployed locally when the revert failed.
/// @param snapshotId The snapshot that could not be reverted.
error DerivationSnapshotRevertFailed(string suite, uint256 snapshotId);

/// Thrown when the pure `LibRainDeploy.zoltuAddress` formula and an actual deploy through the
/// etched Zoltu factory bytecode disagree about where a creation code lands.
/// @param suite The suite whose creation code was being derived.
/// @param formulaAddress The address `zoltuAddress` computed.
/// @param factoryAddress The address the factory bytecode actually deployed to.
error ZoltuDerivationMismatch(string suite, address formulaAddress, address factoryAddress);

/// Thrown when a clone suite's declared factory, run locally, puts the clone somewhere other than
/// the address `rain-factory`'s formula derives.
/// @param suite The suite being derived.
/// @param formulaAddress The address `LibRainDeployClone.cloneDeployedAddress` computed.
/// @param factoryAddress The address the declared factory actually deployed to.
error CloneDerivationMismatch(string suite, address formulaAddress, address factoryAddress);

/// Thrown when a clone suite's `creationCode` is not the EIP-1167 creation code for the
/// implementation its `mechanismData` names.
/// @param suite The suite being derived.
error CloneCreationCodeMismatch(string suite);

/// Thrown when a Zoltu suite carries mechanism data.
/// @param suite The suite carrying the data.
error UnexpectedMechanismData(string suite);

/// Thrown when a `ClonePerNetwork` suite carries a `storedDeployedAddress`.
/// @param suite The suite carrying the address.
/// @param storedDeployedAddress The address it carries.
error UnexpectedStoredDeployedAddress(string suite, address storedDeployedAddress);

/// Thrown when a clone declaration sets `initDataPerNetwork` and also declares `data` for every
/// network.
/// @param suite The declaration's suite key.
error CloneDataAmbiguous(string suite);

/// @title LibRainDeployMechanism
/// @notice The one place anything dispatches on a suite's `DeployMechanism`.
library LibRainDeployMechanism {
    /// Requires a Zoltu suite to carry no mechanism data.
    /// @param suite The Zoltu suite.
    function checkZoltuMechanismData(DeploySuite memory suite) internal pure {
        if (suite.mechanismData.length != 0) {
            revert UnexpectedMechanismData(suite.suite);
        }
    }

    /// A clone suite's `CloneTarget`, with its factory and implementation held to being declared
    /// dependencies of the same suite.
    /// @param suite A suite whose mechanism is `Clone`.
    /// @return The decoded target.
    function cloneTarget(DeploySuite memory suite) internal pure returns (CloneTarget memory) {
        CloneTarget memory target = abi.decode(suite.mechanismData, (CloneTarget));
        LibRainDeployClone.checkCloneDependencies(target, suite.dependencies);
        return target;
    }

    /// A per-network clone suite's `CloneNetworks`, held to `LibRainDeployClone.checkCloneNetworks`
    /// and to carrying no `storedDeployedAddress`.
    /// @param suite A suite whose mechanism is `ClonePerNetwork`.
    /// @return The decoded per-network clone.
    function cloneNetworks(DeploySuite memory suite) internal pure returns (CloneNetworks memory) {
        if (suite.storedDeployedAddress != address(0)) {
            revert UnexpectedStoredDeployedAddress(suite.suite, suite.storedDeployedAddress);
        }
        CloneNetworks memory clones = abi.decode(suite.mechanismData, (CloneNetworks));
        LibRainDeployClone.checkCloneNetworks(clones, suite.dependencies);
        return clones;
    }

    /// The `CloneTarget` a clone suite deploys on one network.
    /// @param suite A suite whose mechanism is `Clone` or `ClonePerNetwork`.
    /// @param chainId The network's chain id.
    /// @return The target on that network.
    function cloneTargetOn(DeploySuite memory suite, uint256 chainId) internal pure returns (CloneTarget memory) {
        if (suite.mechanism == DeployMechanism.ClonePerNetwork) {
            CloneNetworks memory clones = cloneNetworks(suite);
            return LibRainDeployClone.cloneNetworkTarget(clones, LibRainDeployClone.cloneNetworkIndex(clones, chainId));
        }
        return cloneTarget(suite);
    }

    /// The address a suite's mechanism puts it at on one network.
    /// @param suite The suite.
    /// @param chainId The network's chain id.
    /// @return The derived address on that network.
    function deployedAddress(DeploySuite memory suite, uint256 chainId) internal pure returns (address) {
        if (suite.mechanism == DeployMechanism.Zoltu) {
            checkZoltuMechanismData(suite);
            return LibRainDeploy.zoltuAddress(suite.creationCode);
        }
        return LibRainDeployClone.cloneDeployedAddress(cloneTargetOn(suite, chainId));
    }

    /// What a suite's mechanism step is handed on one network.
    /// @param suite The suite.
    /// @param chainId The network's chain id.
    /// @return The step data on that network.
    function deployStepData(DeploySuite memory suite, uint256 chainId) internal pure returns (bytes memory) {
        if (suite.mechanism == DeployMechanism.Zoltu) {
            checkZoltuMechanismData(suite);
            return suite.creationCode;
        }
        return abi.encode(cloneTargetOn(suite, chainId));
    }

    /// A suite's mechanism as a `LibRainDeploy.deployStepToNetworks` step.
    /// @param suite The suite.
    /// @return The step.
    function deployStep(DeploySuite memory suite)
        internal
        pure
        returns (function(Vm, string memory, address, bytes memory) internal returns (address))
    {
        if (suite.mechanism == DeployMechanism.Zoltu) {
            return LibRainDeploy.zoltuDeployStep;
        }
        return LibRainDeployClone.cloneDeployStep;
    }

    /// Every address a suite's mechanism derives for it, in the suite's address order.
    /// @param suite The suite.
    /// @return The derived addresses.
    function deployedAddresses(DeploySuite memory suite) internal pure returns (address[] memory) {
        if (suite.mechanism == DeployMechanism.ClonePerNetwork) {
            CloneNetworks memory clones = cloneNetworks(suite);
            address[] memory perNetwork = new address[](clones.networks.length);
            for (uint256 i = 0; i < clones.networks.length; i++) {
                perNetwork[i] =
                    LibRainDeployClone.cloneDeployedAddress(LibRainDeployClone.cloneNetworkTarget(clones, i));
            }
            return perNetwork;
        }
        address[] memory addresses = new address[](1);
        addresses[0] = deployedAddress(suite, 0);
        return addresses;
    }

    /// Every address a suite RECORDS for itself, in the suite's address order.
    /// @param suite The suite.
    /// @return The recorded addresses.
    function recordedAddresses(DeploySuite memory suite) internal pure returns (address[] memory) {
        if (suite.mechanism == DeployMechanism.ClonePerNetwork) {
            CloneNetworks memory clones = cloneNetworks(suite);
            address[] memory perNetwork = new address[](clones.networks.length);
            for (uint256 i = 0; i < clones.networks.length; i++) {
                perNetwork[i] = clones.networks[i].deployedAddress;
            }
            return perNetwork;
        }
        address[] memory addresses = new address[](1);
        addresses[0] = suite.storedDeployedAddress;
        return addresses;
    }

    /// The address a suite RECORDS for itself on one network.
    /// @param suite The suite.
    /// @param chainId The network's chain id.
    /// @return The recorded address on that network.
    function recordedAddress(DeploySuite memory suite, uint256 chainId) internal pure returns (address) {
        if (suite.mechanism == DeployMechanism.ClonePerNetwork) {
            CloneNetworks memory clones = cloneNetworks(suite);
            return clones.networks[LibRainDeployClone.cloneNetworkIndex(clones, chainId)].deployedAddress;
        }
        return suite.storedDeployedAddress;
    }

    /// The chain id each of a suite's addresses is for, in the suite's address order.
    /// @param suite The suite.
    /// @return The chain ids.
    function addressChainIds(DeploySuite memory suite) internal pure returns (uint256[] memory) {
        if (suite.mechanism != DeployMechanism.ClonePerNetwork) {
            return new uint256[](0);
        }
        CloneNetworks memory clones = cloneNetworks(suite);
        uint256[] memory chainIds = new uint256[](clones.networks.length);
        for (uint256 i = 0; i < clones.networks.length; i++) {
            chainIds[i] = clones.networks[i].chainId;
        }
        return chainIds;
    }

    /// A per-network clone suite with an entry for every network its candidate has one for.
    /// @param suite The suite.
    /// @param candidate The candidate whose init data the suite's unrecorded networks take.
    /// @return The suite, with the candidate's networks it lacks.
    function withUnrecordedNetworks(DeploySuite memory suite, DeploySuite memory candidate)
        internal
        pure
        returns (DeploySuite memory)
    {
        if (
            suite.mechanism != DeployMechanism.ClonePerNetwork || candidate.mechanism != DeployMechanism.ClonePerNetwork
        ) {
            return suite;
        }
        CloneNetworks memory clones = cloneNetworks(suite);
        CloneNetwork[] memory declared = cloneNetworks(candidate).networks;
        uint256 recorded = clones.networks.length;
        CloneNetwork[] memory networks = new CloneNetwork[](recorded + declared.length);
        for (uint256 i = 0; i < recorded; i++) {
            networks[i] = clones.networks[i];
        }
        uint256 count = recorded;
        for (uint256 i = 0; i < declared.length; i++) {
            if (!hasChainId(networks, recorded, declared[i].chainId)) {
                networks[count] =
                    CloneNetwork({chainId: declared[i].chainId, data: declared[i].data, deployedAddress: address(0)});
                count++;
            }
        }
        clones.networks = new CloneNetwork[](count);
        for (uint256 i = 0; i < count; i++) {
            clones.networks[i] = networks[i];
        }
        for (uint256 i = recorded; i < count; i++) {
            clones.networks[i].deployedAddress =
                LibRainDeployClone.cloneDeployedAddress(LibRainDeployClone.cloneNetworkTarget(clones, i));
        }
        return DeploySuite({
            suite: suite.suite,
            creationCode: suite.creationCode,
            storedDeployedAddress: suite.storedDeployedAddress,
            storedBytecodeHash: suite.storedBytecodeHash,
            storedRuntimeCode: suite.storedRuntimeCode,
            artifactPath: suite.artifactPath,
            dependencies: suite.dependencies,
            mechanism: suite.mechanism,
            mechanismData: abi.encode(clones)
        });
    }

    /// Whether one of the first `count` entries of a list of networks is for a chain id.
    /// @param networks The list.
    /// @param count How many of its leading entries to look at.
    /// @param chainId The chain id looked for.
    /// @return Whether an entry below `count` has that chain id.
    function hasChainId(CloneNetwork[] memory networks, uint256 count, uint256 chainId) internal pure returns (bool) {
        for (uint256 i = 0; i < count; i++) {
            if (networks[i].chainId == chainId) {
                return true;
            }
        }
        return false;
    }

    /// Runs a suite's mechanism on the local EVM and returns where it landed, each address
    /// cross-checked against the formula's.
    /// @param vm The Vm instance to etch with.
    /// @param suite The suite to deploy.
    /// @return Where the mechanism deployed it, in the suite's address order — the derived
    /// addresses.
    function deployLocally(Vm vm, DeploySuite memory suite) internal returns (address[] memory) {
        address[] memory deployed = deployedAddresses(suite);

        for (uint256 i = 0; i < suite.dependencies.length; i++) {
            vm.etch(suite.dependencies[i].deployedAddress, suite.dependencies[i].runtimeCode);
        }

        if (suite.mechanism == DeployMechanism.Zoltu) {
            vm.etch(deployed[0], hex"");
            vm.resetNonce(deployed[0]);
            address zoltuAddress = LibRainDeploy.etchAndDeployZoltu(vm, suite.creationCode);
            if (zoltuAddress != deployed[0]) {
                revert ZoltuDerivationMismatch(suite.suite, deployed[0], zoltuAddress);
            }
            return deployed;
        }

        CloneTarget[] memory targets;
        if (suite.mechanism == DeployMechanism.ClonePerNetwork) {
            CloneNetworks memory clones = cloneNetworks(suite);
            targets = new CloneTarget[](clones.networks.length);
            for (uint256 i = 0; i < targets.length; i++) {
                targets[i] = LibRainDeployClone.cloneNetworkTarget(clones, i);
            }
        } else {
            targets = new CloneTarget[](1);
            targets[0] = cloneTarget(suite);
        }
        if (keccak256(suite.creationCode) != keccak256(LibRainDeployClone.cloneCreationCode(targets[0].implementation)))
        {
            revert CloneCreationCodeMismatch(suite.suite);
        }
        for (uint256 i = 0; i < targets.length; i++) {
            if (deployedEarlier(deployed, i)) {
                continue;
            }
            vm.etch(deployed[i], hex"");
            vm.resetNonce(deployed[i]);
            address cloneAddress = ICloneableFactoryV4(targets[i].factory)
                .cloneDeterministicOpenSalt(targets[i].implementation, targets[i].data, targets[i].salt);
            if (cloneAddress != deployed[i]) {
                revert CloneDerivationMismatch(suite.suite, deployed[i], cloneAddress);
            }
        }
        return deployed;
    }

    /// Whether an address appears in a list before a given position.
    /// @param addresses The list.
    /// @param index The position whose address is looked for before it.
    /// @return Whether `addresses[index]` is also at some position below `index`.
    function deployedEarlier(address[] memory addresses, uint256 index) internal pure returns (bool) {
        for (uint256 j = 0; j < index; j++) {
            if (addresses[j] == addresses[index]) {
                return true;
            }
        }
        return false;
    }

    /// Broadcasts a suite by its mechanism, to each network, as the given key.
    /// @param vm The Vm instance to fork and broadcast with.
    /// @param networks The networks to broadcast to.
    /// @param deployerPrivateKey The key to broadcast as.
    /// @param suite The suite to broadcast.
    /// @return Where the suite is on each network, positionally paired with `networks`.
    /// @return The fork each network was deployed on.
    function deployAndBroadcast(Vm vm, string[] memory networks, uint256 deployerPrivateKey, DeploySuite memory suite)
        internal
        returns (address[] memory, uint256[] memory)
    {
        if (networks.length == 0) {
            revert LibRainDeploy.NoNetworks();
        }
        SupportedNetwork[] memory configs = LibRainDeploy.declaredNetworkConfigs(networks);
        NetworkDeploys memory deploys = NetworkDeploys({
            deployStepData: new bytes[](configs.length),
            expectedAddresses: new address[](configs.length),
            derivedAddresses: new address[](configs.length)
        });
        for (uint256 i = 0; i < configs.length; i++) {
            deploys.deployStepData[i] = deployStepData(suite, configs[i].chainId);
            deploys.expectedAddresses[i] = recordedAddress(suite, configs[i].chainId);
            deploys.derivedAddresses[i] = deployedAddress(suite, configs[i].chainId);
        }
        uint256[] memory forkIds = LibRainDeploy.deployStepToNetworks(
            vm,
            configs,
            LibRainDeploy.rememberDeployer(vm, deployerPrivateKey),
            deployStep(suite),
            deploys,
            suite.storedBytecodeHash,
            suite.dependencies
        );
        if (suite.mechanism == DeployMechanism.Zoltu) {
            LibRainDeploy.logVerifyCommands(vm, networks, deploys.expectedAddresses[0], suite.artifactPath);
        }
        return (deploys.expectedAddresses, forkIds);
    }

    /// A clone declaration as the `DeployCandidate` every other part of this package reads.
    /// @param clone The clone being declared.
    /// @param chainIds The chain id of every network the repo supports, in its
    /// `supportedNetworks()` order.
    /// @return The candidate.
    function cloneCandidate(CloneDeploy memory clone, uint256[] memory chainIds)
        internal
        view
        returns (DeployCandidate memory)
    {
        DeployMechanism mechanism;
        bytes memory mechanismData;
        address storedDeployedAddress = address(0);
        if (!clone.initDataPerNetwork) {
            CloneTarget memory target = CloneTarget({
                factory: clone.factory, implementation: clone.implementation, data: clone.data, salt: clone.salt
            });
            mechanism = DeployMechanism.Clone;
            mechanismData = abi.encode(target);
            storedDeployedAddress = LibRainDeployClone.cloneDeployedAddress(target);
        } else {
            if (clone.data.length != 0) {
                revert CloneDataAmbiguous(clone.suite);
            }
            CloneNetworks memory clones = CloneNetworks({
                factory: clone.factory,
                implementation: clone.implementation,
                salt: clone.salt,
                networks: new CloneNetwork[](chainIds.length)
            });
            for (uint256 i = 0; i < chainIds.length; i++) {
                clones.networks[i] = CloneNetwork({
                    chainId: chainIds[i], data: clone.initData(chainIds[i]), deployedAddress: address(0)
                });
                clones.networks[i].deployedAddress =
                    LibRainDeployClone.cloneDeployedAddress(LibRainDeployClone.cloneNetworkTarget(clones, i));
            }
            mechanism = DeployMechanism.ClonePerNetwork;
            mechanismData = abi.encode(clones);
        }
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: clone.suite,
                creationCode: LibRainDeployClone.cloneCreationCode(clone.implementation),
                storedDeployedAddress: storedDeployedAddress,
                storedBytecodeHash: LibRainDeployClone.cloneDeployedCodehash(clone.implementation),
                storedRuntimeCode: LibRainDeployClone.cloneRuntimeCode(clone.implementation),
                artifactPath: CLONE_ARTIFACT_PATH,
                dependencies: clone.dependencies,
                mechanism: mechanism,
                mechanismData: mechanismData
            }),
            unanchorableReason: CLONE_UNANCHORABLE_REASON
        });
    }
}
