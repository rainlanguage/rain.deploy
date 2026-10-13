// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {ICloneableFactoryV4} from "rain-factory-0.1.30/src/interface/ICloneableFactoryV4.sol";

import {DeployCandidate, DeployMechanism, DeploySuite} from "../abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "./LibRainDeploy.sol";
import {
    CLONE_ARTIFACT_PATH,
    CLONE_UNANCHORABLE_REASON,
    CloneDeploy,
    CloneNetwork,
    CloneNetworks,
    CloneTarget,
    LibRainDeployClone
} from "./LibRainDeployClone.sol";

/// Thrown when the pure `LibRainDeploy.zoltuAddress` formula and an actual
/// deploy through the etched Zoltu factory bytecode disagree about where a
/// creation code lands. Both are `LibRainDeploy`'s, so this is a defect in the
/// library rather than in any snapshot, and it invalidates every derivation
/// made from it.
/// @param suite The suite whose creation code was being derived.
/// @param formulaAddress The address `zoltuAddress` computed.
/// @param factoryAddress The address the factory bytecode actually deployed to.
error ZoltuDerivationMismatch(string suite, address formulaAddress, address factoryAddress);

/// Thrown when a clone suite's declared factory, run locally, puts the clone
/// somewhere other than the address `rain-factory`'s formula derives. The
/// factory is the code the suite DECLARES at the factory address, so this is a
/// declared factory that disagrees with the formula every recorded address is
/// checked against.
/// @param suite The suite being derived.
/// @param formulaAddress The address `LibRainDeployClone.cloneDeployedAddress`
/// computed.
/// @param factoryAddress The address the declared factory actually deployed to.
error CloneDerivationMismatch(string suite, address formulaAddress, address factoryAddress);

/// Thrown when a clone suite's `creationCode` is not the EIP-1167 creation code
/// for the implementation its `mechanismData` names. Nothing broadcasts a
/// clone's creation code, so it is a statement of what is deployed, and a
/// statement that disagrees with the mechanism is refused rather than recorded.
/// @param suite The suite being derived.
error CloneCreationCodeMismatch(string suite);

/// Thrown when a Zoltu suite carries mechanism data. Zoltu needs nothing beyond
/// the creation code, so bytes there are a suite whose mechanism and data
/// disagree — most likely a clone entry with the wrong mechanism — and reading
/// it as Zoltu would derive an address its author did not mean.
/// @param suite The suite carrying the data.
error UnexpectedMechanismData(string suite);

/// Thrown when a `ClonePerNetwork` suite carries a `storedDeployedAddress`. Its
/// addresses are recorded per network in its `mechanismData`, so a single
/// address beside them is a second record of where it is, which no reader
/// consults and which therefore cannot be relied on to agree.
/// @param suite The suite carrying the address.
/// @param storedDeployedAddress The address it carries.
error UnexpectedStoredDeployedAddress(string suite, address storedDeployedAddress);

/// Thrown when a clone declaration sets `initDataPerNetwork` and also declares
/// `data` for every network. Either could be meant, and each puts the clone at
/// different addresses.
/// @param suite The declaration's suite key.
error CloneDataAmbiguous(string suite);

