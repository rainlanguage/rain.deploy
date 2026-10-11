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

/// @title LibRainDeployMechanism
/// @notice The one place anything dispatches on a suite's `DeployMechanism`.
///
/// The broadcast (`RainDeployBroadcast.broadcastSuite`), the local derivation
/// every verification group compares against
/// (`RainDeployVerifyBase.deriveDeployment`), the frozen record match
/// (`RainDeployVerifySnapshotBase.checkFrozenSnapshotsReleased`) and the
/// snapshot writer (`LibRainDeploySnapshot.writeSnapshot`) each read the
/// mechanism from the suite they were handed and go through here. So a suite is
/// verified by the same mechanism it is broadcast by, from the same entry, and
/// there is nothing for a consumer to opt into or override to make that so.
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
    /// The one decode of `mechanismData`, so every reader of a clone suite gets
    /// the dependency rule with the target.
    /// @param suite A suite whose mechanism is `Clone`.
    /// @return target The decoded target.
    function cloneTarget(DeploySuite memory suite) internal pure returns (CloneTarget memory target) {
        target = abi.decode(suite.mechanismData, (CloneTarget));
        LibRainDeployClone.checkCloneDependencies(target, suite.dependencies);
    }

    /// The address a suite's mechanism puts it at, on every network.
    /// @param suite The suite.
    /// @return The derived address.
    function deployedAddress(DeploySuite memory suite) internal pure returns (address) {
        if (suite.mechanism == DeployMechanism.Clone) {
            return LibRainDeployClone.cloneDeployedAddress(cloneTarget(suite));
        }
        checkZoltuMechanismData(suite);
        return LibRainDeploy.zoltuAddress(suite.creationCode);
    }

    /// Runs a suite's mechanism on the local EVM and returns where it landed,
    /// which is cross-checked against `deployedAddress`.
    ///
    /// The declared dependencies are etched FIRST, from the runtime code the
    /// declaration carries, so the declaration cannot reach the addresses this
    /// function owns afterwards: the subject, which is cleared — code and nonce,
    /// since `CREATE2` collides on either — and then deployed rather than
    /// etched, and the Zoltu factory. For a clone the factory and the
    /// implementation are declared dependencies, so the clone is deployed by
    /// the factory code the declaration pins, delegating into the implementation
    /// code it pins.
    ///
    /// Leaves its state in place. A caller that must not keep it — every
    /// derivation — takes a state snapshot around the call and reverts it.
    /// @param vm The Vm instance to etch with.
    /// @param suite The suite to deploy.
    /// @return The address the mechanism deployed to, which is the derived one.
    function deployLocally(Vm vm, DeploySuite memory suite) internal returns (address) {
        address formulaAddress = deployedAddress(suite);

        for (uint256 i = 0; i < suite.dependencies.length; i++) {
            vm.etch(suite.dependencies[i].deployedAddress, suite.dependencies[i].runtimeCode);
        }

        vm.etch(formulaAddress, hex"");
        vm.resetNonce(formulaAddress);

        if (suite.mechanism == DeployMechanism.Clone) {
            CloneTarget memory target = cloneTarget(suite);
            if (keccak256(suite.creationCode) != keccak256(LibRainDeployClone.cloneCreationCode(target.implementation)))
            {
                revert CloneCreationCodeMismatch(suite.suite);
            }
            address cloneAddress = ICloneableFactoryV4(target.factory)
                .cloneDeterministicOpenSalt(target.implementation, target.data, target.salt);
            if (cloneAddress != formulaAddress) {
                revert CloneDerivationMismatch(suite.suite, formulaAddress, cloneAddress);
            }
        } else {
            LibRainDeploy.etchZoltuFactory(vm);
            address zoltuAddress = LibRainDeploy.deployZoltu(suite.creationCode);
            if (zoltuAddress != formulaAddress) {
                revert ZoltuDerivationMismatch(suite.suite, formulaAddress, zoltuAddress);
            }
        }

        return formulaAddress;
    }

    /// Broadcasts a suite by its mechanism, to each network, as the given key.
    ///
    /// The suite's RECORDED address and code hash are handed over, never
    /// derived here: each mechanism compares the recorded address against its
    /// own derivation before it forks anything, and a derived value would make
    /// that a comparison of a value with itself.
    /// @param vm The Vm instance to fork and broadcast with.
    /// @param networks The networks to broadcast to.
    /// @param deployerPrivateKey The key to broadcast as.
    /// @param suite The suite to broadcast.
    /// @return deployed The deployed address.
    /// @return forkIds The fork each network was deployed on.
    function deployAndBroadcast(Vm vm, string[] memory networks, uint256 deployerPrivateKey, DeploySuite memory suite)
        internal
        returns (address deployed, uint256[] memory forkIds)
    {
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
    }

    /// A clone declaration as the `DeployCandidate` every other part of this
    /// package reads: every recorded field derived from the clone, the
    /// mechanism set to `Clone` with the `CloneTarget` as its data, the declared
    /// dependencies carried through, and the standard unanchorable reason.
    /// @param clone The clone being declared.
    /// @return The candidate.
    function cloneCandidate(CloneDeploy memory clone) internal pure returns (DeployCandidate memory) {
        CloneTarget memory target = CloneTarget({
            factory: clone.factory, implementation: clone.implementation, data: clone.data, salt: clone.salt
        });
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: clone.suite,
                creationCode: LibRainDeployClone.cloneCreationCode(clone.implementation),
                storedDeployedAddress: LibRainDeployClone.cloneDeployedAddress(target),
                storedBytecodeHash: LibRainDeployClone.cloneDeployedCodehash(clone.implementation),
                storedRuntimeCode: LibRainDeployClone.cloneRuntimeCode(clone.implementation),
                artifactPath: CLONE_ARTIFACT_PATH,
                dependencies: clone.dependencies,
                mechanism: DeployMechanism.Clone,
                mechanismData: abi.encode(target)
            }),
            unanchorableReason: CLONE_UNANCHORABLE_REASON
        });
    }
}
