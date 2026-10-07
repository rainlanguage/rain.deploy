// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {ICloneableFactoryV4} from "rain-factory-0.1.30/src/interface/ICloneableFactoryV4.sol";
import {LibICloneableFactoryV4} from "rain-factory-0.1.30/src/lib/LibICloneableFactoryV4.sol";

import {DeployCandidate, DeploySuite} from "../abstract/RainDeploySuitesBase.sol";
import {DeployDependency, LibRainDeploy} from "./LibRainDeploy.sol";

/// @dev How many leading bytes of the EIP-1167 creation code are the deploy
/// preamble rather than the runtime code it returns: `3d602d80600a3d3981f3`, ten
/// bytes, which copies the trailing 45 and returns them.
///
/// The proxy layout is `rain-factory`'s, which is why `cloneCreationCode` is
/// called for the bytes rather than assembled here. This one offset is the half
/// of the layout that library does not yet expose —
/// rainlanguage/rain.factory#268 asks for `cloneRuntimeCode` beside
/// `cloneCreationCode` — so it is spelled here, once, and this constant and the
/// slice below both go when that lands.
uint256 constant EIP1167_CREATION_CODE_PREFIX_LENGTH = 10;

/// @dev The artifact path every clone candidate declares.
///
/// `RainDeploySuitesBase.checkedCandidateSuites` holds EVERY candidate's
/// `artifactPath` to `<path>:<Name>`, unanchorable ones included — a bare name
/// resolves to whichever same-named artifact comes first, so the shape is the
/// rule, and the EMPTY string is refused by it. An unanchorable candidate spells
/// the path against the file it WOULD have had, and for a clone that file is the
/// same one in every repo: there is no per-consumer source, because an EIP-1167
/// proxy is assembled from an address rather than compiled.
///
/// So it is a constant rather than a parameter. One wording, one shape, and
/// nothing for a consumer to get wrong. No repo compiles it, so it resolves to
/// no artifact, which is the state `unanchorableReason` declares; a repo that
/// somehow did compile it is refused by `CandidateSourceCompiles`, loudly, which
/// is the designed failure rather than a silent anchor against a namesake.
string constant CLONE_ARTIFACT_PATH = "rain-factory/EIP1167Clone.sol:EIP1167Clone";

/// @dev Why no compiler produces a clone candidate's source. The standard reason
/// for the whole category, so every clone declares the same one instead of each
/// consumer wording it again.
string constant CLONE_UNANCHORABLE_REASON = "An EIP-1167 minimal proxy, assembled by the clone factory from the "
    "implementation address. No compiler produces it, so there is no artifact to anchor it to; the implementation "
    "it delegates into is the anchored contract, and because that address is embedded in the proxy's runtime the "
    "recorded code hash is what says which implementation this clone delegates to.";

/// One contract deployed as an EIP-1167 clone through an `ICloneableFactoryV4`
/// at its OPEN salt, as everything about it is derived from.
///
/// Every field of the `DeployCandidate` and every argument of the broadcast is a
/// pure function of these five, so this is the whole statement of a clone
/// deployment. That is what makes the declaration and the broadcast one list
/// rather than two: `RainDeployCloneSuitesBase` derives the candidates from it,
/// and `RainDeployCloneBroadcast` broadcasts from the same entry the selected
/// candidate was derived from.
///
/// The OPEN salt rather than the namespaced one, because this is a deploy
/// framework whose point is one address on every network: the open-salt digest
/// covers the implementation and the init data and NOT the caller, so every
/// account reaches the same address and a racer can only deploy the clone that
/// was specified. The namespaced derivation bakes a deploying account into the
/// address, which a retired key makes unreachable forever.
struct CloneDeploy {
    /// The suite key, held to the key alphabet and to uniqueness by
    /// `RainDeploySuitesBase.allSuites` like any other — the candidate this
    /// becomes carries it, so there is no second rule for a clone's key.
    string suite;
    /// The `ICloneableFactoryV4` that deploys the clone. A PARAMETER and not a
    /// constant: the deployed factory's address and code hash are pinned in
    /// `rain-factory-deploy`, which depends on this package, so a constant here
    /// would be a dependency cycle. The factory is held to its own derivation
    /// per network instead — see `cloneDeployStep`.
    address factory;
    /// The contract the proxy delegates into. Its address is embedded in the
    /// proxy's runtime code, so the recorded code hash is what says which
    /// implementation a deployed clone delegates to.
    address implementation;
    /// The initialization data, passed verbatim to `ICloneableV2.initialize` and
    /// hashed into the open salt. MAY be empty. A byte of difference is a
    /// different address, so a consumer pinning a clone address has to be able
    /// to reproduce these bytes exactly, ABI encoding and all.
    bytes data;
    /// The caller-chosen salt, before the factory's open-salt domain tag and
    /// `keccak256(data)` are hashed in with it.
    bytes32 salt;
}

