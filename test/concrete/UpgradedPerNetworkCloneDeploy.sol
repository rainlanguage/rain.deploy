// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {CloneNetwork} from "../../src/lib/LibRainDeployClone.sol";
import {PerNetworkCloneDeployBase} from "../abstract/PerNetworkCloneDeployBase.sol";
import {PerNetworkCloneDeploys} from "../abstract/PerNetworkCloneDeploys.sol";
import {UpgradedPerNetworkCloneDeploys} from "../abstract/UpgradedPerNetworkCloneDeploys.sol";

/// @title UpgradedPerNetworkCloneDeploy
/// @notice `UpgradedPerNetworkCloneDeploys` under `PerNetworkCloneDeployBase`.
contract UpgradedPerNetworkCloneDeploy is UpgradedPerNetworkCloneDeploys, PerNetworkCloneDeployBase {
    /// @inheritdoc PerNetworkCloneDeploys
    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return PerNetworkCloneDeploys.supportedNetworks();
    }

    /// @inheritdoc PerNetworkCloneDeployBase
    function extendedNetworks(string memory suite)
        internal
        view
        override(PerNetworkCloneDeployBase, RainDeploySuitesBase)
        returns (CloneNetwork[] memory)
    {
        return PerNetworkCloneDeployBase.extendedNetworks(suite);
    }

    /// @inheritdoc PerNetworkCloneDeployBase
    function extendedNetworksRoot()
        internal
        view
        override(PerNetworkCloneDeployBase, RainDeploySuitesBase)
        returns (string memory)
    {
        return PerNetworkCloneDeployBase.extendedNetworksRoot();
    }
}
