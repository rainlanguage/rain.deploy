// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeployDeclaration, DeployMechanismHandler, DeploySuite} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {LibMockCreate2Mechanism, MOCK_CREATE2_FACTORY} from "./LibMockCreate2Mechanism.sol";
import {LibMockMechanismProbe} from "./LibMockMechanismProbe.sol";
import {MockCreate2Factory} from "../concrete/MockCreate2Factory.sol";

bytes32 constant MOCK_SALT_MECHANISM_ID = keccak256("rain.deploy.mock.salt.mechanism");

/// @title LibMockSaltMechanism
/// @notice A second test-only mechanism: CREATE2 through `MockCreate2Factory` at `MOCK_CREATE2_FACTORY`, one address
/// on every network, its `mechanismData` its id and the salt, abi-encoded.
library LibMockSaltMechanism {
    event MockSaltVerification(string suite, address deployed);

    function handler() internal pure returns (DeployMechanismHandler memory) {
        return DeployMechanismHandler({
            id: MOCK_SALT_MECHANISM_ID,
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
            logVerification: logVerification,
            writeSuiteSnapshot: writeSuiteSnapshot,
            releasedMechanismData: releasedMechanismData
        });
    }

    /// Appends the mock salt handler to `d`.
    /// @param d The declaration, mutated.
    function extend(DeployDeclaration memory d) internal pure {
        LibRainDeployDeclaration.addMechanism(d, handler());
    }

    function encode(bytes32 create2Salt) internal pure returns (bytes memory) {
        return abi.encode(MOCK_SALT_MECHANISM_ID, create2Salt);
    }

    function salt(DeploySuite memory suite) internal pure returns (bytes32) {
        (, bytes32 create2Salt) = abi.decode(suite.mechanismData, (bytes32, bytes32));
        return create2Salt;
    }

    function deployedAddress(DeploySuite memory suite, uint256) internal pure returns (address) {
        return LibMockCreate2Mechanism.create2Address(MOCK_CREATE2_FACTORY, salt(suite), suite.creationCode);
    }

    function recordedAddress(DeploySuite memory suite, uint256) internal pure returns (address) {
        return suite.storedDeployedAddress;
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

    /// @return Its one address, once per each of its `networks`.
    function deployLocally(Vm vm, DeploySuite memory suite) internal returns (address[] memory) {
        LibRainDeploy.etchDependencies(vm, suite.dependencies);
        vm.etch(MOCK_CREATE2_FACTORY, type(MockCreate2Factory).runtimeCode);
        address one = MockCreate2Factory(MOCK_CREATE2_FACTORY).deploy(salt(suite), suite.creationCode);
        address[] memory deployed = new address[](suite.networks.length);
        for (uint256 i = 0; i < deployed.length; i++) {
            deployed[i] = one;
        }
        return deployed;
    }

    function deployLocallyOnChain(Vm vm, DeploySuite memory suite) internal {
        deployLocally(vm, suite);
    }

    function addUnrecordedNetworks(DeploySuite memory, DeploySuite memory, uint256[] memory) internal pure {}

    function addRecordedNetworks(DeploySuite memory suite) internal view {
        LibMockMechanismProbe.addRecordedNetworks(MOCK_SALT_MECHANISM_ID, suite.suite);
    }

    function checkNetworkFrozen(DeploySuite memory, string memory, uint256, address) internal pure {}

    function checkOnChain(DeploySuite memory suite, string memory network, uint256 chainId, address deployed)
        internal
        view
    {
        LibMockMechanismProbe.checkOnChain(MOCK_SALT_MECHANISM_ID, suite.suite, network, chainId, deployed);
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
        string memory path = LibRainDeploySnapshot.writeSnapshot(
            vm, root, dir, contractName, spdxLicenseIdentifier, copyrightText, suite.creationCode, suite.dependencies
        );
        vm.writeLine(
            path,
            string.concat(
                "bytes constant MECHANISM_DATA = hex\"", vm.replace(vm.toString(suite.mechanismData), "0x", ""), "\";"
            )
        );
        return path;
    }

    function releasedMechanismData(Vm, string memory, string memory prefix) internal pure returns (string memory) {
        return string.concat(prefix, "_MECHANISM_DATA");
    }
}
