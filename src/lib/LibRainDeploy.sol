// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std/Vm.sol";

/// @title LibRainDeploy
/// Library for deploying contracts via the Zoltu factory across all the networks
/// currently supported by Rain by default. The Rain contracts can be deployed
/// permissionlessly to other networks by end users, using the same patterns
/// here, but the Rain organization only (re)deploys contracts periodically to
/// networks that have specific adoption and use cases.
library LibRainDeploy {
    /// Thrown when deployment via Zoltu factory fails. This could be either an
    /// explicit revert that manifests as non success, or a silent failure that
    /// results in the deployed address being empty somehow.
    error DeployFailed(bool success, address deployedAddress);

    /// Zoltu proxy is the same on every network.
    address constant ZOLTU_FACTORY = 0x7A0D94F55792C434d74a40883C6ed8545E406D12;

    string constant ARBITRUM_ONE = "arbitrum-one";
    string constant BASE = "base";
    string constant FLARE = "flare";
    string constant MATIC = "matic";

    /// Deploys the given creation code via the Zoltu factory.
    /// Handles the return data and errors appropriately.
    /// @param creationCode The creation code to deploy.
    /// @return deployedAddress The address of the deployed contract.
    function deployZoltu(bytes memory creationCode) internal returns (address deployedAddress) {
        address zoltuFactory = ZOLTU_FACTORY;
        bool success;
        assembly ("memory-safe") {
            mstore(0, 0)
            success := call(gas(), zoltuFactory, 0, add(creationCode, 0x20), mload(creationCode), 12, 20)
            deployedAddress := mload(0)
        }
        if (!success || deployedAddress == address(0) || deployedAddress.code.length == 0) {
            revert DeployFailed(success, deployedAddress);
        }
    }

    /// Returns the list of networks currently supported by Rain deployments.
    /// @return networks The list of supported network names.
    function supportedNetworks() internal pure returns (string[] memory) {
        string[] memory networks = new string[](4);
        networks[0] = ARBITRUM_ONE;
        networks[1] = BASE;
        networks[2] = FLARE;
        networks[3] = MATIC;
        return networks;
    }

    function deployAndBroadcastToSupportedNetworks(Vm vm, uint256 deployerPrivateKey, bytes memory creationCode)
        internal
        returns (address deployedAddress)
    {
        string[] memory networks = supportedNetworks();
        for (uint256 i = 0; i < networks.length - 1; i++) {
            vm.createSelectFork(networks[i]);
            vm.startBroadcast(deployerPrivateKey);
            deployedAddress = deployZoltu(creationCode);
            vm.stopBroadcast();
        }
    }
}
