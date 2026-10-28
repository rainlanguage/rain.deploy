// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {
    DeployDeclaration,
    DeployMechanismHandler,
    DeploySuite,
    FrozenSnapshotMechanismDataUnexpected,
    SnapshotFile,
    UnexpectedMechanismData,
    ZoltuDerivationMismatch
} from "../abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "./LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "./LibRainDeployDeclaration.sol";
import {LibRainDeploySnapshot} from "./LibRainDeploySnapshot.sol";

/// @dev The Zoltu mechanism's id.
bytes32 constant ZOLTU_MECHANISM_ID = keccak256("rain.deploy.mechanism.zoltu");

/// @dev Where `LibRainDeployZoltuMechanism` is declared inside this package, below the source root.
string constant ZOLTU_MECHANISM_SOURCE_SUBPATH = "lib/LibRainDeployZoltuMechanism.sol";

/// @title LibRainDeployZoltuMechanism
/// @notice The Zoltu mechanism: one address on every network, from the creation code alone. Its `mechanismData` is
/// `abi.encode(ZOLTU_MECHANISM_ID)`, and every step refuses any other with `UnexpectedMechanismData`.
library LibRainDeployZoltuMechanism {
    /// @return The Zoltu handler.
    function handler() internal pure returns (DeployMechanismHandler memory) {
        return DeployMechanismHandler({
            id: ZOLTU_MECHANISM_ID,
            config: "",
            deployedAddress: deployedAddress,
            recordedAddress: recordedAddress,
            deployStepData: deployStepData,
            deployStep: deployStep,
            deployLocally: deployLocally,
            deployLocallyOnChain: deployLocallyOnChain,
            addUnrecordedNetworks: addUnrecordedNetworks,
            addRecordedNetworks: addRecordedNetworks,
            checkNetworkFrozen: checkNetworkFrozen,
            checkOnChain: checkOnChain,
            checkBroadcastSeat: checkBroadcastSeat,
            checkDeclaration: checkDeclaration,
            checkNetwork: checkNetwork,
            logVerification: logVerification,
            writeSuiteSnapshot: writeSuiteSnapshot,
            releasedMechanismData: releasedMechanismData,
            releasedImport: releasedImport,
            legacyRecordId: legacyRecordId
        });
    }

    /// Appends the Zoltu handler to `d`.
    /// @param d The declaration, mutated.
    function extend(DeployDeclaration memory d) internal pure {
        LibRainDeployDeclaration.addMechanism(d, handler());
    }

    /// @return The `mechanismData` of a Zoltu suite.
    function mechanismData() internal pure returns (bytes memory) {
        return abi.encode(ZOLTU_MECHANISM_ID);
    }

    function checkMechanismData(DeploySuite memory suite) internal pure {
        if (keccak256(suite.mechanismData) != keccak256(mechanismData())) {
            revert UnexpectedMechanismData(suite.suite);
        }
    }

    /// @return The Zoltu address of its creation code, on every network.
    function deployedAddress(DeployDeclaration memory, DeploySuite memory suite, uint256)
        internal
        pure
        returns (address)
    {
        checkMechanismData(suite);
        return LibRainDeploy.zoltuAddress(suite.creationCode);
    }

    /// @return Its recorded address, on every network.
    function recordedAddress(DeployDeclaration memory, DeploySuite memory suite, uint256)
        internal
        pure
        returns (address)
    {
        checkMechanismData(suite);
        return suite.storedDeployedAddress;
    }

    /// @return Its creation code, on every network.
    function deployStepData(DeployDeclaration memory, DeploySuite memory suite, uint256)
        internal
        pure
        returns (bytes memory)
    {
        checkMechanismData(suite);
        return suite.creationCode;
    }

    function deployStep(DeployDeclaration memory, DeploySuite memory suite)
        internal
        pure
        returns (function(Vm, string memory, address, bytes memory) internal returns (address))
    {
        checkMechanismData(suite);
        return LibRainDeploy.zoltuDeployStep;
    }

    /// Deploys through the etched Zoltu factory with the declared dependencies etched, refusing
    /// `ZoltuDerivationMismatch` where the factory and `LibRainDeploy.zoltuAddress` disagree.
    /// @return Its one address, once per each of its `networks`.
    function deployLocally(DeployDeclaration memory d, Vm vm, DeploySuite memory suite)
        internal
        returns (address[] memory)
    {
        address expected = deployedAddress(d, suite, 0);
        LibRainDeploy.etchDependencies(vm, suite.dependencies);
        vm.etch(expected, hex"");
        vm.resetNonce(expected);
        address zoltuAddress = LibRainDeploy.etchAndDeployZoltu(vm, suite.creationCode);
        if (zoltuAddress != expected) {
            revert ZoltuDerivationMismatch(suite.suite, expected, zoltuAddress);
        }
        address[] memory deployed = new address[](suite.networks.length);
        for (uint256 i = 0; i < deployed.length; i++) {
            deployed[i] = expected;
        }
        return deployed;
    }

    function deployLocallyOnChain(DeployDeclaration memory d, Vm vm, DeploySuite memory suite, uint256 chainId)
        internal
    {
        vm.chainId(chainId);
        deployLocally(d, vm, suite);
    }

    /// Its one address covers every network, so there is nothing to add.
    function addUnrecordedNetworks(
        DeployDeclaration memory,
        DeploySuite memory suite,
        DeploySuite memory,
        uint256[] memory
    ) internal pure {
        checkMechanismData(suite);
    }

    /// A Zoltu release records no networks beyond its declared ones.
    function addRecordedNetworks(DeployDeclaration memory, DeploySuite memory suite) internal pure {
        checkMechanismData(suite);
    }

    function checkNetworkFrozen(DeployDeclaration memory, DeploySuite memory frozen, string memory, uint256, address)
        internal
        pure
    {
        checkMechanismData(frozen);
    }

    function checkOnChain(DeployDeclaration memory, DeploySuite memory suite, string memory, uint256, address)
        internal
        pure
    {
        checkMechanismData(suite);
    }

    function checkBroadcastSeat(DeployDeclaration memory, DeploySuite memory suite, uint256, address) internal pure {
        checkMechanismData(suite);
    }

    function checkDeclaration(DeployDeclaration memory) internal pure {}

    function checkNetwork(DeployDeclaration memory, string memory, uint256) internal pure {}

    function logVerification(
        DeployDeclaration memory,
        Vm vm,
        string[] memory networks,
        DeploySuite memory suite,
        address[] memory deployed
    ) internal pure {
        checkMechanismData(suite);
        LibRainDeploy.logVerifyCommands(vm, networks, deployed[0], suite.artifactPath);
    }

    function writeSuiteSnapshot(DeployDeclaration memory, Vm vm, SnapshotFile memory file, DeploySuite memory suite)
        internal
        returns (string memory)
    {
        checkMechanismData(suite);
        return LibRainDeploySnapshot.writeSnapshot(
            vm,
            file.root,
            file.dir,
            file.contractName,
            file.spdxLicenseIdentifier,
            file.copyrightText,
            suite.creationCode,
            suite.dependencies
        );
    }

    /// Refuses `FrozenSnapshotMechanismDataUnexpected` for a record declaring `MECHANISM_DATA`.
    /// @return The expression of `mechanismData()`.
    function releasedMechanismData(DeployDeclaration memory, Vm vm, string memory path, string memory)
        internal
        view
        returns (string memory)
    {
        if (LibRainDeploySnapshot.recordDeclaresMechanismData(vm, path)) {
            revert FrozenSnapshotMechanismDataUnexpected(path);
        }
        return "LibRainDeployZoltuMechanism.mechanismData()";
    }

    /// @param root The import root of this package's source root.
    /// @return The import of this library that `releasedMechanismData`'s expression needs.
    function releasedImport(DeployDeclaration memory, string memory root) internal pure returns (string memory) {
        return
            string.concat("import {LibRainDeployZoltuMechanism} from \"", root, ZOLTU_MECHANISM_SOURCE_SUBPATH, "\";\n");
    }

    /// @return 0: a Zoltu record never declares `MECHANISM_DATA`, so no untagged legacy record is Zoltu's.
    function legacyRecordId(DeployDeclaration memory, Vm, string memory) internal pure returns (bytes32) {
        return 0;
    }
}
