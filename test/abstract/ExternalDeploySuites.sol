// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeployDependency,
    DeploySuite,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ChainDeploy} from "../../src/lib/LibRainDeployExtendedNetworks.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";

/// @title ExternalDeploySuites
/// @notice Every reader of the declaration, exposed externally so a plain
/// `Test` contract can drive them and `vm.expectRevert` lands at the right call
/// depth.
///
/// Here rather than on each fixture because every fixture needs all of them,
/// and a declaration that is refused has to be refused on ALL of them — a
/// wrapper a fixture forgot to carry is a reader nothing checks that fixture
/// through.
abstract contract ExternalDeploySuites is RainDeploySuitesBase {
    /// @return Every declared suite.
    function externalAllSuites() external view returns (DeploySuite[] memory) {
        return allSuites();
    }

    /// @param requested The suite key to select.
    /// @return The selected suite.
    function externalSuiteByName(string memory requested) external view returns (DeploySuite memory) {
        return suiteByName(requested);
    }

    /// @param requested The suite key to select.
    /// @return The index of the suite `requested` selects in `allSuites()`, its length if none.
    function externalSuiteIndex(string memory requested) external view returns (uint256) {
        return suiteIndex(allSuites(), requested);
    }

    /// @param suites The suites to search.
    /// @param requested The suite key to select.
    /// @return The index of the suite `requested` selects in `suites`, its length if none.
    function externalSuiteIndexIn(DeploySuite[] memory suites, string memory requested)
        external
        pure
        returns (uint256)
    {
        return suiteIndex(suites, requested);
    }

    /// @return The declared keys, comma separated.
    function externalSuiteNames() external view returns (string memory) {
        return suiteNames();
    }

    /// @return The networks the declaration names.
    function externalSupportedNetworks() external view returns (string[] memory) {
        return supportedNetworks();
    }

    function externalCheckSuiteKey(uint256 index, string memory suite) external pure {
        checkSuiteKey(index, suite);
    }

    /// @return The declared candidates, refusing an empty list.
    function externalCheckedCandidateSuites() external view returns (DeployCandidate[] memory) {
        return checkedCandidateSuites();
    }

    /// @return The record root the extended networks records are read from.
    function externalExtendedNetworksRoot() external view returns (string memory) {
        return extendedNetworksRoot();
    }

    /// Runs the source anchor over the fixture's own declaration.
    function externalCheckCandidatesAnchoredToSource() external view {
        checkCandidatesAnchoredToSource();
    }

    /// @param suite The suite.
    /// @param chainId The network's chain id.
    /// @return `deployedAddress(suite, chainId)`.
    function externalDeployedAddress(DeploySuite memory suite, uint256 chainId) external view returns (address) {
        return deployedAddress(suite, chainId);
    }

    /// @param suite The suite.
    /// @return `deployedAddresses(suite)`.
    function externalDeployedAddresses(DeploySuite memory suite) external view returns (address[] memory) {
        return deployedAddresses(suite);
    }

    /// @param suite The suite.
    /// @param chainId The network's chain id.
    /// @return `recordedAddress(suite, chainId)`.
    function externalRecordedAddress(DeploySuite memory suite, uint256 chainId) external view returns (address) {
        return recordedAddress(suite, chainId);
    }

    /// @param suite The suite.
    /// @return `recordedAddresses(suite)`.
    function externalRecordedAddresses(DeploySuite memory suite) external view returns (address[] memory) {
        return recordedAddresses(suite);
    }

    /// @param suite The suite.
    /// @return `addressChainIds(suite)`.
    function externalAddressChainIds(DeploySuite memory suite) external view returns (uint256[] memory) {
        return addressChainIds(suite);
    }

    /// @param suite The suite.
    /// @param chainId The network's chain id.
    /// @return `deployStepData(suite, chainId)`.
    function externalDeployStepData(DeploySuite memory suite, uint256 chainId) external view returns (bytes memory) {
        return deployStepData(suite, chainId);
    }

    /// Runs `deployStep(suite)` with the given arguments.
    /// @param stepVm The Vm the step runs on.
    /// @param suite The suite.
    /// @param network The network's name.
    /// @param deployer The deployer.
    /// @param data The step data.
    /// @return Where the step reports the suite landed.
    function externalRunDeployStep(
        Vm stepVm,
        DeploySuite memory suite,
        string memory network,
        address deployer,
        bytes memory data
    ) external returns (address) {
        return deployStep(suite)(stepVm, network, deployer, data);
    }

    /// @param localVm The Vm to etch with.
    /// @param suite The suite.
    /// @return `deployLocally(localVm, suite)`.
    function externalDeployLocally(Vm localVm, DeploySuite memory suite) external returns (address[] memory) {
        return deployLocally(localVm, suite);
    }

    /// @param localVm The Vm to etch with.
    /// @param suite The suite.
    function externalDeployLocallyOnChain(Vm localVm, DeploySuite memory suite) external {
        deployLocallyOnChain(localVm, suite);
    }

    /// @param suite The suite.
    /// @param candidate Its candidate.
    /// @param chainIds The chain ids in play.
    /// @return `withUnrecordedNetworks(suite, candidate, chainIds)`.
    function externalWithUnrecordedNetworks(
        DeploySuite memory suite,
        DeploySuite memory candidate,
        uint256[] memory chainIds
    ) external view returns (DeploySuite memory) {
        return withUnrecordedNetworks(suite, candidate, chainIds);
    }

    /// @param suite The release.
    /// @param extended The networks declared for it.
    /// @return `appendExtendedNetworks(suite, extended)`.
    function externalAppendExtendedNetworks(DeploySuite memory suite, ChainDeploy[] memory extended)
        external
        view
        returns (DeploySuite memory)
    {
        return appendExtendedNetworks(suite, extended);
    }

    /// @param frozen The release with its extended networks.
    /// @param network The network's name.
    /// @param chainId The network's chain id.
    /// @param where The address checked on it.
    function externalCheckNetworkFrozen(DeploySuite memory frozen, string memory network, uint256 chainId, address where)
        external
        view
    {
        checkNetworkFrozen(frozen, network, chainId, where);
    }

    /// @param frozen The release with its extended networks.
    /// @param onNetworks The release as it would be broadcast.
    /// @param networks The networks to broadcast to.
    function externalCheckNetworksFrozen(
        DeploySuite memory frozen,
        DeploySuite memory onNetworks,
        string[] memory networks
    ) external view {
        checkNetworksFrozen(frozen, onNetworks, networks);
    }

    /// @param suite The suite.
    /// @param chainId The network's chain id.
    /// @return `suiteBeacon(suite, chainId)`.
    function externalSuiteBeacon(DeploySuite memory suite, uint256 chainId) external view returns (address) {
        return suiteBeacon(suite, chainId);
    }

    /// @param logVm The Vm to format with.
    /// @param networks The networks.
    /// @param suite The suite.
    /// @param deployed Where it is on each network.
    function externalLogVerification(
        Vm logVm,
        string[] memory networks,
        DeploySuite memory suite,
        address[] memory deployed
    ) external {
        logVerification(logVm, networks, suite, deployed);
    }

    /// @param fileVm The Vm for file operations.
    /// @param path The release's record file.
    /// @param prefix The prefix its constants are aliased under.
    /// @return `releasedMechanismData(fileVm, path, prefix)`.
    function externalReleasedMechanismData(Vm fileVm, string memory path, string memory prefix)
        external
        view
        returns (string memory)
    {
        return releasedMechanismData(fileVm, path, prefix);
    }
}
