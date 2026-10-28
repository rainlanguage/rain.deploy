// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    DeployCandidate,
    DeployDeclaration,
    DeploySuite,
    RainDeploySuitesBase,
    SnapshotFile
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
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
    function externalReleased() external view returns (DeploySuite[] memory) {
        return declaration().released;
    }

    function externalCandidates() external view returns (DeployCandidate[] memory) {
        return declaration().candidates;
    }

    /// @return The id of each of the declaration's mechanisms, in order.
    function externalMechanismIds() external view returns (bytes32[] memory) {
        DeployDeclaration memory d = declaration();
        bytes32[] memory ids = new bytes32[](d.mechanisms.length);
        for (uint256 i = 0; i < ids.length; i++) {
            ids[i] = d.mechanisms[i].id;
        }
        return ids;
    }

    function externalAllSuites() external view returns (DeploySuite[] memory) {
        return allSuites(declaration());
    }

    function externalSuiteByName(string memory requested) external view returns (DeploySuite memory) {
        return suiteByName(declaration(), requested);
    }

    function externalSuiteIndex(string memory requested) external view returns (uint256) {
        return suiteIndex(allSuites(declaration()), requested);
    }

    function externalSuiteIndexIn(DeploySuite[] memory suites, string memory requested)
        external
        pure
        returns (uint256)
    {
        return suiteIndex(suites, requested);
    }

    function externalSuiteNames() external view returns (string memory) {
        return suiteNames(declaration());
    }

    function externalNetworks() external view returns (string[] memory) {
        return declaration().networks;
    }

    function externalCheckSuiteKey(uint256 index, string memory suite) external pure {
        checkSuiteKey(index, suite);
    }

    function externalCheckedCandidateSuites() external view returns (DeployCandidate[] memory) {
        return checkedCandidateSuites(declaration());
    }

    function externalCheckCandidatesAnchoredToSource() external view {
        checkCandidatesAnchoredToSource(declaration());
    }

    /// @return The id of the mechanism `mechanismOf` resolves for `suite`.
    function externalMechanismOf(DeploySuite memory suite) external view returns (bytes32) {
        return mechanismOf(declaration(), suite).id;
    }

    function externalDeployedAddress(DeploySuite memory suite, uint256 chainId) external view returns (address) {
        return deployedAddress(declaration(), suite, chainId);
    }

    function externalDeployedAddresses(DeploySuite memory suite) external view returns (address[] memory) {
        return deployedAddresses(declaration(), suite);
    }

    function externalRecordedAddress(DeploySuite memory suite, uint256 chainId) external view returns (address) {
        return recordedAddress(declaration(), suite, chainId);
    }

    function externalRecordedAddresses(DeploySuite memory suite) external view returns (address[] memory) {
        return recordedAddresses(declaration(), suite);
    }

    function externalDeployStepData(DeploySuite memory suite, uint256 chainId) external view returns (bytes memory) {
        return deployStepData(declaration(), suite, chainId);
    }

    function externalRunDeployStep(
        Vm stepVm,
        DeploySuite memory suite,
        string memory network,
        address deployer,
        bytes memory data
    ) external returns (address) {
        return deployStep(declaration(), suite)(stepVm, network, deployer, data);
    }

    function externalDeployLocally(Vm localVm, DeploySuite memory suite) external returns (address[] memory) {
        return deployLocally(declaration(), localVm, suite);
    }

    function externalDeployLocallyOnChain(Vm localVm, DeploySuite memory suite) external {
        deployLocallyOnChain(declaration(), localVm, suite);
    }

    /// @return `suite` as `addUnrecordedNetworks` leaves it.
    function externalAddUnrecordedNetworks(
        DeploySuite memory suite,
        DeploySuite memory candidate,
        uint256[] memory chainIds
    ) external view returns (DeploySuite memory) {
        addUnrecordedNetworks(declaration(), suite, candidate, chainIds);
        return suite;
    }

    /// @return `suite` as `addRecordedNetworks` leaves it.
    function externalAddRecordedNetworks(DeploySuite memory suite) external view returns (DeploySuite memory) {
        addRecordedNetworks(declaration(), suite);
        return suite;
    }

    /// @return `suite` as `addCandidateNetworks` leaves it.
    function externalAddCandidateNetworks(DeploySuite memory suite, uint256[] memory chainIds)
        external
        view
        returns (DeploySuite memory)
    {
        addCandidateNetworks(declaration(), suite, chainIds);
        return suite;
    }

    function externalCheckNetworkFrozen(
        DeploySuite memory frozen,
        string memory network,
        uint256 chainId,
        address where
    ) external view {
        checkNetworkFrozen(declaration(), frozen, network, chainId, where);
    }

    function externalCheckNetworksFrozen(
        DeploySuite memory frozen,
        DeploySuite memory onNetworks,
        string[] memory networks
    ) external view {
        checkNetworksFrozen(declaration(), frozen, onNetworks, networks);
    }

    function externalCheckOnChain(DeploySuite memory suite, string memory network, uint256 chainId, address deployed)
        external
    {
        checkOnChain(declaration(), suite, network, chainId, deployed);
    }

    function externalLogVerification(
        Vm logVm,
        string[] memory networks,
        DeploySuite memory suite,
        address[] memory deployed
    ) external {
        logVerification(declaration(), logVm, networks, suite, deployed);
    }

    function externalWriteSuiteSnapshot(
        Vm fileVm,
        string memory root,
        string memory dir,
        string memory contractName,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        DeploySuite memory suite
    ) external returns (string memory) {
        return writeSuiteSnapshot(
            declaration(), fileVm, SnapshotFile(root, dir, contractName, spdxLicenseIdentifier, copyrightText), suite
        );
    }

    /// @return The released-lib expression of the record at `path`, by the mechanism its record declares.
    function externalReleasedMechanismData(Vm fileVm, string memory path, string memory prefix)
        external
        view
        returns (string memory)
    {
        DeployDeclaration memory d = declaration();
        return LibRainDeployDeclaration.mechanismById(d, LibRainDeploySnapshot.recordedMechanismId(fileVm, path), path)
            .releasedMechanismData(d, fileVm, path, prefix);
    }
}
