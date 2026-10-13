// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {ICloneableFactoryV4} from "rain-factory-0.1.30/src/interface/ICloneableFactoryV4.sol";
import {LibICloneableFactoryV4} from "rain-factory-0.1.30/src/lib/LibICloneableFactoryV4.sol";

import {DeployDependency, LibRainDeploy, SupportedNetwork} from "./LibRainDeploy.sol";

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

/// What a clone factory is asked to deploy: the four values its open-salt
/// `CREATE2` is a function of.
///
/// The clone half of a suite's mechanism. A clone `DeploySuite` carries it
/// `abi.encode`d in `mechanismData`, so the broadcast, the local derivation,
/// the frozen record match and the snapshot writer all decode the SAME four
/// values from the one entry they were handed.
///
/// The OPEN salt rather than the namespaced one, because this is a deploy
/// framework whose point is one address on every network: the open-salt digest
/// covers the implementation and the init data and NOT the caller, so every
/// account reaches the same address and a racer can only deploy the clone that
/// was specified. The namespaced derivation bakes a deploying account into the
/// address, which a retired key makes unreachable forever.
struct CloneTarget {
    /// The `ICloneableFactoryV4` that deploys the clone. MUST be a declared
    /// dependency of the suite, with its runtime code — see
    /// `LibRainDeployClone.checkCloneDependencies`.
    address factory;
    /// The contract the proxy delegates into. Its address is embedded in the
    /// proxy's runtime code, so the recorded code hash is what says which
    /// implementation a deployed clone delegates to. MUST be a declared
    /// dependency of the suite, with its runtime code.
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

/// One network's clone, as a per-network clone suite records it: the init data
/// on that network and the address that data puts the clone at.
struct CloneNetwork {
    /// The chain id of the network.
    uint256 chainId;
    /// The init data on that network. See `CloneTarget.data`.
    bytes data;
    /// The address recorded for the clone on that network. A recorded output,
    /// checked against the derivation for the reason `DeploySuite` records
    /// `storedDeployedAddress` rather than deriving it.
    address deployedAddress;
}

/// A clone whose init data differs by network, and therefore whose address
/// does: the clone half of a `DeployMechanism.ClonePerNetwork` suite, carried
/// `abi.encode`d in its `mechanismData`.
///
/// Every network the clone is deployed to or verified on MUST have an entry.
/// A network without one is refused with
/// `LibRainDeployClone.CloneNetworkUndeclared`, never given some other
/// network's data: the init data is what the clone is initialized with, so a
/// defaulted network is a clone initialized with values nobody declared for it.
///
/// The factory, the implementation and the salt are the same on every network.
/// So is the code hash: an EIP-1167 clone's runtime code embeds only the
/// implementation address, so one recorded code hash serves every network.
struct CloneNetworks {
    /// See `CloneTarget.factory`.
    address factory;
    /// See `CloneTarget.implementation`.
    address implementation;
    /// See `CloneTarget.salt`.
    bytes32 salt;
    /// One entry per network, keyed by chain id. MUST NOT be empty and MUST
    /// NOT name a chain id twice.
    CloneNetwork[] networks;
}

/// One contract a repo deploys as an EIP-1167 clone, as a clone repo declares
/// it: the suite key, the `CloneTarget` fields, and the dependencies.
///
/// The init data is declared one of two ways. A clone initialized with the
/// same bytes everywhere declares them in `data`, leaves `initDataPerNetwork`
/// false and gives `LibRainDeployClone.noInitDataPerNetwork` as `initData`; it
/// lands at one address on every network. A clone initialized differently per
/// network — an admin that is a different account on one chain — sets
/// `initDataPerNetwork`, leaves `data` empty and gives `initData`, ONE function
/// from a chain id to that network's init data. It is read for the chain id of
/// every network in the repo's `supportedNetworks()`, in that order, so the
/// clone lands at a different address wherever its data differs, and a network
/// the function has no data for reverts rather than being defaulted.
///
/// `LibRainDeployMechanism.cloneCandidate` turns it into the candidate every
/// other part of this package reads, so the declaration is this one entry.
struct CloneDeploy {
    /// The suite key, held to the key alphabet and to uniqueness by
    /// `RainDeploySuitesBase.allSuites` like any other — the candidate this
    /// becomes carries it, so there is no second rule for a clone's key.
    string suite;
    /// See `CloneTarget.factory`.
    address factory;
    /// See `CloneTarget.implementation`.
    address implementation;
    /// The init data on every network. See `CloneTarget.data`. MUST be empty
    /// when `initDataPerNetwork` is set.
    bytes data;
    /// Whether the init data is `initData` per network rather than `data` on
    /// every network.
    bool initDataPerNetwork;
    /// The init data on the network with the given chain id. Read for each
    /// supported network when `initDataPerNetwork` is set, and never read
    /// otherwise. MUST revert for a chain id it has no init data for.
    function(uint256) view returns (bytes memory) initData;
    /// See `CloneTarget.salt`.
    bytes32 salt;
    /// What MUST already be on a network, with exactly this code, before the
    /// clone is broadcast there. MUST include the factory and the
    /// implementation: the factory's entry is what pins the code that runs
    /// `cloneDeterministicOpenSalt`, and the implementation's is what pins the
    /// code every call into the clone delegates to. The consumer declares them
    /// because it is the one that depends on the factory's and the
    /// implementation's published pins; this package cannot, since
    /// `rain-factory-deploy` depends on it.
    DeployDependency[] dependencies;
}

/// @title LibRainDeployClone
/// @notice The CLONE mechanism: an EIP-1167 clone through an
/// `ICloneableFactoryV4` at its open salt, derived and broadcast through the
/// same machinery as a Zoltu deploy.
///
/// The derivations are `rain-factory`'s own — `cloneCreationCode`,
/// `effectiveOpenSalt`, `predictCloneAddress` — so this package carries no
/// second spelling of the proxy layout or the salt digest, bar the one prefix
/// length `EIP1167_CREATION_CODE_PREFIX_LENGTH` names.
///
/// `cloneToNetworks` hands `cloneDeployStep` to
/// `LibRainDeploy.deployStepToNetworks`. The loop is NOT reimplemented here: the
/// network list, the forks created before any is selected, the skip where the
/// clone is already at its address, the declared dependency checks and the
/// address and code hash assertions are the same loop a Zoltu deploy runs.
///
/// Nothing here knows about `DeploySuite`. `LibRainDeployMechanism` is what
/// reads a suite and dispatches to this library.
library LibRainDeployClone {
    /// Thrown when the clone factory on a network does not derive the address
    /// this package derives for the same clone.
    ///
    /// This catches a factory whose `predictDeterministicAddressOpenSalt`
    /// disagrees with `rain-factory`'s formula — not an `ICloneableFactoryV4` at
    /// all, a different open-salt domain tag, a different proxy layout — on the
    /// live network, before anything is broadcast, and independently of any
    /// test having run. It says nothing about what `cloneDeterministicOpenSalt`
    /// itself does, such as what it passes to `initialize`. The declared factory
    /// dependency covers that: its runtime code is pinned on every network
    /// before the step runs.
    /// @param network The network whose factory was read, for the refusal to
    /// name.
    /// @param factory The factory that was asked.
    /// @param expected The address this package derives for the clone.
    /// @param predicted The address the factory says it would deploy to.
    error CloneFactoryPredictionMismatch(string network, address factory, address expected, address predicted);

    /// Thrown when a clone's factory or implementation is not among the
    /// dependencies declared beside it.
    ///
    /// Both are required. Without the factory's entry nothing pins the code
    /// that performs the clone; without the implementation's, nothing pins the
    /// code the clone delegates to, and the recorded code hash only says WHICH
    /// address it delegates to.
    /// @param dependency The factory or implementation address no declared
    /// dependency names.
    error CloneDependencyUndeclared(address dependency);

    /// Thrown when a per-network clone names no network at all. Every check
    /// over its networks would pass having checked nothing.
    error NoCloneNetworks();

    /// Thrown when a per-network clone names one chain id twice, so which
    /// init data that network gets would depend on which entry a reader
    /// happened to stop at.
    /// @param chainId The chain id named more than once.
    error DuplicateCloneNetwork(uint256 chainId);

    /// Thrown when a per-network clone is asked for a network it has no entry
    /// for. Refused rather than defaulted: the init data is what the clone is
    /// initialized with, and no other network's data was declared for this
    /// one.
    /// @param chainId The chain id with no entry.
    error CloneNetworkUndeclared(uint256 chainId);

    /// Thrown when a per-network clone step finds itself on a network whose
    /// chain id is not the one its init data was resolved for: an endpoint
    /// that serves a different chain than its name says. Broadcasting there
    /// would initialize the clone with another network's data.
    /// @param network The network name the step was handed.
    /// @param declared The chain id the init data was resolved for.
    /// @param reported The chain id the network reports.
    error CloneNetworkChainIdMismatch(string network, uint256 declared, uint256 reported);

    /// Thrown by `noInitDataPerNetwork`, the `initData` of a clone whose init
    /// data is `data` on every network.
    /// @param chainId The chain id it was asked for.
    error NoInitDataPerNetwork(uint256 chainId);

    /// The `CloneDeploy.initData` of a clone whose init data is `data` on every
    /// network. Nothing reads it; it reverts if anything does.
    /// @param chainId The chain id asked for.
    /// @return Never returns.
    function noInitDataPerNetwork(uint256 chainId) internal pure returns (bytes memory) {
        revert NoInitDataPerNetwork(chainId);
    }

    /// The clone's creation code: the EIP-1167 initcode the factory `CREATE2`s,
    /// from `rain-factory`'s own helper.
    ///
    /// Recorded on a clone suite as its `creationCode` even though nothing
    /// broadcasts it — the clone factory is handed the implementation, not these
    /// bytes. It is the snapshot's statement of WHAT is deployed, and the local
    /// derivation requires it to be exactly this.
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
    /// @param target The clone being deployed.
    /// @return The predicted clone address.
    function cloneDeployedAddress(CloneTarget memory target) internal pure returns (address) {
        return LibICloneableFactoryV4.predictCloneAddress(
            target.factory, target.implementation, LibICloneableFactoryV4.effectiveOpenSalt(target.salt, target.data)
        );
    }

    /// Requires the clone's factory AND implementation to be among the declared
    /// dependencies.
    ///
    /// Membership by address. The runtime code each entry carries is what
    /// `LibRainDeploy.checkDeclaredDependencies` holds every network to before
    /// the step runs, and what a local derivation etches.
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

    /// Requires a per-network clone to name at least one network, no chain id
    /// twice, and its factory and implementation among the declared
    /// dependencies.
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

    /// The `CloneTarget` one entry of a per-network clone describes: the shared
    /// factory, implementation and salt, with that entry's init data.
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

    /// The CLONE mechanism as a `LibRainDeploy.deployStepToNetworks` step: the
    /// one thing a clone deploy does that a Zoltu deploy does not.
    ///
    /// `cloneDeterministicOpenSalt` in place of Zoltu's `CREATE2` over creation
    /// code. The factory's presence and runtime code were already checked by
    /// the shared loop, as a declared dependency, before this runs — which is
    /// why the step reads it without a presence check of its own: only
    /// `cloneToNetworks` hands this step to the loop, and it refuses a target
    /// whose factory is undeclared. The factory's prediction is
    /// read here too, BEFORE the broadcast window opens — see
    /// `CloneFactoryPredictionMismatch` for what that catches and what it does
    /// not.
    /// @param vm The Vm instance to broadcast with.
    /// @param network The network being deployed to, for a refusal to name.
    /// @param deployer The deployer address to broadcast as.
    /// @param targetData The step data: an `abi.encode`d `CloneTarget`.
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

    /// `cloneDeployStep` for one network of a per-network clone: the same step,
    /// after requiring the selected network to report the chain id the init
    /// data was resolved for.
    ///
    /// The network list is names and the init data is keyed by chain id, so
    /// the name's chain id is resolved from the catalogue before any fork. An
    /// endpoint serving a different chain than its name is the one way that
    /// resolution can be wrong on the network itself, and on a per-network
    /// clone that is a clone initialized with another network's data, so the
    /// step reads `block.chainid` before it broadcasts.
    /// @param vm The Vm instance to broadcast with.
    /// @param network The network being deployed to, for a refusal to name.
    /// @param deployer The deployer address to broadcast as.
    /// @param stepData The step data: the `abi.encode`d chain id and
    /// `CloneTarget` resolved for this network.
    /// @return The address the factory deployed the clone to.
    function cloneNetworkDeployStep(Vm vm, string memory network, address deployer, bytes memory stepData)
        internal
        returns (address)
    {
        (uint256 chainId, CloneTarget memory target) = abi.decode(stepData, (uint256, CloneTarget));
        if (block.chainid != chainId) {
            revert CloneNetworkChainIdMismatch(network, chainId, block.chainid);
        }
        return cloneDeployStep(vm, network, deployer, abi.encode(target));
    }

    /// Deploys the clone to each network through its factory's open salt:
    /// `LibRainDeploy.deployStepToNetworks` with `cloneDeployStep` as the
    /// mechanism.
    ///
    /// Before any network is forked: the factory and the implementation MUST be
    /// declared dependencies, and `expectedAddress` MUST be the address `target`
    /// derives — the same guard, in the same place, as the Zoltu path's. The
    /// latter is not a tautology: `expectedAddress` is the suite's RECORDED
    /// address, so this refuses a suite whose record was not cut from the clone
    /// it is about to broadcast. Without it, a network already holding something
    /// else at the recorded address takes the skip branch and reports success
    /// having deployed nothing.
    ///
    /// Per network, the shared loop then holds every declared dependency —
    /// factory and implementation included — to its declared runtime code
    /// before the step runs.
    /// @param vm The Vm instance to use for forking and broadcasting.
    /// @param networks The list of network names to deploy to.
    /// @param deployer The deployer address.
    /// @param target The clone to deploy.
    /// @param contractPath The contract path for verification commands.
    /// @param expectedAddress The recorded clone address, which MUST be the one
    /// `target` derives.
    /// @param expectedCodeHash The recorded code hash of the deployed clone.
    /// @param dependencies The addresses that must already have code on a
    /// network before the clone can be broadcast there, each paired with the
    /// runtime code that must be at it. MUST include the factory and the
    /// implementation.
    /// @return deployedAddress The deployed clone address.
    /// @return forkIds The fork each network was deployed on, as
    /// `deployStepToNetworks` hands them back.
    function cloneToNetworks(
        Vm vm,
        string[] memory networks,
        address deployer,
        CloneTarget memory target,
        string memory contractPath,
        address expectedAddress,
        bytes32 expectedCodeHash,
        DeployDependency[] memory dependencies
    ) internal returns (address deployedAddress, uint256[] memory forkIds) {
        if (networks.length == 0) {
            revert LibRainDeploy.NoNetworks();
        }
        checkCloneDependencies(target, dependencies);
        address derivedAddress = cloneDeployedAddress(target);
        if (derivedAddress != expectedAddress) {
            revert LibRainDeploy.UnexpectedDeployedAddress(expectedAddress, derivedAddress);
        }
        (bytes[] memory stepData, address[] memory expectedAddresses) =
            LibRainDeploy.everyNetwork(networks.length, abi.encode(target), expectedAddress);
        forkIds = LibRainDeploy.deployStepToNetworks(
            vm,
            networks,
            deployer,
            cloneDeployStep,
            stepData,
            contractPath,
            expectedAddresses,
            expectedCodeHash,
            dependencies
        );
        deployedAddress = expectedAddress;
    }

    /// Deploys the clone to each network, broadcasting as the given private key.
    /// The clone half of `LibRainDeploy.deployAndBroadcast`, and the key handling
    /// is the same `rememberDeployer` rather than a second spelling of it.
    /// @param vm The Vm instance to use for forking and broadcasting.
    /// @param networks The list of network names to deploy to.
    /// @param deployerPrivateKey The private key to use for broadcasting.
    /// @param target The clone to deploy.
    /// @param contractPath The contract path for verification commands.
    /// @param expectedAddress The recorded clone address.
    /// @param expectedCodeHash The recorded code hash of the deployed clone.
    /// @param dependencies The dependencies to check, each an address and the
    /// runtime code that must be at it. MUST include the factory and the
    /// implementation.
    /// @return deployedAddress The deployed clone address.
    /// @return forkIds The fork each network was deployed on.
    function cloneAndBroadcast(
        Vm vm,
        string[] memory networks,
        uint256 deployerPrivateKey,
        CloneTarget memory target,
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
            target,
            contractPath,
            expectedAddress,
            expectedCodeHash,
            dependencies
        );
    }

