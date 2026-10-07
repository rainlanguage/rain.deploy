// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibRainDeployClone} from "../lib/LibRainDeployClone.sol";
import {RainDeployBroadcast} from "./RainDeployBroadcast.sol";
import {RainDeployCloneSuitesBase} from "./RainDeployCloneSuitesBase.sol";
import {DeploySuite} from "./RainDeploySuitesBase.sol";

/// @title RainDeployCloneBroadcast
/// @notice The broadcast for a repo whose deployments are EIP-1167 factory
/// clones. `RainDeployBroadcast` with one function overridden, because one
/// function is the whole of the difference.
///
/// A deploy repo's whole script is still the declaration plus this:
///
/// ```solidity
/// contract Deploy is MyCloneDeploys, RainDeployCloneBroadcast {}
/// ```
///
/// ## What is NOT here, and why
///
/// No `run()`, no network list, no fork loop, no skip, no assertions. Those are
/// `RainDeployBroadcast.run()` and `LibRainDeploy.deployStepToNetworks`, and they
/// are the same ones a Zoltu deploy runs: the anchor first, then the suite from
/// `DEPLOYMENT_SUITE`, then the key, then every network the declaration supports
/// — all of them, every dispatch, because deploying is idempotent and a
/// re-dispatch after a partial rollout fills in only the networks still missing
/// the clone.
///
/// A parallel script carrying its own copy of that loop was the obvious shape and
/// is the wrong one. The copies cannot be told apart by any test that passes, and
/// the one that falls behind is the one whose deploys stop being checked — while
/// `CREATE2` makes whatever it deployed permanent on every chain the dispatch
/// reached. So the loop is shared and the STEP is the parameter: Zoltu's
/// `CREATE2` over creation code, or this one's `cloneDeterministicOpenSalt`.
///
/// ## What IS here
///
/// Which `…AndBroadcast` to call, and nothing else. The selected suite was
/// DERIVED from the clone entry this hands over — `RainDeployCloneSuitesBase`
/// says why that is one list and not two — so the declared address and code hash
/// it carries are checked against the clone's own derivation before any network is
/// forked, and against what the factory actually returned afterwards.
abstract contract RainDeployCloneBroadcast is RainDeployCloneSuitesBase, RainDeployBroadcast {
    /// @inheritdoc RainDeployBroadcast
    /// @dev The clone mechanism: `cloneDeterministicOpenSalt` through the clone
    /// factory, in place of `CREATE2` over creation code through Zoltu.
    ///
    /// The suite's recorded address and code hash are passed through rather than
    /// re-derived here, exactly as the Zoltu path passes them: they are what
    /// `cloneToNetworks` checks the clone's own derivation against before it
    /// forks anything, and a value derived at this call site would make that a
    /// comparison of a value with itself.
    function broadcastSuite(DeploySuite memory suite, string[] memory networks, uint256 deployerPrivateKey)
        internal
        override
    {
        LibRainDeployClone.cloneAndBroadcast(
            vm,
            networks,
            deployerPrivateKey,
            cloneDeployByName(suite.suite),
            suite.artifactPath,
            suite.storedDeployedAddress,
            suite.storedBytecodeHash,
            suite.dependencies
        );
    }
}
