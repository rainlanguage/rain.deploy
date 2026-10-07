// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {CloneDeploy, LibRainDeployClone} from "../lib/LibRainDeployClone.sol";
import {DeployCandidate, DeploySuite, RainDeploySuitesBase, UnknownDeploymentSuite} from "./RainDeploySuitesBase.sol";

/// Thrown when a declaration names no clone at all. The clone list is the only
/// thing this declaration is, so an empty one is a repo that inherited the clone
/// machinery and declared nothing for it to deploy — and
/// `NoDeployCandidates` would be the refusal it actually got, naming the derived
/// list rather than the one a consumer wrote.
error NoCloneDeploys();

/// @title RainDeployCloneSuitesBase
/// @notice The declaration for a repo whose deployments are EIP-1167 factory
/// clones: the clone list, and the candidates derived FROM it.
///
/// A clone is wholly described by five values — factory, implementation, init
/// data, salt and suite key — so a repo declares those and nothing else.
/// `candidateSuites()` is not a hook here; it is `cloneCandidate` mapped over
/// `cloneDeploys()`, which is the point. The hazard this package exists to close
/// is a repo that broadcasts one thing while its tests verify another, and that
/// can only happen where there are two lists to disagree. Here the broadcast
/// reads `cloneDeploys()` and the verification reads candidates derived from the
/// same entries, so there is nothing to keep in step.
///
/// It is NOT `virtual`, for that reason. A repo that deploys compiled contracts
/// as well as clones declares them on its own `RainDeploySuitesBase` and
/// dispatches them through `RainDeployBroadcast`; it does not reach back in here
/// and append, because a `candidateSuites()` free to answer something other than
/// the clone list is the second list again.
///
/// Inherited by both sides, like every declaration in this package: the clone
/// broadcast inherits it through `RainDeployCloneBroadcast`, and a repo's
/// `RainDeployVerifyChain` contract inherits it directly — so the chain matrix
/// checks the same clone the broadcast would deploy.
abstract contract RainDeployCloneSuitesBase is RainDeploySuitesBase {
    /// Every clone this repo deploys.
    ///
    /// The ONE list. A repo adds a clone by adding an entry, and its suite key,
    /// its candidate, its declared address and its broadcast all follow from
    /// that entry.
    ///
    /// MUST NOT be empty, which `checkedCloneDeploys` enforces.
    /// @return The clones.
    function cloneDeploys() internal pure virtual returns (CloneDeploy[] memory);

    /// The declared clones, refusing an empty list.
    ///
    /// The one place `NoCloneDeploys` is raised and the only way anything reads
    /// the clone list, for the reason `checkedCandidateSuites` is the only way
    /// anything reads the candidates: every loop over an empty list passes, so a
    /// guard per reader is a rule with as many spellings as readers and the one
    /// spelled wrong is the reader that silently stops asserting.
    /// @return The clones.
    function checkedCloneDeploys() internal pure returns (CloneDeploy[] memory clones) {
        clones = cloneDeploys();
        if (clones.length == 0) {
            revert NoCloneDeploys();
        }
    }

    /// @inheritdoc RainDeploySuitesBase
    /// @dev Nothing released. A released suite records bytes already frozen into
    /// this repo's own record for a deploy that already happened, and a clone has
    /// no such bytes to freeze: it is a pure function of `cloneDeploys()`, which
    /// is current source, and the implementation it delegates into is published
    /// by whoever deployed THAT.
    ///
    /// Still `virtual`, because a repo that has cut releases of its own compiled
    /// contracts and also deploys clones declares them, and an empty default is
    /// a convenience rather than a rule.
    function releasedSuites() internal pure virtual override returns (DeploySuite[] memory) {
        return new DeploySuite[](0);
    }

    /// @inheritdoc RainDeploySuitesBase
    /// @dev `LibRainDeployClone.cloneCandidate` over the clone list, in order.
    /// Not a hook — see this contract's own notes for why there is exactly one
    /// list here.
    function candidateSuites() internal pure override returns (DeployCandidate[] memory candidates) {
        CloneDeploy[] memory clones = checkedCloneDeploys();
        candidates = new DeployCandidate[](clones.length);
        for (uint256 i = 0; i < clones.length; i++) {
            candidates[i] = LibRainDeployClone.cloneCandidate(clones[i]);
        }
    }

    /// The clone a suite key selects.
    ///
    /// Keyed off the same string the candidate carries, because the candidate was
    /// derived from this very entry — so a key that selects a suite selects the
    /// clone that suite IS. Iterating rather than branching, for the reason
    /// `suiteByName` iterates: a repo adds a clone by adding an entry.
    ///
    /// Refuses with `UnknownDeploymentSuite` and the full declared key list, the
    /// same refusal `suiteByName` makes, because a key that is a released suite
    /// rather than a clone is a key this mechanism cannot broadcast and the
    /// caller needs to be told which keys it can.
    /// @param requested The key to select, from `DEPLOYMENT_SUITE`.
    /// @return The selected clone.
    function cloneDeployByName(string memory requested) internal pure returns (CloneDeploy memory) {
        CloneDeploy[] memory clones = checkedCloneDeploys();
        bytes32 requestedHash = keccak256(bytes(requested));
        for (uint256 i = 0; i < clones.length; i++) {
            if (keccak256(bytes(clones[i].suite)) == requestedHash) {
                return clones[i];
            }
        }
        revert UnknownDeploymentSuite(requested, suiteNames());
    }
}
