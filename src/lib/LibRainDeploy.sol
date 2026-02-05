// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

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

    /// Thrown when a dependency is missing on a network before deployment.
    error MissingDependency(string network, address dependency);

    /// Thrown when the deployed address does not match the expected address.
    error UnexpectedDeployedAddress(address expected, address actual);

    /// Thrown when the deployed code hash does not match the expected code hash.
    error UnexpectedDeployedCodeHash(bytes32 expected, bytes32 actual);

    /// Zoltu proxy is the same on every network.
    address constant ZOLTU_FACTORY = 0x7A0D94F55792C434d74a40883C6ed8545E406D12;

    /// Config name for Arbitrum One network.
    string constant ARBITRUM_ONE = "arbitrum";

    /// Config name for Base network.
    string constant BASE = "base";

    /// Config name for Flare network.
    string constant FLARE = "flare";

    /// Config name for Polygon network.
    string constant POLYGON = "polygon";

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
        networks[3] = POLYGON;
        return networks;
    }

    /// Deploys the given creation code via the Zoltu factory to all supported
    /// networks, broadcasting the deployment transaction using the given private
    /// key.
    /// @param vm The Vm instance to use for forking and broadcasting.
    /// @param deployerPrivateKey The private key to use for broadcasting.
    /// @param creationCode The creation code to deploy.
    /// @return deployedAddress The address of the deployed contract on the last network.
    function deployAndBroadcastToSupportedNetworks(
        Vm vm,
        string[] memory networks,
        uint256 deployerPrivateKey,
        bytes memory creationCode,
        string memory contractPath,
        address expectedAddress,
        bytes32 expectedCodeHash,
        address[] memory dependencies
    ) internal returns (address deployedAddress) {
        address deployer = vm.rememberKey(deployerPrivateKey);

        console2.log("Deploying from address:", deployer);

        /// Check dependencies exist on each network before deploying.
        for (uint256 i = 0; i < networks.length; i++) {
            vm.createSelectFork(networks[i]);
            console2.log("Checking dependencies on network:", networks[i]);

            console2.log(" - Zoltu Factory:", ZOLTU_FACTORY);
            // Zoltu factory must exist always.
            if (ZOLTU_FACTORY.code.length == 0) {
                revert MissingDependency(networks[i], ZOLTU_FACTORY);
            }

            for (uint256 j = 0; j < dependencies.length; j++) {
                console2.log(" - Dependency:", dependencies[j]);
                if (dependencies[j].code.length == 0) {
                    revert MissingDependency(networks[i], dependencies[j]);
                }
            }
        }

        /// Deploy to each network.
        for (uint256 i = 0; i < networks.length; i++) {
            console2.log("Deploying to network:", networks[i]);
            vm.createSelectFork(networks[i]);
            vm.startBroadcast(deployer);
            if (expectedAddress.code.length == 0) {
                console2.log(" - Deploying via Zoltu");
                deployedAddress = deployZoltu(creationCode);
            } else {
                console2.log(" - Code already exists at expected address, skipping deployment");
                deployedAddress = expectedAddress;
            }
            console2.log(" - Final Address:", deployedAddress);
            if (deployedAddress != expectedAddress) {
                revert UnexpectedDeployedAddress(expectedAddress, deployedAddress);
            }
            console2.log(" - Verifying code hash");
            if (expectedCodeHash != deployedAddress.codehash) {
                revert UnexpectedDeployedCodeHash(expectedCodeHash, deployedAddress.codehash);
            }
            vm.stopBroadcast();

            console2.log("manual verficiation command:");
            console2.log(
                string.concat(
                    "forge verify-contract --chain ", networks[i], " ", vm.toString(deployedAddress), " ", contractPath
                )
            );
        }
    }
}
