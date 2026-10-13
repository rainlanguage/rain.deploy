// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {PerNetworkCloneDeploys} from "../abstract/PerNetworkCloneDeploys.sol";
import {ExternalCloneDeploySuites} from "../abstract/ExternalCloneDeploySuites.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";

/// @title ConfigurablePerNetworkCloneDeploy
/// The per-network clone declaration with its `supportedNetworks()` set from
/// outside, so a test can reorder the networks or add one the clone's
/// `initData` has no answer for, and read what the candidate is built for.
contract ConfigurablePerNetworkCloneDeploy is PerNetworkCloneDeploys, ExternalCloneDeploySuites, ExternalDeploySuites {
    /// The supported networks, in order.
    string[] internal sNetworks;

    /// @param networks The supported networks, in order.
    constructor(string[] memory networks) {
        sNetworks = networks;
    }

    /// @inheritdoc RainDeploySuitesBase
    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return sNetworks;
    }
}
