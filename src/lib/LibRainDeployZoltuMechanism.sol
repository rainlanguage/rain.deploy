// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {
    DeployMechanismHandler,
    DeploySuite,
    ExtendedNetworksUnexpected,
    FrozenSnapshotMechanismDataUnexpected,
    UnexpectedMechanismData,
    ZoltuDerivationMismatch
} from "../abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "./LibRainDeploy.sol";
import {ChainDeploy} from "./LibRainDeployExtendedNetworks.sol";
import {LibRainDeploySnapshot} from "./LibRainDeploySnapshot.sol";

/// @title LibRainDeployZoltuMechanism
/// @notice The Zoltu mechanism: one address on every network, from the creation code alone. Its id is `bytes32(0)`,
/// which empty `mechanismData` declares, and every step refuses non-empty data with `UnexpectedMechanismData`.
library LibRainDeployZoltuMechanism {
    /// @return The Zoltu handler.
    function handler() internal pure returns (DeployMechanismHandler memory) {
        return DeployMechanismHandler({
            id: bytes32(0),
            deployedAddress: deployedAddress,
            recordedAddress: recordedAddress,
            addressChainIds: addressChainIds,
            deployStepData: deployStepData,
            deployStep: deployStep,
            deployLocally: deployLocally,
            deployLocallyOnChain: deployLocallyOnChain,
            withUnrecordedNetworks: withUnrecordedNetworks,
            appendExtendedNetworks: appendExtendedNetworks,
            checkNetworkFrozen: checkNetworkFrozen,
            suiteBeacon: suiteBeacon,
            logVerification: logVerification,
            writeSuiteSnapshot: writeSuiteSnapshot,
            releasedMechanismData: releasedMechanismData
        });
    }


    function checkMechanismData(DeploySuite memory suite) internal pure {
        if (suite.mechanismData.length != 0) {
            revert UnexpectedMechanismData(suite.suite);
        }
    }

    /// @return The Zoltu address of its creation code, on every network.
    function deployedAddress(DeploySuite memory suite, uint256) internal pure returns (address) {
        checkMechanismData(suite);
        return LibRainDeploy.zoltuAddress(suite.creationCode);
    }

    /// @return Its recorded address, on every network.
    function recordedAddress(DeploySuite memory suite, uint256) internal pure returns (address) {
        checkMechanismData(suite);
        return suite.storedDeployedAddress;
    }

    /// @return No chain ids: one address on every network.
    function addressChainIds(DeploySuite memory suite) internal pure returns (uint256[] memory) {
        checkMechanismData(suite);
        return new uint256[](0);
    }

    /// @return Its creation code, on every network.
    function deployStepData(DeploySuite memory suite, uint256) internal pure returns (bytes memory) {
        checkMechanismData(suite);
        return suite.creationCode;
    }

    function deployStep(DeploySuite memory suite)
        internal
        pure
        returns (function(Vm, string memory, address, bytes memory) internal returns (address))
    {
        checkMechanismData(suite);
        return LibRainDeploy.zoltuDeployStep;
    }

    /// Deploys through the etched Zoltu factory with the declared dependencies etched, refusing
    /// `ZoltuDerivationMismatch` where the factory and `LibRainDeploy.zoltuAddress` disagree.
    /// @return Its one address.
    function deployLocally(Vm vm, DeploySuite memory suite) internal returns (address[] memory) {
        address[] memory deployed = new address[](1);
        deployed[0] = deployedAddress(suite, 0);
        LibRainDeploy.etchDependencies(vm, suite.dependencies);
        vm.etch(deployed[0], hex"");
        vm.resetNonce(deployed[0]);
        address zoltuAddress = LibRainDeploy.etchAndDeployZoltu(vm, suite.creationCode);
        if (zoltuAddress != deployed[0]) {
            revert ZoltuDerivationMismatch(suite.suite, deployed[0], zoltuAddress);
        }
        return deployed;
    }

    function deployLocallyOnChain(Vm vm, DeploySuite memory suite) internal {
        deployLocally(vm, suite);
    }

    /// @return `suite`: its one address covers every network.
    function withUnrecordedNetworks(DeploySuite memory suite, DeploySuite memory, uint256[] memory)
        internal
        pure
        returns (DeploySuite memory)
    {
        checkMechanismData(suite);
        return suite;
    }

    /// Refuses `ExtendedNetworksUnexpected` for any extended network.
    function appendExtendedNetworks(DeploySuite memory suite, ChainDeploy[] memory extended)
        internal
        pure
        returns (DeploySuite memory)
    {
        checkMechanismData(suite);
        if (extended.length != 0) {
            revert ExtendedNetworksUnexpected(suite.suite);
        }
        return suite;
    }

    function checkNetworkFrozen(DeploySuite memory frozen, string memory, uint256, address) internal pure {
        checkMechanismData(frozen);
    }

    function suiteBeacon(DeploySuite memory suite, uint256) internal pure returns (address) {
        checkMechanismData(suite);
        return address(0);
    }

    function logVerification(Vm vm, string[] memory networks, DeploySuite memory suite, address[] memory deployed)
        internal
        pure
    {
        checkMechanismData(suite);
        LibRainDeploy.logVerifyCommands(vm, networks, deployed[0], suite.artifactPath);
    }

    function writeSuiteSnapshot(
        Vm vm,
        string memory root,
        string memory dir,
        string memory contractName,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        DeploySuite memory suite
    ) internal returns (string memory) {
        checkMechanismData(suite);
        return LibRainDeploySnapshot.writeSnapshot(
            vm, root, dir, contractName, spdxLicenseIdentifier, copyrightText, suite.creationCode, suite.dependencies
        );
    }

    /// Refuses `FrozenSnapshotMechanismDataUnexpected` for a record declaring `MECHANISM_DATA`.
    /// @return The empty bytes expression.
    function releasedMechanismData(Vm vm, string memory path, string memory) internal view returns (string memory) {
        if (LibRainDeploySnapshot.recordDeclaresMechanismData(vm, path)) {
            revert FrozenSnapshotMechanismDataUnexpected(path);
        }
        return "\"\"";
    }
}
