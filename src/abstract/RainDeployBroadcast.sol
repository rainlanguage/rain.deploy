// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";

import {DeploySuite, RainDeploySuitesBase} from "./RainDeploySuitesBase.sol";
import {LibRainDeployMechanism} from "../lib/LibRainDeployMechanism.sol";

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
    function deployNetworks() internal view virtual returns (string[] memory) {
        return supportedNetworks();
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
        checkCandidatesAnchoredToSource();

        DeploySuite memory suite = suiteByName(vm.envOr("DEPLOYMENT_SUITE", string("")));

        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");

        broadcastSuite(suite, deployNetworks(), deployerPrivateKey);
    }

    /// Broadcasts the selected suite by ITS mechanism, through `LibRainDeployMechanism` — the same
    /// dispatch every verification group derives through, so what is broadcast is what was
    /// verified. A per-network release is broadcast to a network it does not record only once `extendedNetworks`
    /// declares it there. Before any fork, such a network is refused with `ExtendedNetworkUnfrozen`, naming the address
    /// its candidate's init data derives there to declare, or with `CloneNetworkUndeclared` where its candidate has no
    /// entry there.
    /// @param suite The selected suite, as `DEPLOYMENT_SUITE` named it.
    /// @param networks The networks to broadcast to, as `deployNetworks()` gave them.
    /// @param deployerPrivateKey The key from `DEPLOYMENT_KEY`.
    /// @return Where the suite is on each network, positionally paired with `networks`.
    /// @return The fork each network was deployed on.
    function broadcastSuite(DeploySuite memory suite, string[] memory networks, uint256 deployerPrivateKey)
        internal
        returns (address[] memory, uint256[] memory)
    {
        DeploySuite memory frozen = withExtendedNetworks(suite);
        return LibRainDeployMechanism.deployAndBroadcast(vm, networks, deployerPrivateKey, frozen, candidateOf(frozen));
    }
}
