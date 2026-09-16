// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DerivedDeploy, RainDeployVerifyBase} from "./RainDeployVerifyBase.sol";
import {LibRainDeploy} from "../lib/LibRainDeploy.sol";

/// Thrown when a version's derived address has no code on a network. Either it
/// never deployed there, or it is not there any more.
/// @param network The network name, as configured in `[rpc_endpoints]`.
/// @param suite The suite that is missing.
/// @param deployedAddress The address that should hold it.
error NotDeployedOnNetwork(string network, string suite, address deployedAddress);

/// Thrown when a version's derived address holds code that is not the code its
/// creation code produces.
///
/// This is also what a chain-dependent runtime code looks like: a constructor
/// that reads `block.chainid` or similar deploys different code per network,
/// so one network disagrees while others pass. That is a defect in the
/// contract, not a shortcoming of a single recorded hash — hence a hard failure
/// naming the chain and both hashes, rather than a per-chain hash to record.
/// @param network The network name, as configured in `[rpc_endpoints]`.
/// @param suite The suite that failed.
/// @param deployedAddress The address checked.
/// @param expectedCodeHash The code hash the version's creation code produces.
/// @param actualCodeHash The code hash actually found on this network.
error CodeHashMismatchOnNetwork(
    string network, string suite, address deployedAddress, bytes32 expectedCodeHash, bytes32 actualCodeHash
);

/// Thrown when the chain id a network's `[etherscan]` entry declares is not the
/// chain id the endpoint bound to that network's `[rpc_endpoints]` alias
/// reports. Either the declaration is wrong — and `chain` is what `--verify`
/// submits, so the deployment is verified against another chain's explorer — or
/// the alias is bound to a different network than the one it names, and
/// everything ever checked through it was checked somewhere else.
/// @param network The network name, as configured in `[rpc_endpoints]`.
/// @param declared The chain id the `[etherscan]` entry states.
/// @param reported The chain id the endpoint answers with.
error NetworkChainIdMismatch(string network, uint256 declared, uint256 reported);

/// Thrown when no supported network's `[etherscan]` entry declares a `chain` at
/// all. That is not nothing to check, it is a config in which every entry
/// resolves through a `url` alone, and a check with no subject passes having
/// forked nothing — indistinguishable from every declared id being right.
error NoDeclaredChainIds();

/// The chain id one network's `[etherscan]` entry states.
struct DeclaredChainId {
    /// The network name, as configured in `[rpc_endpoints]` and `[etherscan]`.
    string network;
    /// The chain id the entry states.
    uint256 chainId;
}

