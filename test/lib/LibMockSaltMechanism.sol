// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeployMechanismHandler, DeploySuite, ExtendedNetworksUnexpected} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ChainDeploy} from "../../src/lib/LibRainDeployExtendedNetworks.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {LibMockCreate2Mechanism, MOCK_CREATE2_FACTORY} from "./LibMockCreate2Mechanism.sol";
import {MockCreate2Factory} from "../concrete/MockCreate2Factory.sol";

/// @title LibMockSaltMechanism
/// @notice A second test-only mechanism: CREATE2 through `MockCreate2Factory` at `MOCK_CREATE2_FACTORY`, one address
/// on every network, its `mechanismData` one word, the abi-encoded salt. It declines every released record.
library LibMockSaltMechanism {
    event MockSaltVerification(string suite, address deployed);

    function handler() internal pure returns (DeployMechanismHandler memory) {
        return DeployMechanismHandler({
            claims: claims,
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

    function claims(DeploySuite memory suite) internal pure returns (bool) {
        return suite.mechanismData.length == 32;
    }

    function salt(DeploySuite memory suite) internal pure returns (bytes32) {
        return abi.decode(suite.mechanismData, (bytes32));
    }

    function deployedAddress(DeploySuite memory suite, uint256) internal pure returns (address) {
        return LibMockCreate2Mechanism.create2Address(MOCK_CREATE2_FACTORY, salt(suite), suite.creationCode);
    }

    function recordedAddress(DeploySuite memory suite, uint256) internal pure returns (address) {
        return suite.storedDeployedAddress;
    }

    function addressChainIds(DeploySuite memory) internal pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    function deployStepData(DeploySuite memory suite, uint256) internal pure returns (bytes memory) {
        return abi.encode(MOCK_CREATE2_FACTORY, salt(suite), suite.creationCode);
    }

    function deployStep(DeploySuite memory)
        internal
        pure
        returns (function(Vm, string memory, address, bytes memory) internal returns (address))
    {
        return LibMockCreate2Mechanism.create2DeployStep;
    }

    function deployLocally(Vm vm, DeploySuite memory suite) internal returns (address[] memory) {
        LibRainDeploy.etchDependencies(vm, suite.dependencies);
        vm.etch(MOCK_CREATE2_FACTORY, type(MockCreate2Factory).runtimeCode);
        address[] memory deployed = new address[](1);
        deployed[0] = MockCreate2Factory(MOCK_CREATE2_FACTORY).deploy(salt(suite), suite.creationCode);
        return deployed;
    }

    function deployLocallyOnChain(Vm vm, DeploySuite memory suite) internal {
        deployLocally(vm, suite);
    }

    function withUnrecordedNetworks(DeploySuite memory suite, DeploySuite memory, uint256[] memory)
        internal
        pure
        returns (DeploySuite memory)
    {
        return suite;
    }

    function appendExtendedNetworks(DeploySuite memory suite, ChainDeploy[] memory extended)
        internal
        pure
        returns (DeploySuite memory)
    {
        if (extended.length != 0) {
            revert ExtendedNetworksUnexpected(suite.suite);
        }
        return suite;
    }

    function checkNetworkFrozen(DeploySuite memory, string memory, uint256, address) internal pure {}

    function suiteBeacon(DeploySuite memory, uint256) internal pure returns (address) {
        return address(0);
    }

    function logVerification(Vm, string[] memory, DeploySuite memory suite, address[] memory deployed) internal {
        emit MockSaltVerification(suite.suite, deployed[0]);
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
        return LibRainDeploySnapshot.writeSnapshot(
            vm, root, dir, contractName, spdxLicenseIdentifier, copyrightText, suite.creationCode, suite.dependencies
        );
    }

    function releasedMechanismData(Vm, string memory, string memory) internal pure returns (string memory) {
        return "";
    }
}
