// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {
    DeployDeclaration,
    DeployMechanismHandler,
    DeploySuite,
    SnapshotFile
} from "../../src/abstract/RainDeploySuitesBase.sol";
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

    function deployedAddress(DeployDeclaration memory, DeploySuite memory suite, uint256)
        internal
        pure
        returns (address)
    {
        return LibMockCreate2Mechanism.create2Address(MOCK_CREATE2_FACTORY, salt(suite), suite.creationCode);
    }

    function recordedAddress(DeployDeclaration memory, DeploySuite memory suite, uint256)
        internal
        pure
        returns (address)
    {
        return suite.storedDeployedAddress;
    }

    function deployStepData(DeployDeclaration memory, DeploySuite memory suite, uint256)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(MOCK_CREATE2_FACTORY, salt(suite), suite.creationCode);
    }

    function deployStep(DeployDeclaration memory, DeploySuite memory)
        internal
        pure
        returns (function(Vm, string memory, address, bytes memory) internal returns (address))
    {
        return LibMockCreate2Mechanism.create2DeployStep;
    }

    /// @return Its one address, once per each of its `networks`.
    function deployLocally(DeployDeclaration memory, Vm vm, DeploySuite memory suite)
        internal
        returns (address[] memory)
    {
        LibRainDeploy.etchDependencies(vm, suite.dependencies);
        vm.etch(MOCK_CREATE2_FACTORY, type(MockCreate2Factory).runtimeCode);
        address one = MockCreate2Factory(MOCK_CREATE2_FACTORY).deploy(salt(suite), suite.creationCode);
        address[] memory deployed = new address[](suite.networks.length);
        for (uint256 i = 0; i < deployed.length; i++) {
            deployed[i] = one;
        }
        return deployed;
    }

    function deployLocallyOnChain(DeployDeclaration memory d, Vm vm, DeploySuite memory suite) internal {
        deployLocally(d, vm, suite);
    }

    function addUnrecordedNetworks(DeployDeclaration memory, DeploySuite memory, DeploySuite memory, uint256[] memory)
        internal
        pure {}

    function addRecordedNetworks(DeployDeclaration memory, DeploySuite memory suite) internal view {
        LibMockMechanismProbe.addRecordedNetworks(MOCK_SALT_MECHANISM_ID, suite.suite);
    }

    function checkNetworkFrozen(DeployDeclaration memory, DeploySuite memory, string memory, uint256, address)
        internal
        pure {}

    function checkOnChain(
        DeployDeclaration memory,
        DeploySuite memory suite,
        string memory network,
        uint256 chainId,
        address deployed
    ) internal view {
        LibMockMechanismProbe.checkOnChain(MOCK_SALT_MECHANISM_ID, suite.suite, network, chainId, deployed);
    }

    function checkBroadcastSeat(DeployDeclaration memory, DeploySuite memory, uint256, address) internal pure {}

    function checkDeclaration(DeployDeclaration memory) internal view {
        LibMockMechanismProbe.checkDeclaration(MOCK_SALT_MECHANISM_ID);
    }

    /// Reports its config as `d` declares it, so a test pins that the hook reads the caller's declaration.
    function checkNetwork(DeployDeclaration memory d, string memory onNetwork, uint256 chainId) internal view {
        LibMockMechanismProbe.checkNetwork(MOCK_SALT_MECHANISM_ID, onNetwork, chainId);
        LibMockMechanismProbe.declaredConfig(
            MOCK_SALT_MECHANISM_ID, LibRainDeployDeclaration.mechanismById(d, MOCK_SALT_MECHANISM_ID, onNetwork).config
        );
    }

    function logVerification(
        DeployDeclaration memory,
        Vm,
        string[] memory,
        DeploySuite memory suite,
        address[] memory deployed
    ) internal {
        emit MockSaltVerification(suite.suite, deployed[0]);
    }

    function writeSuiteSnapshot(DeployDeclaration memory, Vm vm, SnapshotFile memory file, DeploySuite memory suite)
        internal
        returns (string memory)
    {
        string memory path = LibRainDeploySnapshot.writeSnapshot(
            vm,
            file.root,
            file.dir,
            file.contractName,
            file.spdxLicenseIdentifier,
            file.copyrightText,
            suite.creationCode,
            suite.dependencies
        );
        vm.writeLine(
            path,
            string.concat(
                "bytes constant MECHANISM_DATA = hex\"", vm.replace(vm.toString(suite.mechanismData), "0x", ""), "\";"
            )
        );
        return path;
    }

    function releasedMechanismData(DeployDeclaration memory, Vm, string memory, string memory prefix)
        internal
        pure
        returns (string memory)
    {
        return string.concat(prefix, "_MECHANISM_DATA");
    }

    function releasedImport(DeployDeclaration memory, string memory root) internal pure returns (string memory) {
        return string.concat("import {LibMockSaltMechanism} from \"", root, "../test/lib/LibMockSaltMechanism.sol\";\n");
    }

    function legacyRecordId(DeployDeclaration memory, Vm, string memory path) internal view returns (bytes32) {
        return LibMockMechanismProbe.legacyRecordId(MOCK_SALT_MECHANISM_ID, path);
    }
}
