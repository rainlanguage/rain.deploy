// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {DerivedDeploy, RainDeployVerifyBase} from "./RainDeployVerifyBase.sol";
import {DeploySuite} from "./RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "../lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../lib/LibRainDeployMechanism.sol";

/// @title RainDeployVerifyChain
/// @notice The only deploy-pin assertions anchored to something outside the
/// repo: across every network the declaration's `supportedNetworks()` names,
/// every RELEASED suite's derived address carries code with its derived code
/// hash over declared dependencies that carry the code declared for them, and
/// every chain id `[etherscan]` declares is the one that network's alias forks.
///
/// The declaration's networks, through the same hook
/// `RainDeployBroadcast.deployNetworks()` defaults to, so a repo deploying to a
/// subset is held to that subset and cannot be verified on fewer networks than
/// it broadcasts to.
///
/// This is the only group that can catch a suite that never deployed to a
/// network, or that is not there any more. Neither is a fact the repo can hold:
/// both can go false with nobody touching it — a release that reached some
/// chains and not others, a chain added to `supportedNetworks()` after a
/// release that therefore never got it, a deploy that silently failed.
///
/// ## Released only, for the same reason source anchors the candidate only
///
/// A release IS a deployment that happened. That is what its recorded bytes
/// describe and why they are frozen, so "it is on every network" is a claim
/// about it that is either true or a defect. The candidate is what the NEXT
/// release will be: between releases it is ordinarily ahead of anything on
/// chain, and a repo whose source has moved since its last deploy is the
/// normal state of a repo, not a fault in it. Demanding the candidate be live
/// asserts something false by design.
///
/// The two exemptions are the same shape from opposite ends —
/// `RainDeployVerifySnapshot` anchors the candidate to source and never a
/// release, because a release is meant to have diverged from source; this
/// anchors releases to the chain and never the candidate, because the
/// candidate is meant to be ahead of the chain. Neither is a field a caller
/// can set: there is nothing to opt a suite into or out of.
///
/// That puts the whole weight on `releasedSuites()` naming every release. A
/// frozen tag missing from it would be a release nothing here is ever handed,
/// and a check that is never handed a subject cannot fail on it — so
/// `RainDeployVerifySnapshot` checks that declaration against the append-only
/// `src/generated/<tag>/` record. Without that, scoping to releases would be a
/// way to make this contract quiet rather than correct.
///
/// The matrix is suites by networks and is generated from both, so a new
/// network leaves no suite unchecked and a new release is checked on every
/// network from the moment it is declared. There are deliberately no per-chain
/// or per-suite functions to add.
///
/// ## One bad cell ends the run, at that cell
///
/// Generated from both lists is a statement about what gets CHECKED, not a
/// promise that every cell gets REPORTED. The first missing or mismatched cell
/// reverts and the run stops on that network, so a release that reached one
/// network of nine is enumerated one red run per cell.
///
/// That is the trade, not an oversight. The error names the network and the
/// address, and the log the suite, so one cell is actionable on its own;
/// deploying is idempotent by construction, so a partial release is fixed by
/// running the deploy again rather than by knowing the whole shape first; and
/// stopping spends no further RPC on a run whose answer is already red.
/// Reporting every cell means this check becomes a collector with a summary
/// error, which is a larger contract bought with fewer red runs.
///
/// It compares against the DERIVED code hash rather than the recorded one, so
/// the creation code stays the only parameter. `RainDeployVerifySnapshot` is
/// what ties the derivation back to the recorded constants; the two together
/// say the recorded set describes what is actually live.
///
/// Kept in its own contract, away from every assertion about the snapshot, so
/// an unreachable RPC endpoint fails only this. It cannot take down the
/// snapshot checks with it, and its failures are legible: a fork that cannot be created
/// is an outage, while `NotDeployedOnNetwork` from a fork that was created is a
/// missing deployment. A contract boundary is what `forge test
/// --match-contract` and a CI job select at, and it is structural rather than
/// conventional — nothing reachable from the snapshot contract forks anything.
/// `RainDeployVerify` is what a repo binds, and this stays a contract of its
/// own so that binding the snapshot half alone remains a thing a
/// credential-free job can do.
abstract contract RainDeployVerifyChain is RainDeployVerifyBase {
    /// Checks every suite against every supported network: `checkDeployedOnNetworks`
    /// over the catalogue entries `LibRainDeploy.declaredNetworkConfigs` gives
    /// for `supportedNetworks()`.
    /// @param suites The suites to check.
    function checkDeployedOnSupportedNetworks(DeploySuite[] memory suites) internal {
        checkDeployedOnNetworks(LibRainDeploy.declaredNetworkConfigs(supportedNetworks()), suites);
    }

    /// Checks every suite against every given network, forking each network
    /// once and checking every suite on it.
    ///
    /// Everything compared is computed before anything forks. The code hashes
    /// are derived first because on a fork the derived address is the very
    /// address the deployment under test occupies, so deriving there would
    /// either collide with it or read it back as its own expectation. Each
    /// suite's address on each network is resolved first too, by that
    /// network's chain id from its catalogue entry: a per-network clone has a
    /// different address per network, and refuses a network it declares
    /// nothing for with `LibRainDeployClone.CloneNetworkUndeclared` — before
    /// any endpoint is touched, rather than partway down the list.
    ///
    /// Each suite goes through `onSupportedNetworks` first, so a per-network
    /// clone release is checked on a supported network it was not cut for at
    /// the address the declaration's init data derives there — where a
    /// broadcast of it puts it — and on every network it records at the
    /// address its record derives.
    ///
    /// On each network, the fork MUST first report the chain id its catalogue
    /// entry declares, by `LibRainDeploy.checkNetworkChainId` — the check a
    /// broadcast makes there — since every address checked on it was resolved
    /// from that chain id. Then every suite's declared dependencies are checked
    /// before its code, by `LibRainDeploy.checkDeclaredDependencies` and
    /// `LibRainDeploy.checkDeployedCode`, as a broadcast does. A suite's code
    /// is what it is with them: a clone's runtime code says only WHICH implementation
    /// it delegates to, so a clone at its address over an implementation that
    /// is missing or changed has the right code hash and does not work.
    /// @param networks The catalogue entry of each network to check on.
    /// @param suites The suites to check.
    function checkDeployedOnNetworks(SupportedNetwork[] memory networks, DeploySuite[] memory suites) internal {
        // Nothing to check is not a reason to touch every RPC endpoint. Forking
        // to check nothing turns an outage into the failure of an assertion
        // that has no subject, which is the one failure this contract is
        // supposed to be legible against.
        if (suites.length == 0) {
            return;
        }

        DeploySuite[] memory onNetworks = new DeploySuite[](suites.length);
        for (uint256 j = 0; j < suites.length; j++) {
            onNetworks[j] = onSupportedNetworks(suites[j]);
        }
        suites = onNetworks;

        DerivedDeploy[] memory derived = deriveDeployments(suites);
        address[][] memory addresses = new address[][](networks.length);
        for (uint256 i = 0; i < networks.length; i++) {
            addresses[i] = new address[](suites.length);
            for (uint256 j = 0; j < suites.length; j++) {
                addresses[i][j] = LibRainDeployMechanism.deployedAddress(suites[j], networks[i].chainId);
            }
        }

        uint256[] memory forkIds = LibRainDeploy.createForks(vm, LibRainDeploy.networkNames(networks));
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            LibRainDeploy.checkNetworkChainId(networks[i]);
            for (uint256 j = 0; j < suites.length; j++) {
                console2.log("Checking suite on network:", derived[j].suite, networks[i].name);
                LibRainDeploy.checkDeclaredDependencies(networks[i].name, suites[j].dependencies);
                LibRainDeploy.checkDeployedCode(networks[i].name, addresses[i][j], derived[j].bytecodeHash);
            }
        }
    }

    /// Every RELEASED suite MUST be live, with the code its creation code
    /// produces and its declared dependencies under it, on every supported
    /// network.
    function testSuitesLiveOnEverySupportedNetwork() external {
        checkDeployedOnSupportedNetworks(releasedSuites());
    }

    /// Checks every network's declared chain id against the endpoint bound to
    /// its `[rpc_endpoints]` alias, by `LibRainDeploy.checkNetworkChainId`.
    /// @param networks The roster to check.
    function checkNetworkChainIds(SupportedNetwork[] memory networks) internal {
        // An empty roster is a repo that deploys nowhere, not a repo with
        // nothing to check, and it would pass here having forked nothing.
        if (networks.length == 0) {
            revert LibRainDeploy.NoNetworks();
        }

        uint256[] memory forkIds = LibRainDeploy.createForks(vm, LibRainDeploy.networkNames(networks));
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            LibRainDeploy.checkNetworkChainId(networks[i]);
        }
    }

    /// Every declared network's chain id MUST be the one the endpoint bound to
    /// its alias reports.
    ///
    /// The one thing about the config that generating it cannot settle. The
    /// sections are written from the same declaration this reads, so an alias
    /// missing from one of them is a tree `Git is clean` fails rather than an
    /// assertion anything makes — but which chain an endpoint actually serves
    /// is a claim about the world, and `chain` is what `--verify` submits to. A
    /// wrong id there is config that resolves, passes every check that reads
    /// the text, and verifies a deployment against the wrong explorer.
    ///
    /// Here rather than beside the catalogue because the subject is the
    /// endpoint: this is the contract that already forks every declared
    /// network, and the snapshot half is the one a credential-free job binds.
    function testSupportedNetworkChainIdsAreBound() external {
        checkNetworkChainIds(LibRainDeploy.declaredNetworkConfigs(supportedNetworks()));
    }
}