/// @title LibRainDeployMechanism
/// @notice The one place anything dispatches on a suite's `DeployMechanism`.
///
/// The broadcast (`RainDeployBroadcast.broadcastSuite`), the local derivation
/// every verification group compares against
/// (`RainDeployVerifyBase.deriveDeployment`), the per-network address the chain
/// group checks (`RainDeployVerifyChain`), the frozen record match
/// (`RainDeployVerifySnapshotBase.checkFrozenSnapshotsReleased`) and the
/// snapshot writer (`LibRainDeploySnapshot.writeSnapshot`) each read the
/// mechanism from the suite they were handed and go through here. So a suite is
/// verified by the same mechanism it is broadcast by, from the same entry, and
/// there is nothing for a consumer to opt into or override to make that so.
///
/// A suite's ADDRESSES are a list: one address on every network for Zoltu and
/// `Clone`, one per declared network for `ClonePerNetwork`, in the order its
/// `CloneNetworks` names them. `recordedAddresses`, `deployedAddresses` and
/// `deployLocally` all answer in that one order, so a reader compares them
/// position by position.
library LibRainDeployMechanism {
    /// Requires a Zoltu suite to carry no mechanism data.
    /// @param suite The Zoltu suite.
    function checkZoltuMechanismData(DeploySuite memory suite) internal pure {
        if (suite.mechanismData.length != 0) {
            revert UnexpectedMechanismData(suite.suite);
        }
    }

    /// A clone suite's `CloneTarget`, with its factory and implementation held
    /// to being declared dependencies of the same suite.
    ///
    /// The one decode of a `Clone` suite's `mechanismData`, so every reader of
    /// a clone suite gets the dependency rule with the target.
    /// @param suite A suite whose mechanism is `Clone`.
    /// @return target The decoded target.
    function cloneTarget(DeploySuite memory suite) internal pure returns (CloneTarget memory target) {
        target = abi.decode(suite.mechanismData, (CloneTarget));
        LibRainDeployClone.checkCloneDependencies(target, suite.dependencies);
    }

    /// A per-network clone suite's `CloneNetworks`, held to
    /// `LibRainDeployClone.checkCloneNetworks` and to carrying no
    /// `storedDeployedAddress`.
    ///
    /// The one decode of a `ClonePerNetwork` suite's `mechanismData`, for the
    /// reason `cloneTarget` is the one decode of a `Clone` suite's.
    /// @param suite A suite whose mechanism is `ClonePerNetwork`.
    /// @return clones The decoded per-network clone.
    function cloneNetworks(DeploySuite memory suite) internal pure returns (CloneNetworks memory clones) {
        if (suite.storedDeployedAddress != address(0)) {
            revert UnexpectedStoredDeployedAddress(suite.suite, suite.storedDeployedAddress);
        }
        clones = abi.decode(suite.mechanismData, (CloneNetworks));
        LibRainDeployClone.checkCloneNetworks(clones, suite.dependencies);
    }

    /// The address a suite's mechanism puts it at on one network.
    ///
    /// The chain id is read only by a `ClonePerNetwork` suite, which refuses a
    /// chain id it has no entry for with
    /// `LibRainDeployClone.CloneNetworkUndeclared`. Zoltu and `Clone` suites
    /// are at one address on every network.
    /// @param suite The suite.
    /// @param chainId The network's chain id.
    /// @return The derived address on that network.
    function deployedAddress(DeploySuite memory suite, uint256 chainId) internal pure returns (address) {
        if (suite.mechanism == DeployMechanism.ClonePerNetwork) {
            CloneNetworks memory clones = cloneNetworks(suite);
            return LibRainDeployClone.cloneDeployedAddress(
                LibRainDeployClone.cloneNetworkTarget(clones, LibRainDeployClone.cloneNetworkIndex(clones, chainId))
            );
        }
        if (suite.mechanism == DeployMechanism.Clone) {
            return LibRainDeployClone.cloneDeployedAddress(cloneTarget(suite));
        }
        checkZoltuMechanismData(suite);
        return LibRainDeploy.zoltuAddress(suite.creationCode);
    }

    /// Every address a suite's mechanism derives for it, in the suite's address
    /// order.
    /// @param suite The suite.
    /// @return addresses The derived addresses.
    function deployedAddresses(DeploySuite memory suite) internal pure returns (address[] memory addresses) {
        if (suite.mechanism == DeployMechanism.ClonePerNetwork) {
            CloneNetworks memory clones = cloneNetworks(suite);
            addresses = new address[](clones.networks.length);
            for (uint256 i = 0; i < clones.networks.length; i++) {
                addresses[i] = LibRainDeployClone.cloneDeployedAddress(LibRainDeployClone.cloneNetworkTarget(clones, i));
            }
            return addresses;
        }
        addresses = new address[](1);
        // Any chain id: only a per-network suite reads it.
        addresses[0] = deployedAddress(suite, 0);
    }

    /// Every address a suite RECORDS for itself, in the suite's address order:
    /// `storedDeployedAddress`, or each network's recorded address for a
    /// `ClonePerNetwork` suite.
    /// @param suite The suite.
    /// @return addresses The recorded addresses.
    function recordedAddresses(DeploySuite memory suite) internal pure returns (address[] memory addresses) {
        if (suite.mechanism == DeployMechanism.ClonePerNetwork) {
            CloneNetworks memory clones = cloneNetworks(suite);
            addresses = new address[](clones.networks.length);
            for (uint256 i = 0; i < clones.networks.length; i++) {
                addresses[i] = clones.networks[i].deployedAddress;
            }
            return addresses;
        }
        addresses = new address[](1);
        addresses[0] = suite.storedDeployedAddress;
    }

    /// The chain id each of a suite's addresses is for, in the suite's address
    /// order: empty for a Zoltu or `Clone` suite, whose one address is on every
    /// network, and each entry's chain id for a `ClonePerNetwork` suite.
    /// @param suite The suite.
    /// @return chainIds The chain ids.
    function addressChainIds(DeploySuite memory suite) internal pure returns (uint256[] memory chainIds) {
        if (suite.mechanism == DeployMechanism.ClonePerNetwork) {
            CloneNetworks memory clones = cloneNetworks(suite);
            chainIds = new uint256[](clones.networks.length);
            for (uint256 i = 0; i < clones.networks.length; i++) {
                chainIds[i] = clones.networks[i].chainId;
            }
        }
    }

    /// Runs a suite's mechanism on the local EVM and returns where it landed,
    /// each address cross-checked against the formula's.
    ///
    /// The declared dependencies are etched FIRST, from the runtime code the
    /// declaration carries, so the declaration cannot reach the addresses this
    /// function owns afterwards: the subject, which is cleared — code and nonce,
    /// since `CREATE2` collides on either — and then deployed rather than
    /// etched, and the Zoltu factory. For a clone the factory and the
    /// implementation are declared dependencies, so the clone is deployed by
    /// the factory code the declaration pins, delegating into the implementation
    /// code it pins. A per-network clone is deployed once per network entry,
    /// each with that network's init data.
    ///
    /// Leaves its state in place. A caller that must not keep it — every
    /// derivation — takes a state snapshot around the call and reverts it.
    /// @param vm The Vm instance to etch with.
    /// @param suite The suite to deploy.
    /// @return deployed Where the mechanism deployed it, in the suite's address
    /// order — the derived addresses.
    function deployLocally(Vm vm, DeploySuite memory suite) internal returns (address[] memory deployed) {
        deployed = deployedAddresses(suite);

        for (uint256 i = 0; i < suite.dependencies.length; i++) {
            vm.etch(suite.dependencies[i].deployedAddress, suite.dependencies[i].runtimeCode);
        }

        if (suite.mechanism == DeployMechanism.Zoltu) {
            vm.etch(deployed[0], hex"");
            vm.resetNonce(deployed[0]);
            LibRainDeploy.etchZoltuFactory(vm);
            address zoltuAddress = LibRainDeploy.deployZoltu(suite.creationCode);
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
            // Networks sharing init data share an address, and the clone the
            // first of them deployed is the clone every one of them derives:
            // clearing its code would leave its initialized storage behind for
            // a second `initialize` to refuse.
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
    }

    /// Whether an address appears in a list before a given position.
    /// @param addresses The list.
    /// @param index The position whose address is looked for before it.
    /// @return Whether `addresses[index]` is also at some position below
    /// `index`.
    function deployedEarlier(address[] memory addresses, uint256 index) internal pure returns (bool) {
        for (uint256 j = 0; j < index; j++) {
            if (addresses[j] == addresses[index]) {
                return true;
            }
        }
        return false;
    }

    /// Broadcasts a suite by its mechanism, to each network, as the given key.
    ///
    /// The suite's RECORDED addresses and code hash are handed over, never
    /// derived here: each mechanism compares the recorded address on every
    /// network against its own derivation before it forks anything, and a
    /// derived value would make that a comparison of a value with itself.
    /// @param vm The Vm instance to fork and broadcast with.
    /// @param networks The networks to broadcast to.
    /// @param deployerPrivateKey The key to broadcast as.
    /// @param suite The suite to broadcast.
    /// @return addresses Where the suite is on each network,
    /// positionally paired with `networks`: one address on every network for
    /// Zoltu and `Clone`, each network's own for `ClonePerNetwork`.
    /// @return forkIds The fork each network was deployed on.
    function deployAndBroadcast(Vm vm, string[] memory networks, uint256 deployerPrivateKey, DeploySuite memory suite)
        internal
        returns (address[] memory addresses, uint256[] memory forkIds)
    {
        if (suite.mechanism == DeployMechanism.ClonePerNetwork) {
            (addresses, forkIds) = LibRainDeployClone.cloneNetworksAndBroadcast(
                vm,
                networks,
                deployerPrivateKey,
                cloneNetworks(suite),
                suite.artifactPath,
                suite.storedBytecodeHash,
                suite.dependencies
            );
            return (addresses, forkIds);
        }
        address deployed;
        if (suite.mechanism == DeployMechanism.Clone) {
            (deployed, forkIds) = LibRainDeployClone.cloneAndBroadcast(
                vm,
                networks,
                deployerPrivateKey,
                cloneTarget(suite),
                suite.artifactPath,
                suite.storedDeployedAddress,
                suite.storedBytecodeHash,
                suite.dependencies
            );
        } else {
            checkZoltuMechanismData(suite);
            (deployed, forkIds) = LibRainDeploy.deployAndBroadcast(
                vm,
                networks,
                deployerPrivateKey,
                suite.creationCode,
                suite.artifactPath,
                suite.storedDeployedAddress,
                suite.storedBytecodeHash,
                suite.dependencies
            );
        }
        addresses = new address[](networks.length);
        for (uint256 i = 0; i < networks.length; i++) {
            addresses[i] = deployed;
        }
    }

    /// A clone declaration as the `DeployCandidate` every other part of this
    /// package reads: every recorded field derived from the clone, the
    /// mechanism and its data set from how the declaration states its init
    /// data, the declared dependencies carried through, and the standard
    /// unanchorable reason.
    ///
    /// One init data for every network is a `Clone` suite with the
    /// `CloneTarget` as its data. Init data per network is a `ClonePerNetwork`
    /// suite with the `CloneNetworks` as its data: one entry per chain id in
    /// `chainIds`, in that order, its data read from `clone.initData` and its
    /// address derived from that data, and no `storedDeployedAddress`. A chain id
    /// `initData` reverts on reverts here, with its revert. Per-network init data
    /// beside a `data` is refused with `CloneDataAmbiguous`.
    /// @param clone The clone being declared.
    /// @param chainIds The chain id of every network the repo supports, in its
    /// `supportedNetworks()` order. Not read for a clone whose init data is
    /// the same on every network.
    /// @return The candidate.
    function cloneCandidate(CloneDeploy memory clone, uint256[] memory chainIds)
        internal
        view
        returns (DeployCandidate memory)
    {
        DeployMechanism mechanism;
        bytes memory mechanismData;
        // Zero unless one address serves every network: a `ClonePerNetwork`
        // suite records its addresses in its `mechanismData`.
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