/// @title RainDeployVerifyChain
/// @notice The only deploy-pin assertions anchored to something outside the
/// repo: across every network in `LibRainDeploy.supportedNetworks()`, every
/// RELEASED suite's derived address carries code with its derived code hash,
/// and every chain id `[etherscan]` declares is the one that network's alias
/// forks.
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
/// That is the trade, not an oversight. The error names the network, the suite
/// and the address, so a run that names one cell is actionable on its own;
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
    /// Checks one derived suite against whichever network is currently
    /// selected.
    /// @param network The network name, for the error only.
    /// @param derived The derivation to check for.
    function checkDeployedOnNetwork(string memory network, DerivedDeploy memory derived) internal view {
        if (derived.deployedAddress.code.length == 0) {
            revert NotDeployedOnNetwork(network, derived.suite, derived.deployedAddress);
        }
        bytes32 actualCodeHash = derived.deployedAddress.codehash;
        if (actualCodeHash != derived.bytecodeHash) {
            revert CodeHashMismatchOnNetwork(
                network, derived.suite, derived.deployedAddress, derived.bytecodeHash, actualCodeHash
            );
        }
    }

    /// Checks every derived suite against every supported network, forking
    /// each network once and checking every suite on it.
    ///
    /// The derivations are taken as an argument, already computed, because they
    /// have to be computed before anything forks: on a fork the derived address
    /// is the very address the deployment under test occupies, so deriving
    /// there would either collide with it or read it back as its own
    /// expectation.
    /// @param derived The derivation of every suite to check.
    function checkDeployedOnSupportedNetworks(DerivedDeploy[] memory derived) internal {
        // Nothing to check is not a reason to touch every RPC endpoint. Forking
        // to check nothing turns an outage into the failure of an assertion
        // that has no subject, which is the one failure this contract is
        // supposed to be legible against.
        if (derived.length == 0) {
            return;
        }

        string[] memory networks = LibRainDeploy.supportedNetworks();
        uint256[] memory forkIds = LibRainDeploy.createForks(vm, networks);
        for (uint256 i = 0; i < networks.length; i++) {
            vm.selectFork(forkIds[i]);
            for (uint256 j = 0; j < derived.length; j++) {
                checkDeployedOnNetwork(networks[i], derived[j]);
            }
        }
    }

    /// Every RELEASED suite MUST be live, with the code its creation code
    /// produces, on every supported network.
    function testSuitesLiveOnEverySupportedNetwork() external {
        checkDeployedOnSupportedNetworks(deriveDeployments(releasedSuites()));
    }

    /// The chain id each supported network's `[etherscan]` entry states, for
    /// the networks that state one.
    ///
    /// An entry with no `chain` is not a gap here. The config group requires
    /// only that an entry carry at least one of `chain` or `url`, so one that
    /// resolves through a `url` alone makes no claim about which chain its
    /// alias is, and there is nothing about it to compare. What WOULD be a gap
    /// is every entry being that way, which is why `checkNetworkChainIds`
    /// refuses an empty declaration set rather than passing on it.
    ///
    /// Takes the config text rather than reading it, so a test can hand it one
    /// it built. Reading the binder's own file is
    /// `testSupportedNetworkChainIdsAreBound`.
    /// @param config The raw `foundry.toml` text.
    /// @param networks The supported networks whose entries to read.
    /// @return The declaration of every network that states a chain id, in
    /// `networks` order.
    function declaredChainIds(string memory config, string[] memory networks)
        internal
        view
        returns (DeclaredChainId[] memory)
    {
        uint256 declaredCount = 0;
        for (uint256 i = 0; i < networks.length; i++) {
            if (vm.keyExistsToml(config, string.concat(".etherscan.", networks[i], ".chain"))) {
                declaredCount++;
            }
        }

        DeclaredChainId[] memory declared = new DeclaredChainId[](declaredCount);
        uint256 next = 0;
        for (uint256 i = 0; i < networks.length; i++) {
            string memory key = string.concat(".etherscan.", networks[i], ".chain");
            if (vm.keyExistsToml(config, key)) {
                declared[next] = DeclaredChainId({network: networks[i], chainId: vm.parseTomlUint(config, key)});
                next++;
            }
        }
        return declared;
    }

    /// Checks one network's declared chain id against a reported one.
    /// @param network The network name, for the error only.
    /// @param declared The chain id the `[etherscan]` entry states.
    /// @param reported The chain id the bound endpoint answers with.
    function checkNetworkChainId(string memory network, uint256 declared, uint256 reported) internal pure {
        if (declared != reported) {
            revert NetworkChainIdMismatch(network, declared, reported);
        }
    }

    /// Checks every declaration against the endpoint bound to its network's
    /// `[rpc_endpoints]` alias.
    ///
    /// Every fork is created before any is selected, for the reason
    /// `LibRainDeploy.createForks` gives.
    /// @param declared The declarations to check.
    function checkNetworkChainIds(DeclaredChainId[] memory declared) internal {
        if (declared.length == 0) {
            revert NoDeclaredChainIds();
        }

        string[] memory names = new string[](declared.length);
        for (uint256 i = 0; i < declared.length; i++) {
            names[i] = declared[i].network;
        }

        uint256[] memory forkIds = LibRainDeploy.createForks(vm, names);
        for (uint256 i = 0; i < declared.length; i++) {
            vm.selectFork(forkIds[i]);
            checkNetworkChainId(declared[i].network, declared[i].chainId, block.chainid);
        }
    }

    /// Every chain id `[etherscan]` declares MUST be the one the endpoint bound
    /// to that network's `[rpc_endpoints]` alias reports.
    ///
    /// The config group asserts that those entries exist and can resolve, and
    /// can go no further: whether `chain = 42161` is the network `arbitrum`
    /// forks is a claim about the world that only a fork settles. A wrong id
    /// resolves, satisfies every check that reads the text, and is what
    /// `--verify` submits — so the deployment is verified against another
    /// chain's explorer, after the gas is spent. The mirror of it is an
    /// `[rpc_endpoints]` alias bound to a different network than it names,
    /// which the same comparison catches and which is worse: every
    /// chain-anchored assertion ever made through that alias was made somewhere
    /// nobody named.
    ///
    /// Here rather than in the config group because the subject is the
    /// endpoint. This is the contract that forks, and keeping the comparison
    /// out of the snapshot half is what leaves that half bindable by a job with
    /// no RPC endpoint at all.
    ///
    /// `vm.readFile` resolves against the project root of whatever runs it, so
    /// the file read is the binder's own — which is why a binding repo needs
    /// `{ access = "read", path = "./foundry.toml" }` in `fs_permissions` for
    /// THIS half as well as the snapshot half.
    function testSupportedNetworkChainIdsAreBound() external {
        checkNetworkChainIds(declaredChainIds(vm.readFile("foundry.toml"), LibRainDeploy.supportedNetworks()));
    }
}
