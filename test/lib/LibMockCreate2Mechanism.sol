// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {StdConstants} from "forge-std-1.17.0/src/StdConstants.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {
    DeployDeclaration,
    DeployMechanismHandler,
    DeploySuite,
    SnapshotFile
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy, SupportedNetwork} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {MockCreate2Factory} from "../concrete/MockCreate2Factory.sol";
import {LibMockMechanismProbe} from "./LibMockMechanismProbe.sol";
import {LibMockNetworkRecord, MockNetworkDeploy} from "./LibMockNetworkRecord.sol";

/// The payload of a `LibMockCreate2Mechanism` suite. Not `perNetwork`: one address on every network, at `salt`.
/// `perNetwork`: each network of `networks` deploys at `keccak256(abi.encode(salt, data))`, and `addRecordedNetworks`
/// adds the networks recorded under `root` (none when `root` is empty).
struct MockCreate2Mechanism {
    address factory;
    bytes32 salt;
    bool perNetwork;
    MockNetworkDeploy[] networks;
    string root;
}

address constant MOCK_CREATE2_FACTORY = address(uint160(uint256(keccak256("rain.deploy.mock.create2.factory"))));

bytes32 constant MOCK_CREATE2_SALT = keccak256("rain.deploy.mock.create2.salt");

bytes32 constant MOCK_CREATE2_MECHANISM_ID = keccak256("rain.deploy.mock.create2.mechanism");

error MockCreate2NetworkUndeclared(string suite, uint256 chainId);

error MockCreate2NetworkUnfrozen(string suite, string network, address where);

error MockCreate2DerivationMismatch(string suite, address derived, address deployed);

error MockCreate2ChainUnsupported(uint256 chainId);

