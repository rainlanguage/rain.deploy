// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeploySuite, RainDeploySuitesBase} from "./RainDeploySuitesBase.sol";
import {ChainDeploy} from "../lib/LibRainDeployExtendedNetworks.sol";
import {LibRainDeployZoltuMechanism} from "../lib/LibRainDeployZoltuMechanism.sol";

/// @title RainDeployZoltuSuitesBase
/// @notice Every mechanism hook through Zoltu, by `LibRainDeployZoltuMechanism`. Every hook refuses non-empty
/// `mechanismData` with `UnexpectedMechanismData`.
abstract contract RainDeployZoltuSuitesBase is RainDeploySuitesBase {
    function deployedAddress(DeploySuite memory suite, uint256)
        internal
        view
        virtual
        override
        returns (address)
    {
        return LibRainDeployZoltuMechanism.deployedAddress(suite);
    }

    function recordedAddress(DeploySuite memory suite, uint256)
        internal
        view
        virtual
        override
        returns (address)
    {
        return LibRainDeployZoltuMechanism.recordedAddress(suite);
    }

    function addressChainIds(DeploySuite memory suite) internal view virtual override returns (uint256[] memory) {
        return LibRainDeployZoltuMechanism.addressChainIds(suite);
    }

    function deployStepData(DeploySuite memory suite, uint256)
        internal
        view
        virtual
        override
        returns (bytes memory)
    {
        return LibRainDeployZoltuMechanism.deployStepData(suite);
    }

    function deployStep(DeploySuite memory suite)
        internal
        view
        virtual
        override
        returns (function(Vm, string memory, address, bytes memory) internal returns (address))
    {
        return LibRainDeployZoltuMechanism.deployStep(suite);
    }

    function deployLocally(Vm vm, DeploySuite memory suite) internal virtual override returns (address[] memory) {
        return LibRainDeployZoltuMechanism.deployLocally(vm, suite);
    }

    function deployLocallyOnChain(Vm vm, DeploySuite memory suite) internal virtual override {
        LibRainDeployZoltuMechanism.deployLocallyOnChain(vm, suite);
    }

    function withUnrecordedNetworks(DeploySuite memory suite, DeploySuite memory, uint256[] memory)
        internal
        view
        virtual
        override
        returns (DeploySuite memory)
    {
        return LibRainDeployZoltuMechanism.withUnrecordedNetworks(suite);
    }

    function appendExtendedNetworks(DeploySuite memory suite, ChainDeploy[] memory extended)
        internal
        view
        virtual
        override
        returns (DeploySuite memory)
    {
        return LibRainDeployZoltuMechanism.appendExtendedNetworks(suite, extended);
    }

    function checkNetworkFrozen(DeploySuite memory frozen, string memory, uint256, address)
        internal
        view
        virtual
        override
    {
        LibRainDeployZoltuMechanism.checkNetworkFrozen(frozen);
    }

    function suiteBeacon(DeploySuite memory suite, uint256) internal view virtual override returns (address) {
        return LibRainDeployZoltuMechanism.suiteBeacon(suite);
    }

    function logVerification(Vm vm, string[] memory networks, DeploySuite memory suite, address[] memory deployed)
        internal
        virtual
        override
    {
        LibRainDeployZoltuMechanism.logVerification(vm, networks, suite, deployed);
    }

    function writeSuiteSnapshot(
        Vm vm,
        string memory root,
        string memory dir,
        string memory contractName,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        DeploySuite memory suite
    ) internal virtual override returns (string memory) {
        return LibRainDeployZoltuMechanism.writeSuiteSnapshot(
            vm, root, dir, contractName, spdxLicenseIdentifier, copyrightText, suite
        );
    }

    function releasedMechanismData(Vm vm, string memory path, string memory)
        internal
        view
        virtual
        override
        returns (string memory)
    {
        return LibRainDeployZoltuMechanism.releasedMechanismData(vm, path);
    }
}
