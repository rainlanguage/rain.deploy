// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {CloneDeploy} from "../lib/LibRainDeployClone.sol";
import {LibRainDeploy, SupportedNetwork} from "../lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../lib/LibRainDeployMechanism.sol";
import {DeployCandidate, RainDeploySuitesBase} from "./RainDeploySuitesBase.sol";

/// Thrown when a declaration names no clone at all. The clone list is the only
/// thing this declaration's candidates are, so an empty one is a repo that
/// inherited the clone machinery and declared nothing for it to deploy — and
/// `NoDeployCandidates` would be the refusal it actually got, naming the derived
/// list rather than the one a consumer wrote.
error NoCloneDeploys();

/// @title RainDeployCloneSuitesBase
/// @notice The declaration for a repo whose candidates are EIP-1167 factory
/// clones: the clone list, and the candidates derived FROM it.
///
/// A clone is wholly described by its `CloneDeploy` — suite key, factory,
/// implementation, init data, salt and dependencies — so a repo declares those.
/// `candidateSuites()` is not a hook here; it is
/// `LibRainDeployMechanism.cloneCandidate` mapped over `cloneDeploys()`, and
/// each candidate carries its clone mechanism and that mechanism's data. From
/// there it is an ordinary suite: `RainDeployBroadcast` broadcasts it,
/// `RainDeployVerifySnapshot` and `RainDeployVerifyChain` derive it, and
/// `LibRainDeploySnapshot.writeSnapshot` records it, all through the same
/// mechanism dispatch on the same entry.
///
/// It is NOT `virtual`, for that reason. A `candidateSuites()` free to answer
/// something other than the clone list is a second list.
///
/// `releasedSuites()` is the consumer's, as on any declaration: the generated
/// `Lib<Contract>Released` over the frozen record, whose entries carry the
/// mechanism and the `CloneTarget` each release was cut with. A clone repo that
/// has released nothing declares an empty list, and the record group holds that
/// declaration to the record like any other.
abstract contract RainDeployCloneSuitesBase is RainDeploySuitesBase {
    /// Every clone candidate this repo deploys.
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
    function checkedCloneDeploys() internal pure returns (CloneDeploy[] memory) {
        CloneDeploy[] memory clones = cloneDeploys();
        if (clones.length == 0) {
            revert NoCloneDeploys();
        }
        return clones;
    }

    /// The chain id of every network in `supportedNetworks()`, in that order,
    /// from the network catalogue. The networks a per-network clone's
    /// `initData` is read for, so its entries are exactly the networks the
    /// repo deploys to and verifies on, from the one list that says which.
    /// @return The chain ids.
    function supportedChainIds() internal view returns (uint256[] memory) {
        SupportedNetwork[] memory configs = LibRainDeploy.declaredNetworkConfigs(supportedNetworks());
        uint256[] memory chainIds = new uint256[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            chainIds[i] = configs[i].chainId;
        }
        return chainIds;
    }

    /// @inheritdoc RainDeploySuitesBase
    /// @dev `LibRainDeployMechanism.cloneCandidate` over the clone list, in
    /// order, with `supportedChainIds()`. Not a hook — see this contract's own
    /// notes for why there is exactly one list here.
    function candidateSuites() internal view override returns (DeployCandidate[] memory) {
        CloneDeploy[] memory clones = checkedCloneDeploys();
        uint256[] memory chainIds = supportedChainIds();
        DeployCandidate[] memory candidates = new DeployCandidate[](clones.length);
        for (uint256 i = 0; i < clones.length; i++) {
            candidates[i] = LibRainDeployMechanism.cloneCandidate(clones[i], chainIds);
        }
        return candidates;
    }
}
