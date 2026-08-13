// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";

import {DeploySuite, RainDeploySuitesBase} from "./RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../lib/LibRainDeploy.sol";

/// @title RainDeployBroadcast
/// @notice The broadcast, inherited rather than rewritten per repo. Selects one
/// suite by `DEPLOYMENT_SUITE` and deploys it through the Zoltu factory.
///
/// A deploy repo's whole script becomes the declaration plus this:
///
/// ```solidity
/// contract Deploy is MyDeploySuites, RainDeployBroadcast {}
/// ```
///
/// The declaration it inherits is the SAME one its verification contracts
/// inherit. That is the point of putting it here: a repo that wrote its suites
/// out twice could broadcast one contract while its tests verified another and
/// stay green, because nothing would connect the two lists. There is one list.
///
/// ## A registry, not a branch
///
/// One suite is a degenerate case. `st0x.deploy` broadcasts ten, and its script
/// is ten `else if` arms of identical shape differing only in their arguments,
/// with the valid keys restated in a revert string that nothing keeps in step
/// with the arms. Here the keys and the arms are the same array, so adding a
/// suite is adding an entry and the failure message follows from the registry
/// rather than from a string somebody remembered to update.
///
/// ## What is NOT derived, and why
///
/// The recorded address and code hash are passed to `deployAndBroadcast`, not
/// derived from the creation code here. They are derivable — that is exactly
/// what `RainDeployVerifyOffline` derives them for — but deriving them at
/// broadcast time would defeat the check that matters most at broadcast time.
/// `LibRainDeploy.deployToNetworks` compares the recorded address against the
/// address the creation code derives BEFORE it forks anything, precisely so a
/// stale pin fails instead of silently deploying somewhere the repo's constants
/// do not describe. Feeding it a derived value would make that comparison
/// derived-against-derived, and a guard that compares a value to itself is not
/// a guard.
///
/// The artifact path is declared too. `src/concrete/<Name>.sol:<Name>` holds
/// only for the flattest repos; `st0x.deploy` groups concretes under
/// `deploy/` and `authorize/`, so a convention would be wrong for most of its
/// suites.
abstract contract RainDeployBroadcast is RainDeploySuitesBase, Script {
    /// The networks to broadcast to. Every supported network by default, which
    /// is what a deterministic deployment usually wants: one address, every
    /// chain, in one dispatch.
    ///
    /// Overridable because that is not universal. A repo bootstrapping onto one
    /// chain at a time — `st0x.deploy` selects between Ethereum and HyperEVM
    /// per dispatch — returns a single-element list from its own env var
    /// instead. The reusable workflow already carries a `network:` input for
    /// exactly this.
    /// @return The network names to deploy to, as `[rpc_endpoints]` aliases.
    function deployNetworks() internal view virtual returns (string[] memory) {
        return LibRainDeploy.supportedNetworks();
    }

    /// Broadcasts the suite `DEPLOYMENT_SUITE` names.
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
        DeploySuite memory suite = suiteByName(vm.envOr("DEPLOYMENT_SUITE", string("")));

        uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_KEY");

        LibRainDeploy.deployAndBroadcast(
            vm,
            deployNetworks(),
            deployerPrivateKey,
            suite.creationCode,
            suite.artifactPath,
            suite.storedDeployedAddress,
            suite.storedBytecodeHash,
            suite.dependencies
        );
    }
}