/// @title LibRainDeployClone
/// @notice A contract deployed as an EIP-1167 factory clone, declared and
/// broadcast through the same machinery as a Zoltu deploy.
///
/// Two things live here, and nothing else does:
///
/// - `cloneCandidate`, which turns a `CloneDeploy` into the `DeployCandidate`
///   the verification abstracts already know how to check. Five derivations and
///   a standard reason, so a consumer declares a clone in one call rather than
///   writing all five and its own wording for the same unanchorable category.
/// - `cloneDeployStep`, the clone's deploy step, and `cloneToNetworks`, which
///   hands it to `LibRainDeploy.deployStepToNetworks`. The loop is NOT
///   reimplemented here: the network list, the forks created before any is
///   selected, the skip where the clone is already at its address, and the
///   address and code hash assertions are the same loop a Zoltu deploy runs.
///   The whole of the difference is the one call that puts code on chain.
///
/// Every derivation is `rain-factory`'s own — `cloneCreationCode`,
/// `effectiveOpenSalt`, `predictCloneAddress` — so this package carries no
/// second spelling of the proxy layout or the salt digest, bar the one prefix
/// length `EIP1167_CREATION_CODE_PREFIX_LENGTH` names.
library LibRainDeployClone {
    /// Thrown when the clone factory on a network does not derive the address
    /// this package derives for the same clone.
    ///
    /// The clone factory has no pinned code hash here, because the pin lives in
    /// `rain-factory-deploy` and that package depends on this one. This is the
    /// check that replaces it, and it is a stronger one: a code hash says the
    /// factory is a known build, while this says the factory AGREES about where
    /// this exact clone goes. A factory that is not an `ICloneableFactoryV4` at
    /// all reverts the read, and one whose domain tag or proxy layout differs
    /// answers a different address — both before anything is broadcast, which is
    /// the point. Finding out afterwards means a clone already exists at an
    /// address nobody declared, permanently.
    /// @param network The network whose factory was read, for the refusal to
    /// name.
    /// @param factory The factory that was asked.
    /// @param expected The address this package derives for the clone.
    /// @param predicted The address the factory says it would deploy to.
    error CloneFactoryPredictionMismatch(string network, address factory, address expected, address predicted);

    /// The clone's creation code: the EIP-1167 initcode the factory `CREATE2`s,
    /// from `rain-factory`'s own helper.
    ///
    /// Recorded on the candidate as its `creationCode` even though nothing
    /// broadcasts it — the clone factory is handed the implementation, not these
    /// bytes. It is the snapshot's statement of WHAT is deployed, and the
    /// verification abstracts derive the runtime code and its hash by running it,
    /// exactly as they do for a Zoltu suite.
    /// @param implementation The contract the proxy delegates into.
    /// @return The creation code.
    function cloneCreationCode(address implementation) internal pure returns (bytes memory) {
        return LibICloneableFactoryV4.cloneCreationCode(implementation);
    }

    /// The clone's runtime code: what `CREATE2` leaves at the clone address,
    /// which is the creation code with its deploy preamble cut off.
    ///
    /// Derived here only because `LibICloneableFactoryV4` does not expose it yet
    /// — rainlanguage/rain.factory#268 — and derived by slicing the creation
    /// code that library DOES produce, so the implementation address and the
    /// proxy's bytes are still stated in exactly one place.
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

    /// The address the clone lands at — the same one on every network where both
    /// the factory and the implementation are at the same address, which is what
    /// deploying both deterministically buys.
    /// @param clone The clone being deployed.
    /// @return The predicted clone address.
    function cloneDeployedAddress(CloneDeploy memory clone) internal pure returns (address) {
        return LibICloneableFactoryV4.predictCloneAddress(
            clone.factory, clone.implementation, LibICloneableFactoryV4.effectiveOpenSalt(clone.salt, clone.data)
        );
    }

    /// A clone as a `DeployCandidate`: every field derived, and the standard
    /// unanchorable reason.
    ///
    /// This is the declaration a consumer makes in one call. Each field was five
    /// hand-written derivations in every repo that wanted a clone declared, and
    /// every one of them a place to get the salt digest or the proxy layout
    /// subtly wrong while every check still passed — because a consistent
    /// snapshot of the wrong clone agrees with itself perfectly, and the source
    /// anchor that would catch it is the one thing an unanchorable candidate does
    /// not have.
    ///
    /// `dependencies` is empty, and that is a statement rather than an omission.
    /// A dependency entry is an address AND the runtime code that must be at it,
    /// and nothing here knows the implementation's runtime code. The
    /// implementation still MUST be on a network before a clone of it can be
    /// deployed there, and it is the factory that refuses otherwise:
    /// `LibICloneableFactoryV4.checkImplementationCode` reverts
    /// `ZeroImplementationCodeSize` atomically with the clone, so an absent
    /// implementation is a failed broadcast rather than a proxy delegating into
    /// nothing. A consumer that wants the stronger claim — that the
    /// implementation holds EXACTLY the audited code — declares the clone here
    /// and overrides the candidate's dependency list with the implementation's
    /// own published pin, which only it has.
    /// @param clone The clone being declared.
    /// @return The candidate, ready for `candidateSuites()`.
    function cloneCandidate(CloneDeploy memory clone) internal pure returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: clone.suite,
                creationCode: cloneCreationCode(clone.implementation),
                storedDeployedAddress: cloneDeployedAddress(clone),
                storedBytecodeHash: cloneDeployedCodehash(clone.implementation),
                storedRuntimeCode: cloneRuntimeCode(clone.implementation),
                artifactPath: CLONE_ARTIFACT_PATH,
                dependencies: new DeployDependency[](0)
            }),
            unanchorableReason: CLONE_UNANCHORABLE_REASON
        });
    }

    /// The CLONE mechanism as a `LibRainDeploy.deployStepToNetworks` step: the
    /// one thing a clone deploy does that a Zoltu deploy does not.
    ///
    /// `cloneDeterministicOpenSalt` in place of Zoltu's `CREATE2` over creation
    /// code, and the factory checked for itself in place of Zoltu's pinned code
    /// hash. Everything else — the networks, the forks, the skip, the
    /// assertions — is the shared loop's.
    ///
    /// The factory is read twice, for two different things: that it is there at
    /// all, and that it derives the same address this package does. The second
    /// is the check `CloneFactoryPredictionMismatch` exists for, and it runs
    /// BEFORE the broadcast window opens, because a clone that lands at an
    /// address nobody declared cannot be taken back.
    /// @param vm The Vm instance to broadcast with.
    /// @param network The network being deployed to, for a refusal to name.
    /// @param deployer The deployer address to broadcast as.
    /// @param cloneData The step data: an `abi.encode`d `CloneDeploy`.
    /// @return The address the factory deployed the clone to.
    function cloneDeployStep(Vm vm, string memory network, address deployer, bytes memory cloneData)
        internal
        returns (address)
    {
        CloneDeploy memory clone = abi.decode(cloneData, (CloneDeploy));

        console2.log(" - Clone Factory:", clone.factory);
        if (clone.factory.code.length == 0) {
            revert LibRainDeploy.MissingDependency(network, clone.factory);
        }

        address expectedAddress = cloneDeployedAddress(clone);
        address factoryPredictedAddress = ICloneableFactoryV4(clone.factory)
            .predictDeterministicAddressOpenSalt(clone.implementation, clone.data, clone.salt);
        if (factoryPredictedAddress != expectedAddress) {
            revert CloneFactoryPredictionMismatch(network, clone.factory, expectedAddress, factoryPredictedAddress);
        }

        console2.log(" - Cloning implementation:", clone.implementation);
        vm.startBroadcast(deployer);
        address cloneDeployedAddr =
            ICloneableFactoryV4(clone.factory).cloneDeterministicOpenSalt(clone.implementation, clone.data, clone.salt);
        vm.stopBroadcast();
        return cloneDeployedAddr;
    }

    /// Deploys the clone to each network through its factory's open salt:
    /// `LibRainDeploy.deployStepToNetworks` with `cloneDeployStep` as the
    /// mechanism.
    ///
    /// `expectedAddress` MUST be the address `clone` derives, which is checked
    /// HERE, before any network is forked — the same guard, in the same place, as
    /// the Zoltu path's. It is not a tautology: `expectedAddress` and
    /// `expectedCodeHash` come from the DECLARATION the broadcast selected, and
    /// `clone` from the clone list, so this is what refuses a repo whose
    /// candidate was not built from the clone inputs it is about to broadcast.
    /// Without it, a network already holding something else at the declared
    /// address takes the skip branch and reports success having deployed
    /// nothing.
    /// @param vm The Vm instance to use for forking and broadcasting.
    /// @param networks The list of network names to deploy to.
    /// @param deployer The deployer address.
    /// @param clone The clone to deploy.
    /// @param contractPath The contract path for verification commands.
    /// @param expectedAddress The declared clone address, which MUST be the one
    /// `clone` derives.
    /// @param expectedCodeHash The declared code hash of the deployed clone.
    /// @param dependencies The addresses that must already have code on a
    /// network before the clone can be broadcast there, each paired with the
    /// runtime code that must be at it.
    /// @return deployedAddress The deployed clone address.
    /// @return forkIds The fork each network was deployed on, as
    /// `deployStepToNetworks` hands them back.
    function cloneToNetworks(
        Vm vm,
        string[] memory networks,
        address deployer,
        CloneDeploy memory clone,
        string memory contractPath,
        address expectedAddress,
        bytes32 expectedCodeHash,
        DeployDependency[] memory dependencies
    ) internal returns (address deployedAddress, uint256[] memory forkIds) {
        if (networks.length == 0) {
            revert LibRainDeploy.NoNetworks();
        }
        address derivedAddress = cloneDeployedAddress(clone);
        if (derivedAddress != expectedAddress) {
            revert LibRainDeploy.UnexpectedDeployedAddress(expectedAddress, derivedAddress);
        }
        // Assigned to the named returns rather than returned directly from the
        // call. Identical behaviour, and it is what `unused-return` can see: the
        // detector reads a CROSS-LIBRARY call's return values as discarded where
        // the same forwarding inside `LibRainDeploy` is an internal call it does
        // not model, which is why `deployToNetworks` can `return` its own
        // forwarding and this cannot. A suppression here would be a directive
        // that outlives the detector's reason for firing; naming both values is
        // the shape that needs none.
        (deployedAddress, forkIds) = LibRainDeploy.deployStepToNetworks(
            vm,
            networks,
            deployer,
            cloneDeployStep,
            abi.encode(clone),
            contractPath,
            expectedAddress,
            expectedCodeHash,
            dependencies
        );
    }

    /// Deploys the clone to each network, broadcasting as the given private key.
    /// The clone half of `LibRainDeploy.deployAndBroadcast`, and the key handling
    /// is the same `rememberDeployer` rather than a second spelling of it.
    /// @param vm The Vm instance to use for forking and broadcasting.
    /// @param networks The list of network names to deploy to.
    /// @param deployerPrivateKey The private key to use for broadcasting.
    /// @param clone The clone to deploy.
    /// @param contractPath The contract path for verification commands.
    /// @param expectedAddress The declared clone address.
    /// @param expectedCodeHash The declared code hash of the deployed clone.
    /// @param dependencies The dependencies to check, each an address and the
    /// runtime code that must be at it.
    /// @return deployedAddress The deployed clone address.
    /// @return forkIds The fork each network was deployed on.
    function cloneAndBroadcast(
        Vm vm,
        string[] memory networks,
        uint256 deployerPrivateKey,
        CloneDeploy memory clone,
        string memory contractPath,
        address expectedAddress,
        bytes32 expectedCodeHash,
        DeployDependency[] memory dependencies
    ) internal returns (address deployedAddress, uint256[] memory forkIds) {
        if (networks.length == 0) {
            revert LibRainDeploy.NoNetworks();
        }
        return cloneToNetworks(
            vm,
            networks,
            LibRainDeploy.rememberDeployer(vm, deployerPrivateKey),
            clone,
            contractPath,
            expectedAddress,
            expectedCodeHash,
            dependencies
        );
    }
}
