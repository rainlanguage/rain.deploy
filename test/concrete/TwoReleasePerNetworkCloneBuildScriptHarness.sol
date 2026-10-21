// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {CloneNetwork} from "../../src/lib/LibRainDeployClone.sol";
import {PerNetworkCloneDeploys} from "../abstract/PerNetworkCloneDeploys.sol";
import {PerNetworkCloneBuildScriptHarness} from "./PerNetworkCloneBuildScriptHarness.sol";

/// @dev The key the harness releases its second copy of the per-network clone under.
string constant SECOND_RELEASE_KEY = "per-network-clone@0_0_2";

/// @title TwoReleasePerNetworkCloneBuildScriptHarness
/// @notice `PerNetworkCloneBuildScriptHarness` releasing the per-network clone twice, under its own key and under
/// `SECOND_RELEASE_KEY`, each with its own extended networks.
contract TwoReleasePerNetworkCloneBuildScriptHarness is PerNetworkCloneBuildScriptHarness {
    /// The networks `extendedNetworks` declares for `SECOND_RELEASE_KEY`. Empty by default.
    CloneNetwork[] internal sSecondExtendedNetworks;

    /// @param root The record root to regenerate into.
    /// @param libDir The directory the released-suites lib is written to.
    constructor(string memory root, string memory libDir) PerNetworkCloneBuildScriptHarness(root, libDir) {}

    /// @inheritdoc PerNetworkCloneDeploys
    function releasedSuites()
        internal
        pure
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (DeploySuite[] memory)
    {
        DeploySuite memory first = PerNetworkCloneDeploys.releasedSuites()[0];
        DeploySuite memory second = PerNetworkCloneDeploys.releasedSuites()[0];
        second.suite = SECOND_RELEASE_KEY;
        DeploySuite[] memory suites = new DeploySuite[](2);
        suites[0] = first;
        suites[1] = second;
        return suites;
    }

    /// Sets what `extendedNetworks` declares for `SECOND_RELEASE_KEY`.
    /// @param networks The networks.
    function setSecondExtendedNetworks(CloneNetwork[] memory networks) external {
        delete sSecondExtendedNetworks;
        for (uint256 i = 0; i < networks.length; i++) {
            sSecondExtendedNetworks.push(networks[i]);
        }
    }

    /// @inheritdoc PerNetworkCloneBuildScriptHarness
    function extendedNetworks(string memory suite) internal view override returns (CloneNetwork[] memory) {
        if (keccak256(bytes(suite)) == keccak256(bytes(SECOND_RELEASE_KEY))) {
            return sSecondExtendedNetworks;
        }
        return PerNetworkCloneBuildScriptHarness.extendedNetworks(suite);
    }
}
