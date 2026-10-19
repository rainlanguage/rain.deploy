// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm, VmSafe} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
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

/// Thrown when a suite that is not a per-network clone is given extended networks.
/// @param suite The suite's key.
error ExtendedNetworksUnexpected(string suite);

/// Thrown when an extended network's address is not the one its init data derives under the release.
/// @param suite The release's suite key.
/// @param chainId The extended network's chain id.
/// @param derivedAddress The address its init data derives.
/// @param extendedAddress The address it declares.
error ExtendedNetworkAddressMismatch(string suite, uint256 chainId, address derivedAddress, address extendedAddress);

/// Thrown when a per-network release is live, or about to be broadcast, on a network it neither records nor declares
/// as extended, at the address its candidate's current init data derives.
/// @param suite The release's suite key.
/// @param network The network.
/// @param deployedAddress The address checked or to be broadcast there.
error ExtendedNetworkUnfrozen(string suite, string network, address deployedAddress);

/// Thrown when a storage slot of any account but the clone is read while the clone is deployed locally: the factory
/// call and the clone's `initialize`.
/// @param suite The suite being deployed.
/// @param account The account whose storage was read.
/// @param slot The slot read.
error CloneInitializeReadsStorage(string suite, address account, bytes32 slot);

/// Emitted when a broadcast Zoltu entry under `CLONE_ARTIFACT_PATH` leaves its source to verify by hand.
/// @param sender The deploy's `msg.sender`, not the broadcasting key.
/// @param entryAddress Where the entry is deployed on every network.
/// @param networks The networks it was broadcast to.
event UnverifiableSource(address indexed sender, address indexed entryAddress, string[] networks);

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

    /// A per-network clone suite with an entry for every network in play its candidate has one for.
    /// @param suite The suite.
    /// @param candidate The candidate whose init data the suite's unrecorded networks take.
    /// @param chainIds The chain ids in play; a candidate network on any other chain is not added.
    /// @return The suite, with the candidate's networks in play it lacks.
    function withUnrecordedNetworks(DeploySuite memory suite, DeploySuite memory candidate, uint256[] memory chainIds)
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
            if (!hasChainId(networks, recorded, declared[i].chainId) && containsChainId(chainIds, declared[i].chainId))
            {
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
        return withMechanismData(suite, abi.encode(clones));
    }

    /// A per-network release with the networks declared for it beyond those it records appended, each held to the
    /// address its init data derives under the release.
    /// Reverts with `ExtendedNetworksUnexpected` on a suite that is not per network, `ExtendedNetworkAddressMismatch` on
    /// an entry at an address its init data does not derive, and `DuplicateCloneNetwork` on a network named twice.
    /// @param suite The release.
    /// @param extended The networks declared for it, each as it is or will be broadcast.
    /// @return The release with them.
    function withExtendedNetworks(DeploySuite memory suite, CloneNetwork[] memory extended)
        internal
        pure
        returns (DeploySuite memory)
    {
        if (extended.length == 0) {
            return suite;
        }
        if (suite.mechanism != DeployMechanism.ClonePerNetwork) {
            revert ExtendedNetworksUnexpected(suite.suite);
        }
        CloneNetworks memory clones = cloneNetworks(suite);
        uint256 recorded = clones.networks.length;
        CloneNetwork[] memory networks = new CloneNetwork[](recorded + extended.length);
        for (uint256 i = 0; i < recorded; i++) {
            networks[i] = clones.networks[i];
        }
        for (uint256 i = 0; i < extended.length; i++) {
            networks[recorded + i] = extended[i];
        }
        clones.networks = networks;
        for (uint256 i = recorded; i < networks.length; i++) {
            address derived = LibRainDeployClone.cloneDeployedAddress(LibRainDeployClone.cloneNetworkTarget(clones, i));
            if (derived != networks[i].deployedAddress) {
                revert ExtendedNetworkAddressMismatch(
                    suite.suite, networks[i].chainId, derived, networks[i].deployedAddress
                );
            }
        }
        LibRainDeployClone.checkCloneNetworks(clones, suite.dependencies);
        return withMechanismData(suite, abi.encode(clones));
    }

    /// Refuses a per-network release on a network that `frozen` neither records nor declares as extended.
    /// @param frozen The release with its extended networks.
    /// @param network The network's name.
    /// @param chainId The network's chain id.
    /// @param where The address checked on it.
    function checkNetworkFrozen(DeploySuite memory frozen, string memory network, uint256 chainId, address where)
        internal
        pure
    {
        if (frozen.mechanism != DeployMechanism.ClonePerNetwork) {
            return;
        }
        CloneNetworks memory clones = cloneNetworks(frozen);
        if (!hasChainId(clones.networks, clones.networks.length, chainId)) {
            revert ExtendedNetworkUnfrozen(frozen.suite, network, where);
        }
    }

    /// Refuses to broadcast a per-network release to a network it neither records nor declares as extended, so an
    /// unrecorded network's address is frozen before it exists on chain.
    /// @param frozen The release with its extended networks.
    /// @param onNetworks The release as it would be broadcast, with its candidate's unrecorded networks.
    /// @param networks The networks to broadcast to.
    function checkNetworksFrozen(DeploySuite memory frozen, DeploySuite memory onNetworks, string[] memory networks)
        internal
        pure
    {
        if (onNetworks.mechanism != DeployMechanism.ClonePerNetwork) {
            return;
        }
        SupportedNetwork[] memory configs = LibRainDeploy.declaredNetworkConfigs(networks);
        CloneNetwork[] memory clones = cloneNetworks(onNetworks).networks;
        for (uint256 i = 0; i < configs.length; i++) {
            for (uint256 j = 0; j < clones.length; j++) {
                if (clones[j].chainId == configs[i].chainId) {
                    checkNetworkFrozen(frozen, networks[i], configs[i].chainId, clones[j].deployedAddress);
                }
            }
        }
    }

    /// Whether a list of chain ids holds a chain id.
    /// @param chainIds The list.
    /// @param chainId The chain id looked for.
    /// @return Whether it is in the list.
    function containsChainId(uint256[] memory chainIds, uint256 chainId) internal pure returns (bool) {
        for (uint256 i = 0; i < chainIds.length; i++) {
            if (chainIds[i] == chainId) {
                return true;
            }
        }
        return false;
    }

    /// A suite with its mechanism data replaced.
    /// @param suite The suite.
    /// @param mechanismData The mechanism data it takes.
    /// @return The suite with that mechanism data.
    function withMechanismData(DeploySuite memory suite, bytes memory mechanismData)
        internal
        pure
        returns (DeploySuite memory)
    {
        return DeploySuite({
            suite: suite.suite,
            creationCode: suite.creationCode,
            storedDeployedAddress: suite.storedDeployedAddress,
            storedBytecodeHash: suite.storedBytecodeHash,
            storedRuntimeCode: suite.storedRuntimeCode,
            artifactPath: suite.artifactPath,
            dependencies: suite.dependencies,
            mechanism: suite.mechanism,
            mechanismData: mechanismData
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
    /// A storage read during the factory call of any account the call did not create is refused with
    /// `CloneInitializeReadsStorage`, even when the call then reverts: locally that storage is empty, while an account
    /// the call creates, the clone among them, is empty on chain too. A call that reverts without one reverts
    /// unchanged.
    /// Only storage reads are checked: a balance or code read of another account is not refused. A write to part of a
    /// slot reads the slot first, so it is refused like a read.
    /// Each clone is deployed under a state-diff recording, which ends any recording the caller started.
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
            vm.startStateDiffRecording();
            // slither-disable-next-line low-level-calls
            (bool success, bytes memory result) = targets[i].factory
                .call(
                    abi.encodeCall(
                        ICloneableFactoryV4.cloneDeterministicOpenSalt,
                        (targets[i].implementation, targets[i].data, targets[i].salt)
                    )
                );
            Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
            if (success) {
                address cloneAddress = abi.decode(result, (address));
                if (cloneAddress != deployed[i]) {
                    revert CloneDerivationMismatch(suite.suite, deployed[i], cloneAddress);
                }
            }
            checkReadsOwnStorageOnly(suite.suite, accesses);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(result, 0x20), mload(result))
                }
            }
        }
        return deployed;
    }

    /// Refuses a storage read, recorded while a clone was deployed, of any account not created in the recording: the
    /// clone and any account its `initialize` creates are empty on chain too. Only storage reads are checked: a
    /// balance or code read of another account is not refused.
    /// @param suite The suite being deployed.
    /// @param accesses What was recorded.
    function checkReadsOwnStorageOnly(string memory suite, Vm.AccountAccess[] memory accesses) internal pure {
        for (uint256 i = 0; i < accesses.length; i++) {
            for (uint256 j = 0; j < accesses[i].storageAccesses.length; j++) {
                Vm.StorageAccess memory access = accesses[i].storageAccesses[j];
                if (!access.isWrite && !createdIn(access.account, accesses)) {
                    revert CloneInitializeReadsStorage(suite, access.account, access.slot);
                }
            }
        }
    }

    /// Whether a recording created an account.
    /// @param account The account.
    /// @param accesses What was recorded.
    /// @return Whether some access created `account`.
    function createdIn(address account, Vm.AccountAccess[] memory accesses) internal pure returns (bool) {
        for (uint256 k = 0; k < accesses.length; k++) {
            if (accesses[k].kind == VmSafe.AccountAccessKind.Create && accesses[k].account == account) {
                return true;
            }
        }
        return false;
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

    /// Broadcasts a suite by its mechanism, to each network, as the given key: `frozen` with `candidate`'s networks it
    /// lacks among `networks`, after `checkNetworksFrozen` refuses any of those `frozen` does not declare.
    /// @param vm The Vm instance to fork and broadcast with.
    /// @param networks The networks to broadcast to.
    /// @param deployerPrivateKey The key to broadcast as.
    /// @param frozen The release with its extended networks.
    /// @param candidate The release's candidate, or `frozen` when it has none.
    /// @return Where the suite is on each network, positionally paired with `networks`.
    /// @return The fork each network was deployed on.
    function deployAndBroadcast(
        Vm vm,
        string[] memory networks,
        uint256 deployerPrivateKey,
        DeploySuite memory frozen,
        DeploySuite memory candidate
    ) internal returns (address[] memory, uint256[] memory) {
        if (networks.length == 0) {
            revert LibRainDeploy.NoNetworks();
        }
        SupportedNetwork[] memory configs = LibRainDeploy.declaredNetworkConfigs(networks);
        DeploySuite memory suite = withUnrecordedNetworks(frozen, candidate, LibRainDeploy.networkChainIds(configs));
        checkNetworksFrozen(frozen, suite, networks);
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
            if (keccak256(bytes(suite.artifactPath)) != keccak256(bytes(CLONE_ARTIFACT_PATH))) {
                LibRainDeploy.logVerifyCommands(vm, networks, deploys.expectedAddresses[0], suite.artifactPath);
            } else {
                // slither-disable-next-line reentrancy-events
                emit UnverifiableSource(msg.sender, deploys.expectedAddresses[0], networks);
                console2.log(unverifiableSourceNotice(vm, networks, deploys.expectedAddresses[0]));
            }
        }
        return (deploys.expectedAddresses, forkIds);
    }

    /// The notice that a Zoltu entry under `CLONE_ARTIFACT_PATH` names no compiled source to verify, so its source
    /// needs verifying by hand on each network.
    /// @param vm The Vm instance to format the address with.
    /// @param networks The networks the entry is deployed on.
    /// @param where Where it is deployed on every one of them.
    /// @return The notice.
    function unverifiableSourceNotice(Vm vm, string[] memory networks, address where)
        internal
        pure
        returns (string memory)
    {
        string memory notice = string.concat(
            "no verify command: the Zoltu entry carries the clone artifact path; verify the source at ",
            vm.toString(where),
            " by hand on"
        );
        for (uint256 i = 0; i < networks.length; i++) {
            notice = string.concat(notice, " ", networks[i]);
        }
        return notice;
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