/// @title LibMockCreate2Mechanism
/// @notice A test-only mechanism: CREATE2 through `MockCreate2Factory`, `mechanismData` its id and a
/// `MockCreate2Mechanism`, abi-encoded. Its per-network mode stands in for a clone layer: it reads its own records.
library LibMockCreate2Mechanism {
    event MockCreate2Verification(string[] networks, string suite, address[] deployed);

    function handler() internal pure returns (DeployMechanismHandler memory) {
        return DeployMechanismHandler({
            id: MOCK_CREATE2_MECHANISM_ID,
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
            releasedImport: releasedImport
        });
    }

    /// Appends the mock create2 handler to `d`.
    /// @param d The declaration, mutated.
    function extend(DeployDeclaration memory d) internal pure {
        LibRainDeployDeclaration.addMechanism(d, handler());
    }

    function isMockCreate2(DeploySuite memory suite) internal pure returns (bool) {
        return
            suite.mechanismData.length > 0x20 && abi.decode(suite.mechanismData, (bytes32)) == MOCK_CREATE2_MECHANISM_ID;
    }

    function create2Address(address factory, bytes32 create2Salt, bytes memory creationCode)
        internal
        pure
        returns (address)
    {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), factory, create2Salt, keccak256(creationCode)))))
        );
    }

    function networkSalt(bytes32 baseSalt, bytes memory data) internal pure returns (bytes32) {
        return keccak256(abi.encode(baseSalt, data));
    }

    function encode(MockCreate2Mechanism memory mechanism) internal pure returns (bytes memory) {
        return abi.encode(MOCK_CREATE2_MECHANISM_ID, mechanism);
    }

    function decode(DeploySuite memory suite) internal pure returns (MockCreate2Mechanism memory) {
        (, MockCreate2Mechanism memory mechanism) = abi.decode(suite.mechanismData, (bytes32, MockCreate2Mechanism));
        return mechanism;
    }

    /// The network a per-network suite deploys to on `chainId` with `data`, at its derived address.
    function network(address factory, bytes32 baseSalt, bytes memory creationCode, uint256 chainId, bytes memory data)
        internal
        pure
        returns (MockNetworkDeploy memory)
    {
        return MockNetworkDeploy({
            chainId: chainId,
            data: data,
            deployedAddress: create2Address(factory, networkSalt(baseSalt, data), creationCode)
        });
    }

    /// @return The `[rpc_endpoints]` alias of each of `networks`' chain ids, in order.
    function networkNames(MockNetworkDeploy[] memory networks) internal pure returns (string[] memory) {
        string[] memory names = new string[](networks.length);
        for (uint256 i = 0; i < networks.length; i++) {
            names[i] = networkName(networks[i].chainId);
        }
        return names;
    }

    function networkName(uint256 chainId) internal pure returns (string memory) {
        SupportedNetwork[] memory configs = LibRainDeploy.supportedNetworkConfigs();
        for (uint256 i = 0; i < configs.length; i++) {
            if (configs[i].chainId == chainId) {
                return configs[i].name;
            }
        }
        revert MockCreate2ChainUnsupported(chainId);
    }

    function networkIndex(MockCreate2Mechanism memory mechanism, uint256 chainId)
        internal
        pure
        returns (bool, uint256)
    {
        uint256 i = 0;
        while (i < mechanism.networks.length && mechanism.networks[i].chainId != chainId) {
            i++;
        }
        bool found = i < mechanism.networks.length;
        return (found, found ? i : 0);
    }

    function salt(DeploySuite memory suite, uint256 chainId) internal pure returns (bytes32) {
        MockCreate2Mechanism memory mechanism = decode(suite);
        if (!mechanism.perNetwork) {
            return mechanism.salt;
        }
        (bool found, uint256 index) = networkIndex(mechanism, chainId);
        if (!found) {
            revert MockCreate2NetworkUndeclared(suite.suite, chainId);
        }
        return networkSalt(mechanism.salt, mechanism.networks[index].data);
    }

    function create2DeployStep(Vm vm, string memory, address deployer, bytes memory data) internal returns (address) {
        (address factory, bytes32 stepSalt, bytes memory creationCode) = abi.decode(data, (address, bytes32, bytes));
        vm.startBroadcast(deployer);
        address deployed = MockCreate2Factory(factory).deploy(stepSalt, creationCode);
        vm.stopBroadcast();
        return deployed;
    }

    function deployAt(Vm vm, DeploySuite memory suite, bytes32 atSalt, address derived) internal {
        vm.etch(derived, hex"");
        vm.resetNonce(derived);
        address deployed = MockCreate2Factory(decode(suite).factory).deploy(atSalt, suite.creationCode);
        if (deployed != derived) {
            revert MockCreate2DerivationMismatch(suite.suite, derived, deployed);
        }
    }

    function etchFactory(Vm vm, DeploySuite memory suite) internal {
        LibRainDeploy.etchDependencies(vm, suite.dependencies);
        vm.etch(decode(suite).factory, type(MockCreate2Factory).runtimeCode);
    }

    function deployedAddress(DeployDeclaration memory, DeploySuite memory suite, uint256 chainId) internal pure returns (address) {
        return create2Address(decode(suite).factory, salt(suite, chainId), suite.creationCode);
    }

    function recordedAddress(DeployDeclaration memory, DeploySuite memory suite, uint256 chainId) internal pure returns (address) {
        MockCreate2Mechanism memory mechanism = decode(suite);
        if (!mechanism.perNetwork) {
            return suite.storedDeployedAddress;
        }
        (bool found, uint256 index) = networkIndex(mechanism, chainId);
        if (!found) {
            revert MockCreate2NetworkUndeclared(suite.suite, chainId);
        }
        return mechanism.networks[index].deployedAddress;
    }

    function deployStepData(DeployDeclaration memory, DeploySuite memory suite, uint256 chainId) internal pure returns (bytes memory) {
        return abi.encode(decode(suite).factory, salt(suite, chainId), suite.creationCode);
    }

    function deployStep(DeployDeclaration memory, DeploySuite memory)
        internal
        pure
        returns (function(Vm, string memory, address, bytes memory) internal returns (address))
    {
        return create2DeployStep;
    }

    /// @return One address per each of its `networks`; a single-address suite is deployed once.
    function deployLocally(DeployDeclaration memory d, Vm vm, DeploySuite memory suite) internal returns (address[] memory) {
        etchFactory(vm, suite);
        uint256[] memory chainIds = LibRainDeploy.networkChainIds(LibRainDeploy.declaredNetworkConfigs(suite.networks));
        address[] memory deployed = new address[](chainIds.length);
        bool perNetwork = decode(suite).perNetwork;
        for (uint256 i = 0; i < deployed.length; i++) {
            deployed[i] = deployedAddress(d, suite, chainIds[i]);
            if (perNetwork || i == 0) {
                deployAt(vm, suite, salt(suite, chainIds[i]), deployed[i]);
            }
        }
        return deployed;
    }

    function deployLocallyOnChain(DeployDeclaration memory d, Vm vm, DeploySuite memory suite) internal {
        etchFactory(vm, suite);
        deployAt(vm, suite, salt(suite, block.chainid), deployedAddress(d, suite, block.chainid));
    }

    /// Per-network: adds to `suite` each of `chainIds` its candidate deploys to and it records nothing on, at the
    /// address `suite`'s own salt derives there. A single-address suite has nothing to add.
    function addUnrecordedNetworks(DeployDeclaration memory, DeploySuite memory suite, DeploySuite memory candidate, uint256[] memory chainIds)
        internal
        pure
    {
        MockCreate2Mechanism memory mechanism = decode(suite);
        if (!mechanism.perNetwork || !isMockCreate2(candidate)) {
            return;
        }
        MockCreate2Mechanism memory candidateMechanism = decode(candidate);
        MockNetworkDeploy[] memory added = new MockNetworkDeploy[](chainIds.length);
        uint256 count = 0;
        for (uint256 i = 0; i < chainIds.length; i++) {
            (bool recorded,) = networkIndex(mechanism, chainIds[i]);
            (bool candidateHas, uint256 index) = networkIndex(candidateMechanism, chainIds[i]);
            if (!recorded && candidateHas) {
                added[count++] = network(
                    mechanism.factory,
                    mechanism.salt,
                    suite.creationCode,
                    chainIds[i],
                    candidateMechanism.networks[index].data
                );
            }
        }
        addNetworks(suite, mechanism, added, count);
    }

    /// Probes, then per-network adds to `suite` the networks recorded for it under its `root`.
    function addRecordedNetworks(DeployDeclaration memory, DeploySuite memory suite) internal view {
        LibMockMechanismProbe.addRecordedNetworks(MOCK_CREATE2_MECHANISM_ID, suite.suite);
        MockCreate2Mechanism memory mechanism = decode(suite);
        if (!mechanism.perNetwork || bytes(mechanism.root).length == 0) {
            return;
        }
        MockNetworkDeploy[] memory recorded = LibMockNetworkRecord.read(StdConstants.VM, mechanism.root, suite.suite);
        addNetworks(suite, mechanism, recorded, recorded.length);
    }

    /// Appends the first `count` of `more` to `suite`'s payload networks and their aliases to its `networks`.
    function addNetworks(
        DeploySuite memory suite,
        MockCreate2Mechanism memory mechanism,
        MockNetworkDeploy[] memory more,
        uint256 count
    ) internal pure {
        if (count == 0) {
            return;
        }
        MockNetworkDeploy[] memory networks = new MockNetworkDeploy[](mechanism.networks.length + count);
        string[] memory names = new string[](suite.networks.length + count);
        for (uint256 i = 0; i < mechanism.networks.length; i++) {
            networks[i] = mechanism.networks[i];
        }
        for (uint256 i = 0; i < suite.networks.length; i++) {
            names[i] = suite.networks[i];
        }
        for (uint256 i = 0; i < count; i++) {
            networks[mechanism.networks.length + i] = more[i];
            names[suite.networks.length + i] = networkName(more[i].chainId);
        }
        mechanism.networks = networks;
        suite.networks = names;
        suite.mechanismData = encode(mechanism);
    }

    function checkNetworkFrozen(DeployDeclaration memory, DeploySuite memory frozen, string memory frozenNetwork, uint256 chainId, address where)
        internal
        pure
    {
        MockCreate2Mechanism memory mechanism = decode(frozen);
        if (!mechanism.perNetwork) {
            return;
        }
        (bool found,) = networkIndex(mechanism, chainId);
        if (!found) {
            revert MockCreate2NetworkUnfrozen(frozen.suite, frozenNetwork, where);
        }
    }

    function checkOnChain(
        DeployDeclaration memory,
        DeploySuite memory suite,
        string memory onNetwork,
        uint256 chainId,
        address deployed
    ) internal view {
        LibMockMechanismProbe.checkOnChain(MOCK_CREATE2_MECHANISM_ID, suite.suite, onNetwork, chainId, deployed);
    }

    function checkBroadcastSeat(DeployDeclaration memory, DeploySuite memory, uint256, address) internal pure {}

    function checkDeclaration(DeployDeclaration memory) internal view {
        LibMockMechanismProbe.checkDeclaration(MOCK_CREATE2_MECHANISM_ID);
    }

    function checkNetwork(DeployDeclaration memory, string memory onNetwork, uint256 chainId) internal view {
        LibMockMechanismProbe.checkNetwork(MOCK_CREATE2_MECHANISM_ID, onNetwork, chainId);
    }

    function logVerification(DeployDeclaration memory, Vm, string[] memory networks, DeploySuite memory suite, address[] memory deployed)
        internal
    {
        emit MockCreate2Verification(networks, suite.suite, deployed);
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

    function releasedMechanismData(DeployDeclaration memory, Vm, string memory, string memory prefix) internal pure returns (string memory) {
        return string.concat(prefix, "_MECHANISM_DATA");
    }

    function releasedImport(DeployDeclaration memory, string memory) internal pure returns (string memory) {
        return "";
    }
}
