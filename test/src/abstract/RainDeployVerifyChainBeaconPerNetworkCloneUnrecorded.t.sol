// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {PerNetworkCloneDeploys, onlyFirstRecordedNetwork} from "../../abstract/PerNetworkCloneDeploys.sol";
import {
    RainDeployVerifyChainBeaconPerNetworkCloneTestBase
} from "../../abstract/RainDeployVerifyChainBeaconPerNetworkCloneTestBase.sol";

/// @title RainDeployVerifyChainBeaconPerNetworkCloneUnrecordedTest
/// @notice A beacon on a network the per-network clone release never recorded must point at its init data's clone.
contract RainDeployVerifyChainBeaconPerNetworkCloneUnrecordedTest is
    RainDeployVerifyChainBeaconPerNetworkCloneTestBase
{
    function releasedSuites()
        internal
        pure
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (DeploySuite[] memory)
    {
        DeploySuite[] memory suites = PerNetworkCloneDeploys.releasedSuites();
        suites[0] = onlyFirstRecordedNetwork(suites[0]);
        return suites;
    }
}
