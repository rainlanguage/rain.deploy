// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {RainDeployBroadcast} from "../../src/abstract/RainDeployBroadcast.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ChainDeploy} from "../../src/lib/LibRainDeployExtendedNetworks.sol";
import {ExternalDeploySuites} from "../abstract/ExternalDeploySuites.sol";
import {MockCreate2DeploySuites} from "../abstract/MockCreate2DeploySuites.sol";

contract MockCreate2Deploy is MockCreate2DeploySuites, ExternalDeploySuites, RainDeployBroadcast {
    function externalMockRelease() external pure returns (DeploySuite memory) {
        return mockRelease();
    }

    function externalMockCandidate() external pure returns (DeploySuite memory) {
        return mockCandidate();
    }

    function externalWithExtendedNetworks(DeploySuite memory suite) external view returns (DeploySuite memory) {
        return withExtendedNetworks(suite);
    }

    function externalOnSupportedNetworks(DeploySuite memory frozen, uint256[] memory chainIds)
        external
        view
        returns (DeploySuite memory)
    {
        return onSupportedNetworks(frozen, chainIds);
    }

    function externalDeployAndBroadcast(
        Vm forkVm,
        string[] memory networks,
        uint256 deployerPrivateKey,
        DeploySuite memory frozen,
        DeploySuite memory candidate
    ) external returns (address[] memory, uint256[] memory) {
        return deployAndBroadcast(forkVm, networks, deployerPrivateKey, frozen, candidate);
    }

    function externalCheckSeatsNoDeployKey(DeploySuite memory suite, string[] memory networks, address deployer)
        external
    {
        checkSeatsNoDeployKey(suite, networks, deployer);
    }

    function extendedNetworksRoot()
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (string memory)
    {
        return super.extendedNetworksRoot();
    }

    function extendedNetworks(string memory suite)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (ChainDeploy[] memory)
    {
        return super.extendedNetworks(suite);
    }

    function deployedAddress(DeploySuite memory suite, uint256 chainId)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (address)
    {
        return super.deployedAddress(suite, chainId);
    }

    function recordedAddress(DeploySuite memory suite, uint256 chainId)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (address)
    {
        return super.recordedAddress(suite, chainId);
    }

    function addressChainIds(DeploySuite memory suite)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (uint256[] memory)
    {
        return super.addressChainIds(suite);
    }

    function deployStepData(DeploySuite memory suite, uint256 chainId)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (bytes memory)
    {
        return super.deployStepData(suite, chainId);
    }

    function deployStep(DeploySuite memory suite)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (function(Vm, string memory, address, bytes memory) internal returns (address))
    {
        return super.deployStep(suite);
    }

    function deployLocally(Vm localVm, DeploySuite memory suite)
        internal
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (address[] memory)
    {
        return super.deployLocally(localVm, suite);
    }

    function deployLocallyOnChain(Vm localVm, DeploySuite memory suite)
        internal
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
    {
        super.deployLocallyOnChain(localVm, suite);
    }

    function withUnrecordedNetworks(DeploySuite memory suite, DeploySuite memory candidate, uint256[] memory chainIds)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (DeploySuite memory)
    {
        return super.withUnrecordedNetworks(suite, candidate, chainIds);
    }

    function appendExtendedNetworks(DeploySuite memory suite, ChainDeploy[] memory extended)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (DeploySuite memory)
    {
        return super.appendExtendedNetworks(suite, extended);
    }

    function checkNetworkFrozen(DeploySuite memory frozen, string memory network, uint256 chainId, address where)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
    {
        super.checkNetworkFrozen(frozen, network, chainId, where);
    }

    function suiteBeacon(DeploySuite memory suite, uint256 chainId)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (address)
    {
        return super.suiteBeacon(suite, chainId);
    }

    function logVerification(Vm logVm, string[] memory networks, DeploySuite memory suite, address[] memory deployed)
        internal
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
    {
        super.logVerification(logVm, networks, suite, deployed);
    }

    function writeSuiteSnapshot(
        Vm fileVm,
        string memory root,
        string memory dir,
        string memory contractName,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        DeploySuite memory suite
    ) internal override(RainDeploySuitesBase, MockCreate2DeploySuites) returns (string memory) {
        return super.writeSuiteSnapshot(fileVm, root, dir, contractName, spdxLicenseIdentifier, copyrightText, suite);
    }

    function releasedMechanismData(Vm fileVm, string memory path, string memory prefix)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (string memory)
    {
        return super.releasedMechanismData(fileVm, path, prefix);
    }
}
