// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {IERC5313} from "@openzeppelin-contracts-5.7.0/interfaces/IERC5313.sol";

import {DeploySuite, RainDeploySuitesBase} from "./RainDeploySuitesBase.sol";
import {DerivationSnapshotRevertFailed, LibRainDeployMechanism} from "../lib/LibRainDeployMechanism.sol";
import {LibRainDeploy, SupportedNetwork} from "../lib/LibRainDeploy.sol";
import {ChainBeacon, LibRainDeployBeacon} from "../lib/LibRainDeployBeacon.sol";

/// @notice A suite deployed as the deploy key would deploy it MUST NOT answer `owner()` with a first word whose low
/// 160 bits are the deploy key. Roles, pending owners, admin slots and contracts the suite's constructors create are
/// not read.
/// A beacon proxy suite is checked per network on its fork instead, as `BeaconProxySeatsDeployKey`.
/// @param suite The suite being broadcast.
/// @param deployed The address, deployed locally as the deploy key would, that answers `owner()` with a first word
/// whose low 160 bits are the deploy key.
error SuiteSeatsDeployKey(string suite, address deployed);

/// @notice The deploy key MUST NOT be a declared owner of any state of any beacon.
/// @param chainId The beacon's network.
/// @param beaconIndex The beacon's index in `beacons()`.
/// @param state The state index, as `LibRainDeployBeacon.stateAt` takes it.
error BeaconOwnedByDeployKey(uint256 chainId, uint256 beaconIndex, uint256 state);

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

    /// Refuses `BeaconOwnedByDeployKey` and `checkSeatsNoDeployKey`'s refusals before reading any network (so the
    /// suite's constructor MUST succeed locally, with only its declared dependencies etched, under each chain id that
    /// check reads), then broadcasts the selected suite by ITS mechanism, through `LibRainDeployMechanism` — the same
    /// dispatch every verification group derives through, so what is broadcast is what was verified.
    /// A beacon proxy suite's seat check is not one of these pre-fork refusals: it runs per network, on that
    /// network's fork, as `BeaconProxySeatsDeployKey`.
    /// The seat check reads a per-network release with its extended networks and every network its candidate adds.
    /// A per-network release is broadcast to a network it does not record only once `extendedNetworks` declares it
    /// there. Before any fork, such a network is refused with `ExtendedNetworkUnfrozen`, naming the address its
    /// candidate's init data derives there to declare, or with `CloneNetworkUndeclared` where its candidate has no
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
        address deployer = vm.addr(deployerPrivateKey);
        ChainBeacon[] memory chainBeacons = beacons();
        for (uint256 beaconIndex = 0; beaconIndex < chainBeacons.length; beaconIndex++) {
            for (uint256 state = 0; state <= chainBeacons[beaconIndex].beacon.transitions.length; state++) {
                if (LibRainDeployBeacon.stateAt(chainBeacons[beaconIndex].beacon, state).owner == deployer) {
                    revert BeaconOwnedByDeployKey(chainBeacons[beaconIndex].chainId, beaconIndex, state);
                }
            }
        }
        DeploySuite memory frozen = withExtendedNetworks(suite);
        DeploySuite memory candidate = candidateOf(frozen);
        checkSeatsNoDeployKey(
            LibRainDeployMechanism.withUnrecordedNetworks(
                frozen, candidate, LibRainDeployMechanism.addressChainIds(candidate)
            ),
            networks,
            deployer
        );
        return LibRainDeployMechanism.deployAndBroadcast(vm, networks, deployerPrivateKey, frozen, candidate);
    }

    /// Deploys `suite` locally with `deployer` as sender and origin, once under each target's chain id (a per-network
    /// clone suite only that network's clone), and refuses
    /// `SuiteSeatsDeployKey` when the target deployed for that chain id answers `owner()` with a first word whose
    /// low 160 bits are `deployer`. The targets are a per-network clone suite's networks, otherwise every one of
    /// `supportedNetworks()`, those this broadcast does not reach included, then each of `networks` not among them,
    /// so one network seating the deploy key refuses the broadcast to every network. The suite's constructor runs
    /// on the local EVM with only its declared dependencies etched, so it MUST succeed there under each target's
    /// chain id: one that reverts locally (say, by calling an undeclared contract under one chain id) refuses the
    /// broadcast to every network with its revert.
    /// A beacon proxy suite is only placed here, its frozen code over a beacon with no implementation, so its `owner()`
    /// is not read: its seat check is the per-network one in
    /// `LibRainDeployBeaconProxy.beaconProxyDeployStep`, on each network's fork, not this one.
    /// @param suite The suite to broadcast, with its extended networks and every network its candidate adds.
    /// @param networks The networks this broadcast reaches.
    /// @param deployer The deploy key's address.
    function checkSeatsNoDeployKey(DeploySuite memory suite, string[] memory networks, address deployer) internal {
        uint256[] memory chainIds = LibRainDeployMechanism.addressChainIds(suite);
        if (chainIds.length == 0) {
            SupportedNetwork[] memory supported = LibRainDeploy.declaredNetworkConfigs(supportedNetworks());
            SupportedNetwork[] memory dispatched = LibRainDeploy.declaredNetworkConfigs(networks);
            uint256 count = supported.length;
            for (uint256 i = 0; i < dispatched.length; i++) {
                if (!LibRainDeploy.hasChainId(supported, dispatched[i].chainId)) {
                    count++;
                }
            }
            chainIds = new uint256[](count);
            for (uint256 i = 0; i < supported.length; i++) {
                chainIds[i] = supported[i].chainId;
            }
            count = supported.length;
            for (uint256 i = 0; i < dispatched.length; i++) {
                if (!LibRainDeploy.hasChainId(supported, dispatched[i].chainId)) {
                    chainIds[count] = dispatched[i].chainId;
                    count++;
                }
            }
        }
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 snapshotId = vm.snapshotState();
            vm.chainId(chainIds[i]);
            vm.startPrank(deployer, deployer);
            LibRainDeployMechanism.deployLocallyOnChain(vm, suite);
            vm.stopPrank();
            address deployed = LibRainDeployMechanism.deployedAddress(suite, chainIds[i]);
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