    /// Deploys a per-network clone to each network through its factory's open
    /// salt: `LibRainDeploy.deployStepToNetworks` with `cloneNetworkDeployStep`
    /// as the mechanism, and each network's own init data and address.
    ///
    /// Before any network is forked: the clone MUST pass
    /// `checkCloneNetworks`, every network MUST be in the catalogue and have an
    /// entry for its chain id — `CloneNetworkUndeclared` otherwise, so a
    /// network the declaration says nothing about stops the run before
    /// anything is broadcast anywhere — and each entry's recorded address MUST
    /// be the address its init data derives, for the reason `cloneToNetworks`
    /// requires that of its one address.
    /// @param vm The Vm instance to use for forking and broadcasting.
    /// @param networks The list of network names to deploy to.
    /// @param deployer The deployer address.
    /// @param clones The per-network clone, with each network's recorded
    /// address.
    /// @param contractPath The contract path for verification commands.
    /// @param expectedCodeHash The recorded code hash of the deployed clone,
    /// the same on every network.
    /// @param dependencies The addresses that must already have code on a
    /// network before the clone can be broadcast there, each paired with the
    /// runtime code that must be at it. MUST include the factory and the
    /// implementation.
    /// @return deployedAddresses The clone's address on each network,
    /// positionally paired with `networks`.
    /// @return forkIds The fork each network was deployed on.
    function cloneNetworksToNetworks(
        Vm vm,
        string[] memory networks,
        address deployer,
        CloneNetworks memory clones,
        string memory contractPath,
        bytes32 expectedCodeHash,
        DeployDependency[] memory dependencies
    ) internal returns (address[] memory deployedAddresses, uint256[] memory forkIds) {
        if (networks.length == 0) {
            revert LibRainDeploy.NoNetworks();
        }
        checkCloneNetworks(clones, dependencies);
        SupportedNetwork[] memory configs = LibRainDeploy.declaredNetworkConfigs(networks);
        bytes[] memory stepData = new bytes[](networks.length);
        deployedAddresses = new address[](networks.length);
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 index = cloneNetworkIndex(clones, configs[i].chainId);
            CloneTarget memory target = cloneNetworkTarget(clones, index);
            address derivedAddress = cloneDeployedAddress(target);
            if (derivedAddress != clones.networks[index].deployedAddress) {
                revert LibRainDeploy.UnexpectedDeployedAddress(clones.networks[index].deployedAddress, derivedAddress);
            }
            stepData[i] = abi.encode(configs[i].chainId, target);
            deployedAddresses[i] = derivedAddress;
        }
        forkIds = LibRainDeploy.deployStepToNetworks(
            vm,
            networks,
            deployer,
            cloneNetworkDeployStep,
            stepData,
            contractPath,
            deployedAddresses,
            expectedCodeHash,
            dependencies
        );
    }

    /// Deploys a per-network clone to each network, broadcasting as the given
    /// private key: `cloneNetworksToNetworks` as `cloneAndBroadcast` is
    /// `cloneToNetworks`.
    /// @param vm The Vm instance to use for forking and broadcasting.
    /// @param networks The list of network names to deploy to.
    /// @param deployerPrivateKey The private key to use for broadcasting.
    /// @param clones The per-network clone, with each network's recorded
    /// address.
    /// @param contractPath The contract path for verification commands.
    /// @param expectedCodeHash The recorded code hash of the deployed clone.
    /// @param dependencies The dependencies to check, each an address and the
    /// runtime code that must be at it. MUST include the factory and the
    /// implementation.
    /// @return deployedAddresses The clone's address on each network.
    /// @return forkIds The fork each network was deployed on.
    function cloneNetworksAndBroadcast(
        Vm vm,
        string[] memory networks,
        uint256 deployerPrivateKey,
        CloneNetworks memory clones,
        string memory contractPath,
        bytes32 expectedCodeHash,
        DeployDependency[] memory dependencies
    ) internal returns (address[] memory deployedAddresses, uint256[] memory forkIds) {
        if (networks.length == 0) {
            revert LibRainDeploy.NoNetworks();
        }
        return cloneNetworksToNetworks(
            vm,
            networks,
            LibRainDeploy.rememberDeployer(vm, deployerPrivateKey),
            clones,
            contractPath,
            expectedCodeHash,
            dependencies
        );
    }
}
