// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {
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
/// @notice The Zoltu bodies of the `RainDeploySuitesBase` mechanism hooks, one function per hook, for
/// `RainDeployZoltuSuitesBase` and for any mechanism that deploys its suites with empty `mechanismData` through Zoltu.
library LibRainDeployZoltuMechanism {
    /// Refuses `UnexpectedMechanismData` for a Zoltu suite carrying mechanism data.
    /// @param suite The Zoltu suite.
    function checkMechanismData(DeploySuite memory suite) internal pure {
        if (suite.mechanismData.length != 0) {
            revert UnexpectedMechanismData(suite.suite);
        }
    }

    /// @param suite The suite.
    /// @return The Zoltu address of its creation code, on every network.
    function deployedAddress(DeploySuite memory suite) internal pure returns (address) {
        checkMechanismData(suite);
        return LibRainDeploy.zoltuAddress(suite.creationCode);
    }

    /// @param suite The suite.
    /// @return Its recorded address, on every network.
    function recordedAddress(DeploySuite memory suite) internal pure returns (address) {
        checkMechanismData(suite);
        return suite.storedDeployedAddress;
    }

    /// @param suite The suite.
    /// @return No chain ids: one address on every network.
    function addressChainIds(DeploySuite memory suite) internal pure returns (uint256[] memory) {
        checkMechanismData(suite);
        return new uint256[](0);
    }

    /// @param suite The suite.
    /// @return Its creation code, on every network.
    function deployStepData(DeploySuite memory suite) internal pure returns (bytes memory) {
        checkMechanismData(suite);
        return suite.creationCode;
    }

    /// @param suite The suite.
    /// @return `LibRainDeploy.zoltuDeployStep`.
    function deployStep(DeploySuite memory suite)
        internal
        pure
        returns (function(Vm, string memory, address, bytes memory) internal returns (address))
    {
        checkMechanismData(suite);
        return LibRainDeploy.zoltuDeployStep;
    }

    /// Deploys a suite through the etched Zoltu factory with its declared dependencies etched, refusing
    /// `ZoltuDerivationMismatch` where the factory and `LibRainDeploy.zoltuAddress` disagree.
    /// @param vm The Vm instance to etch with.
    /// @param suite The suite to deploy.
    /// @return Its one address.
    function deployLocally(Vm vm, DeploySuite memory suite) internal returns (address[] memory) {
        address[] memory deployed = new address[](1);
        deployed[0] = deployedAddress(suite);
        LibRainDeploy.etchDependencies(vm, suite.dependencies);
        vm.etch(deployed[0], hex"");
        vm.resetNonce(deployed[0]);
        address zoltuAddress = LibRainDeploy.etchAndDeployZoltu(vm, suite.creationCode);
        if (zoltuAddress != deployed[0]) {
            revert ZoltuDerivationMismatch(suite.suite, deployed[0], zoltuAddress);
        }
        return deployed;
    }

    /// `deployLocally`: the address is the same on every network.
    /// @param vm The Vm instance to etch with.
    /// @param suite The suite to deploy.
    function deployLocallyOnChain(Vm vm, DeploySuite memory suite) internal {
        deployLocally(vm, suite);
    }

    /// @param suite The suite.
    /// @return `suite`: its one address covers every network.
    function withUnrecordedNetworks(DeploySuite memory suite) internal pure returns (DeploySuite memory) {
        checkMechanismData(suite);
        return suite;
    }

    /// Refuses `ExtendedNetworksUnexpected` for any extended network.
    /// @param suite The release.
    /// @param extended The networks declared for it.
    /// @return `suite`.
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

    /// Refuses no network.
    /// @param frozen The release.
    function checkNetworkFrozen(DeploySuite memory frozen) internal pure {
        checkMechanismData(frozen);
    }

    /// @param suite The suite.
    /// @return No beacon.
    function suiteBeacon(DeploySuite memory suite) internal pure returns (address) {
        checkMechanismData(suite);
        return address(0);
    }

    /// Logs the verify command for the suite's one address.
    /// @param vm The Vm instance to format with.
    /// @param networks The networks it was broadcast to.
    /// @param suite The suite.
    /// @param deployed Its address on each network.
    function logVerification(Vm vm, string[] memory networks, DeploySuite memory suite, address[] memory deployed)
        internal
        pure
    {
        checkMechanismData(suite);
        LibRainDeploy.logVerifyCommands(vm, networks, deployed[0], suite.artifactPath);
    }

    /// Writes the suite's snapshot with `LibRainDeploySnapshot.writeSnapshot`.
    /// @param vm The Vm instance for file operations.
    /// @param root The record root.
    /// @param dir The snapshot directory name.
    /// @param contractName The contract the snapshot describes.
    /// @param spdxLicenseIdentifier The SPDX licence identifier the snapshot declares.
    /// @param copyrightText The copyright text the snapshot declares.
    /// @param suite The suite to snapshot.
    /// @return The path written.
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
    /// @param vm The Vm instance for file and string operations.
    /// @param path The release's record file.
    /// @return The empty bytes expression.
    function releasedMechanismData(Vm vm, string memory path) internal view returns (string memory) {
        if (LibRainDeploySnapshot.recordDeclaresMechanismData(vm, path)) {
            revert FrozenSnapshotMechanismDataUnexpected(path);
        }
        return "\"\"";
    }
}
