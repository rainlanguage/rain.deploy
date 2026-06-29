// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.16.1/src/Vm.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";

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

    /// Thrown when a dependency's code hash does not match the expected value.
    error DependencyChanged(string network, address dependency, bytes32 expectedCodeHash, bytes32 actualCodeHash);

    /// Thrown when no networks are provided for deployment.
    error NoNetworks();

    /// Thrown when attempting to find the deploy block of a contract that has
    /// no code at the current block.
    error NotDeployed(address target);

    /// Thrown when the target already has code at the start block, meaning
    /// the deploy may have happened before the search range.
    error DeployedBeforeStartBlock(address target, uint256 startBlock);

    /// Zoltu factory is the same on every network.
    address constant ZOLTU_FACTORY = 0x7A0D94F55792C434d74a40883C6ed8545E406D12;

    /// Expected codehash of the Zoltu factory contract.
    bytes32 constant ZOLTU_FACTORY_CODEHASH = 0x5acaad953250bec20933f7c72a25bb03bfa54767ebd3a750396276512c46a79c;

    /// Runtime bytecode of the Zoltu factory, for use with `vm.etch`.
    bytes constant ZOLTU_FACTORY_BYTECODE = hex"60003681823780368234f58015156014578182fd5b80825250506014600cf3";

    /// Config name for Arbitrum One network.
    string constant ARBITRUM_ONE = "arbitrum";

    /// Config name for Base network.
    string constant BASE = "base";

    /// Config name for Base Sepolia testnet.
    string constant BASE_SEPOLIA = "base_sepolia";

    /// Config name for Flare network.
    string constant FLARE = "flare";

    /// Config name for Polygon network.
    string constant POLYGON = "polygon";

    /// Checks whether a block is the first block where a contract with the
    /// expected code hash exists. True when the target has the expected code
    /// hash at `blockNumber` and does NOT have it at `blockNumber - 1`. At
    /// block 0, only the first condition is checked. The fork is restored to
    /// its original block number after checking.
    /// @param vm The Vm instance for fork manipulation.
    /// @param target The contract address to check.
    /// @param expectedCodeHash The code hash to look for.
    /// @param blockNumber The block number to check.
    /// @return isStart True if the contract first appears at this block.
    function isStartBlock(Vm vm, address target, bytes32 expectedCodeHash, uint256 blockNumber)
        internal
        returns (bool isStart)
    {
        uint256 originalBlock = block.number;
        vm.rollFork(blockNumber);
        isStart = target.codehash == expectedCodeHash;
        if (isStart && blockNumber > 0) {
            vm.rollFork(blockNumber - 1);
            isStart = target.codehash != expectedCodeHash;
        }
        vm.rollFork(originalBlock);
    }

    /// Finds the block number at which a contract was first deployed by binary
    /// searching the fork history. Requires an active fork with archive access
    /// back to `startBlock`. The fork is restored to its original block
    /// number before returning. The target's code hash is verified against the
    /// expected value before searching. The result is validated via
    /// `isStartBlock`.
    /// @param vm The Vm instance for fork manipulation.
    /// @param target The contract address to search for.
    /// @param expectedCodeHash The expected code hash of the target contract.
    /// @param startBlock The earliest block to search from. The target MUST
    /// NOT have the expected code hash at this block.
    /// @return deployBlock The first block number where `target` has the
    /// expected code hash.
    function findDeployBlock(Vm vm, address target, bytes32 expectedCodeHash, uint256 startBlock)
        internal
        returns (uint256 deployBlock)
    {
        if (target.code.length == 0) {
            revert NotDeployed(target);
        }
        if (target.codehash != expectedCodeHash) {
            revert UnexpectedDeployedCodeHash(expectedCodeHash, target.codehash);
        }

        uint256 originalBlock = block.number;

        // Verify the target does not already have the expected code at
        // startBlock. If it does, the deploy happened before our search
        // range and the result would be meaningless.
        vm.rollFork(startBlock);
        if (target.codehash == expectedCodeHash) {
            vm.rollFork(originalBlock);
            revert DeployedBeforeStartBlock(target, startBlock);
        }

        uint256 low = startBlock;
        uint256 high = originalBlock;

        while (low < high) {
            uint256 mid = (low + high) / 2;
            vm.rollFork(mid);
            if (target.codehash == expectedCodeHash) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        deployBlock = low;
        vm.rollFork(originalBlock);
    }

    /// Etches the Zoltu factory bytecode into the factory address. Useful for
    /// networks where the factory is not yet deployed.
    /// @param vm The Vm instance to use for etching.
    function etchZoltuFactory(Vm vm) internal {
        vm.etch(ZOLTU_FACTORY, ZOLTU_FACTORY_BYTECODE);
    }

    /// Deploys the given creation code via the Zoltu factory.
    /// Handles the return data and errors appropriately.
    /// @param creationCode The creation code to deploy.
    /// @return deployedAddress The address of the deployed contract.
    function deployZoltu(bytes memory creationCode) internal returns (address deployedAddress) {
        address zoltuFactory = ZOLTU_FACTORY;
        bool success;
        assembly ("memory-safe") {
            // Zero scratch space so mload(0) reads a clean 32-byte word.
            mstore(0, 0)
            // The Zoltu factory returns a raw 20-byte address (not ABI-encoded).
            // Writing 20 bytes at offset 12 (= 32 - 20) right-aligns the address
            // in scratch space so that mload(0) produces a correctly padded value.
            success := call(gas(), zoltuFactory, 0, add(creationCode, 0x20), mload(creationCode), 12, 20)
            deployedAddress := mload(0)
        }
        if (!success || deployedAddress == address(0) || deployedAddress.code.length == 0) {
            console2.log("Zoltu deployment failed. Success:", success, "Deployed Address:", deployedAddress);
            console2.log("Code length at Deployed Address:", deployedAddress.code.length);
            console2.log("Codehash at Deployed Address:");
            console2.logBytes32(deployedAddress.codehash);
            revert DeployFailed(success, deployedAddress);
        }
    }

    /// Returns the list of networks currently supported by Rain deployments.
    /// @return networks The list of supported network names.
    function supportedNetworks() internal pure returns (string[] memory) {
        string[] memory networks = new string[](5);
        networks[0] = ARBITRUM_ONE;
        networks[1] = BASE;
        networks[2] = BASE_SEPOLIA;
        networks[3] = FLARE;
        networks[4] = POLYGON;
        return networks;
    }

    /// Checks that the Zoltu factory has the expected codehash and all
    /// dependencies have code on each network, returning the fork validated for
    /// each network so the deploy phase can reuse it.
    /// @param vm The Vm instance to use for forking.
    /// @param networks The list of network names to check.
    /// @param dependencies The addresses that must have code on each network.
    /// @return forkIds The fork id created and selected for each network, in the
    /// same order as `networks`, so the deploy phase can reuse the validated
    /// fork instead of creating a fresh one.
    function checkDependencies(Vm vm, string[] memory networks, address[] memory dependencies)
        internal
        returns (uint256[] memory forkIds)
    {
        if (networks.length == 0) {
            revert NoNetworks();
        }
        forkIds = new uint256[](networks.length);
        for (uint256 i = 0; i < networks.length; i++) {
            forkIds[i] = vm.createSelectFork(networks[i]);
            console2.log("Block number:", block.number);
            console2.log("Checking dependencies on network:", networks[i]);

            console2.log(" - Zoltu Factory:", ZOLTU_FACTORY);
            // Zoltu factory must exist with the expected codehash.
            if (ZOLTU_FACTORY.code.length == 0) {
                revert MissingDependency(networks[i], ZOLTU_FACTORY);
            }
            if (ZOLTU_FACTORY.codehash != ZOLTU_FACTORY_CODEHASH) {
                revert DependencyChanged(networks[i], ZOLTU_FACTORY, ZOLTU_FACTORY_CODEHASH, ZOLTU_FACTORY.codehash);
            }

            for (uint256 j = 0; j < dependencies.length; j++) {
                console2.log(" - Dependency:", dependencies[j]);
                if (dependencies[j].code.length == 0) {
                    revert MissingDependency(networks[i], dependencies[j]);
                }
            }
        }
    }

    /// Deploys to each network via the Zoltu factory, reusing the fork that
    /// `checkDependencies` already validated. If code already exists at
    /// `expectedAddress`, deployment is skipped for that network.
    /// @param vm The Vm instance to use for forking and broadcasting.
    /// @param networks The list of network names to deploy to.
    /// @param forkIds The fork ids returned by `checkDependencies`, reused per
    /// network so the deploy runs on the same validated snapshot.
    /// @param deployer The deployer address.
    /// @param creationCode The creation code to deploy.
    /// @param contractPath The contract path for verification commands.
    /// @param expectedAddress The expected deterministic address.
    /// @param expectedCodeHash The expected code hash of the deployed contract.
    /// @return deployedAddress The deployed contract address.
    function deployToNetworks(
        Vm vm,
        string[] memory networks,
        uint256[] memory forkIds,
        address deployer,
        bytes memory creationCode,
        string memory contractPath,
        address expectedAddress,
        bytes32 expectedCodeHash
    ) internal returns (address deployedAddress) {
        if (networks.length == 0) {
            revert NoNetworks();
        }
        for (uint256 i = 0; i < networks.length; i++) {
            console2.log("Deploying to network:", networks[i]);
            // Reuse the fork that checkDependencies already validated for this
            // network, rather than creating a fresh fork at a newer head. The
            // dependencies were verified on this exact snapshot; a fresh fork
            // re-reads them on a different one, where a transient RPC
            // inconsistency can report an already-deployed dependency as missing
            // and abort an otherwise-valid deploy.
            vm.selectFork(forkIds[i]);
            console2.log("Block number:", block.number);

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

            console2.log("manual verification command:");
            console2.log(
                string.concat(
                    "forge verify-contract --chain ", networks[i], " ", vm.toString(deployedAddress), " ", contractPath
                )
            );
        }
    }

    /// Deploys the given creation code via the Zoltu factory to the given
    /// networks, broadcasting the deployment transaction using the given private
    /// key.
    /// @param vm The Vm instance to use for forking and broadcasting.
    /// @param networks The list of network names to deploy to.
    /// @param deployerPrivateKey The private key to use for broadcasting.
    /// @param creationCode The creation code to deploy.
    /// @param contractPath The contract path for verification commands.
    /// @param expectedAddress The expected deterministic address.
    /// @param expectedCodeHash The expected code hash of the deployed contract.
    /// @param dependencies The dependency addresses to check.
    /// @return deployedAddress The address of the deployed contract.
    function deployAndBroadcast(
        Vm vm,
        string[] memory networks,
        uint256 deployerPrivateKey,
        bytes memory creationCode,
        string memory contractPath,
        address expectedAddress,
        bytes32 expectedCodeHash,
        address[] memory dependencies
    ) internal returns (address deployedAddress) {
        if (networks.length == 0) {
            revert NoNetworks();
        }
        address deployer = vm.rememberKey(deployerPrivateKey);

        console2.log("Deploying from address:", deployer);

        uint256[] memory forkIds = checkDependencies(vm, networks, dependencies);
        deployedAddress = deployToNetworks(
            vm, networks, forkIds, deployer, creationCode, contractPath, expectedAddress, expectedCodeHash
        );
    }
}
