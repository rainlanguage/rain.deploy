// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {IERC5313} from "@openzeppelin-contracts-5.7.0/interfaces/IERC5313.sol";

import {
    DeployDeclaration,
    DeploySuite,
    DerivationSnapshotRevertFailed,
    RainDeploySuitesBase
} from "./RainDeploySuitesBase.sol";
import {LibRainDeploy, NetworkDeploys, SupportedNetwork} from "../lib/LibRainDeploy.sol";

/// @notice A suite deployed as the deploy key would deploy it MUST NOT answer `owner()` with a first word whose low
/// 160 bits are the deploy key. Roles, pending owners, admin slots and contracts the suite's constructors create are
/// not read.
/// @param suite The suite being broadcast.
/// @param deployed The address, deployed locally as the deploy key would, that answers `owner()` with a first word
/// whose low 160 bits are the deploy key.
error SuiteSeatsDeployKey(string suite, address deployed);

/// @title RainDeployBroadcast
/// @notice The broadcast, inherited rather than rewritten per repo.
abstract contract RainDeployBroadcast is RainDeploySuitesBase, Script {
    /// The networks to broadcast to. Every network the declaration supports by
    /// default, which is what a deterministic deployment usually wants: one
    /// address, every chain, in one dispatch.
    ///
    /// Overridable because that is not universal. A repo bootstrapping onto one
    /// chain at a time — `st0x.deploy` selects between Ethereum and HyperEVM
    /// per dispatch — returns a single-element list from its own env var
    /// instead. The reusable workflow already carries a `network:` input for
    /// exactly this.
    ///
    /// An override here narrows ONE dispatch: the networks it skips are still
    /// ones this repo deploys to and is verified on. A repo that deploys to
    /// fewer networks at all overrides `supportedNetworks` instead, which this
    /// defaults to.
    /// @return The network names to deploy to, as `[rpc_endpoints]` aliases.
    function deployNetworks(DeployDeclaration memory d) internal view virtual returns (string[] memory) {
        return d.networks;
    }

    /// Broadcasts the suite `DEPLOYMENT_SUITE` names.
    ///
    /// The source anchor runs FIRST, before a suite is selected and before the
    /// key is read. A snapshot the deploy reads and nothing anchors is a deploy
    /// of unknown bytes: everything else asked of a snapshot is internal to it,
    /// and the recorded-address guard `LibRainDeploy` applies before it forks
    /// anything compares two values out of the same generated file. That guard
    /// is what catches a stale PIN; only the anchor catches a snapshot of the
    /// wrong CONTRACT, and `CREATE2` at a zero salt means the wrong bytes take
    /// their own permanent address on every chain this reaches. It is run over
    /// the whole declaration rather than over the selected suite because the
    /// declaration is what a repo maintains and regenerates as a unit — a
    /// dispatch of one suite from a tree where another candidate has gone stale
    /// is a tree nobody should be broadcasting from at all.
    ///
    /// The suite is resolved before the key is read, so a mistyped suite fails
    /// in seconds listing the valid ones rather than failing on a missing
    /// `DEPLOYMENT_KEY` and sending the reader after the wrong thing.
    ///
    /// One suite per run, deliberately. Deploying through a shared factory in a
    /// single run couples every deployment to the others' success, and a suite
    /// that depends on another needs that other to be on chain first — which
    /// `dependencies` enforces per network, and which a caller satisfies by
    /// dispatching in order.
    function run() external {
        DeployDeclaration memory d = declaration();
        checkCandidatesAnchoredToSource(d);

        DeploySuite memory suite = suiteByName(d, vm.envOr("DEPLOYMENT_SUITE", string("")));

        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");

        broadcastSuite(d, suite, deployNetworks(d), deployerPrivateKey);
    }

    /// Refuses `checkSeatsNoDeployKey`'s refusals before reading any network (so the suite's constructor MUST succeed
    /// locally, with only its declared dependencies etched, under each chain id that check reads), then broadcasts the
    /// selected suite by ITS mechanism, through the mechanism hooks — the same dispatch every verification group
    /// derives through, so what is broadcast is what was verified. `suite` is not changed.
    /// @param suite The selected suite, as `DEPLOYMENT_SUITE` named it.
    /// @param networks The networks to broadcast to, as `deployNetworks()` gave them.
    /// @param deployerPrivateKey The key from `DEPLOYMENT_KEY`.
    /// @return Where the suite is on each network, positionally paired with `networks`.
    /// @return The fork each network was deployed on.
    function broadcastSuite(
        DeployDeclaration memory d,
        DeploySuite memory suite,
        string[] memory networks,
        uint256 deployerPrivateKey
    ) internal returns (address[] memory, uint256[] memory) {
        address deployer = vm.addr(deployerPrivateKey);
        DeploySuite memory frozen = abi.decode(abi.encode(suite), (DeploySuite));
        addRecordedNetworks(d, frozen);
        (DeploySuite memory candidate, bool found) = candidateOf(d, frozen.suite);
        if (!found) {
            candidate = abi.decode(abi.encode(frozen), (DeploySuite));
        }
        DeploySuite memory seated = abi.decode(abi.encode(frozen), (DeploySuite));
        addUnrecordedNetworks(d, seated, candidate, suiteChainIds(candidate));
        checkSeatsNoDeployKey(d, seated, seatTargets(seated, candidate, networks), deployer);
        return deployAndBroadcast(d, vm, networks, deployerPrivateKey, frozen, candidate);
    }

    /// Broadcasts `frozen`, with every network in play its candidate adds, to each of `networks` by its mechanism,
    /// then logs how to verify it. `frozen` is not changed.
    /// @param vm The Vm instance to broadcast with.
    /// @param networks The networks to broadcast to.
    /// @param deployerPrivateKey The deploy key.
    /// @param frozen The release with its recorded networks.
    /// @param candidate Its candidate, or a copy of `frozen` when it has none.
    /// @return Where the suite is on each network, positionally paired with `networks`.
    /// @return The fork each network was deployed on.
    function deployAndBroadcast(
        DeployDeclaration memory d,
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
        DeploySuite memory suite = abi.decode(abi.encode(frozen), (DeploySuite));
        addUnrecordedNetworks(d, suite, candidate, LibRainDeploy.networkChainIds(configs));
        checkNetworksFrozen(d, frozen, suite, networks);
        NetworkDeploys memory deploys = NetworkDeploys({
            deployStepData: new bytes[](configs.length),
            expectedAddresses: new address[](configs.length),
            derivedAddresses: new address[](configs.length)
        });
        for (uint256 i = 0; i < configs.length; i++) {
            deploys.deployStepData[i] = deployStepData(d, suite, configs[i].chainId);
            deploys.expectedAddresses[i] = recordedAddress(d, suite, configs[i].chainId);
            deploys.derivedAddresses[i] = deployedAddress(d, suite, configs[i].chainId);
        }
        uint256[] memory forkIds = LibRainDeploy.deployStepToNetworks(
            vm,
            configs,
            LibRainDeploy.rememberDeployer(vm, deployerPrivateKey),
            deployStep(d, suite),
            deploys,
            suite.storedBytecodeHash,
            suite.dependencies
        );
        logVerification(d, vm, networks, suite, deploys.expectedAddresses);
        return (deploys.expectedAddresses, forkIds);
    }

    /// The chain ids `checkSeatsNoDeployKey` deploys under: those of `suite`'s networks, then of `candidate`'s not
    /// among them, then of `networks` not among those, so one network seating the deploy key refuses the broadcast
    /// to every network.
    /// @param suite The suite to broadcast, with its recorded networks and every network its candidate adds.
    /// @param candidate Its candidate.
    /// @param networks The networks this broadcast reaches.
    /// @return The chain ids.
    function seatTargets(DeploySuite memory suite, DeploySuite memory candidate, string[] memory networks)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory own = suiteChainIds(suite);
        uint256[] memory candidates = suiteChainIds(candidate);
        uint256[] memory dispatched = LibRainDeploy.networkChainIds(LibRainDeploy.declaredNetworkConfigs(networks));
        uint256[] memory targets = new uint256[](own.length + candidates.length + dispatched.length);
        uint256 count = 0;
        for (uint256 i = 0; i < targets.length; i++) {
            uint256 chainId = i < own.length
                ? own[i]
                : i < own.length + candidates.length
                    ? candidates[i - own.length]
                    : dispatched[i - own.length - candidates.length];
            bool seen = false;
            for (uint256 j = 0; j < count; j++) {
                if (targets[j] == chainId) {
                    seen = true;
                    break;
                }
            }
            if (!seen) {
                targets[count++] = chainId;
            }
        }
        assembly ("memory-safe") {
            mstore(targets, count)
        }
        return targets;
    }

    /// Deploys `suite` locally with `deployer` as sender and origin, once under each of `chainIds`, and refuses
    /// `SuiteSeatsDeployKey` when the address deployed for that chain id answers `owner()` with a first word whose
    /// low 160 bits are `deployer`. The suite's constructor runs on the local EVM with only its declared dependencies
    /// etched, so it MUST succeed there under each chain id: one that reverts locally (say, by calling an undeclared
    /// contract under one chain id) refuses the broadcast to every network with its revert.
    /// @param suite The suite to broadcast, with its recorded networks and every network its candidate adds.
    /// @param chainIds The chain ids to deploy under.
    /// @param deployer The deploy key's address.
    function checkSeatsNoDeployKey(
        DeployDeclaration memory d,
        DeploySuite memory suite,
        uint256[] memory chainIds,
        address deployer
    ) internal {
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 snapshotId = vm.snapshotState();
            vm.chainId(chainIds[i]);
            vm.startPrank(deployer, deployer);
            deployLocallyOnChain(d, vm, suite);
            vm.stopPrank();
            address deployed = deployedAddress(d, suite, chainIds[i]);
            // slither-disable-next-line low-level-calls
            (bool answered, bytes memory owner) = deployed.staticcall(abi.encodeCall(IERC5313.owner, ()));
            // Restores the chain id with the state.
            if (!vm.revertToState(snapshotId)) {
                revert DerivationSnapshotRevertFailed(suite.suite, snapshotId);
            }
            if (answered && owner.length >= 0x20 && address(uint160(abi.decode(owner, (uint256)))) == deployer) {
                revert SuiteSeatsDeployKey(suite.suite, deployed);
            }
        }
    }
}
