// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeployMechanismHandler, DeploySuite, ExtendedNetworksUnexpected} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ChainDeploy} from "../../src/lib/LibRainDeployExtendedNetworks.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {MockCreate2Factory} from "../concrete/MockCreate2Factory.sol";

/// The mechanism data of a `LibMockCreate2Mechanism` suite. Empty `networks` is one address on every network, at
/// `salt`; otherwise each network deploys at `keccak256(abi.encode(salt, data))`.
struct MockCreate2Mechanism {
    address factory;
    bytes32 salt;
    address beacon;
    ChainDeploy[] networks;
}

address constant MOCK_CREATE2_FACTORY = address(uint160(uint256(keccak256("rain.deploy.mock.create2.factory"))));

bytes32 constant MOCK_CREATE2_SALT = keccak256("rain.deploy.mock.create2.salt");

bytes32 constant MOCK_CREATE2_MECHANISM_ID = keccak256("rain.deploy.mock.create2.mechanism");

error MockCreate2NetworkUndeclared(string suite, uint256 chainId);

error MockCreate2NetworkUnfrozen(string suite, string network, address where);

error MockCreate2DerivationMismatch(string suite, address derived, address deployed);

/// @title LibMockCreate2Mechanism
/// @notice A test-only mechanism: CREATE2 through `MockCreate2Factory`, `mechanismData` its id and a
/// `MockCreate2Mechanism`, abi-encoded.
library LibMockCreate2Mechanism {
    event MockCreate2Verification(string[] networks, string suite, address[] deployed);

    function handler() internal pure returns (DeployMechanismHandler memory) {
        return DeployMechanismHandler({
            id: MOCK_CREATE2_MECHANISM_ID,
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

    function isMockCreate2(DeploySuite memory suite) internal pure returns (bool) {
        return suite.mechanismData.length > 0x20 && abi.decode(suite.mechanismData, (bytes32)) == MOCK_CREATE2_MECHANISM_ID;
    }

    function create2Address(address factory, bytes32 create2Salt, bytes memory creationCode) internal pure returns (address) {
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

    function withMechanism(DeploySuite memory suite, MockCreate2Mechanism memory mechanism)
        internal
        pure
        returns (DeploySuite memory)
    {
        DeploySuite memory copy = abi.decode(abi.encode(suite), (DeploySuite));
        copy.mechanismData = encode(mechanism);
        return copy;
    }

    function networkIndex(MockCreate2Mechanism memory mechanism, uint256 chainId)
        internal
        pure
        returns (bool, uint256)
    {
        for (uint256 i = 0; i < mechanism.networks.length; i++) {
            if (mechanism.networks[i].chainId == chainId) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    function salt(DeploySuite memory suite, uint256 chainId) internal pure returns (bytes32) {
        MockCreate2Mechanism memory mechanism = decode(suite);
        if (mechanism.networks.length == 0) {
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

    function deployedAddress(DeploySuite memory suite, uint256 chainId) internal pure returns (address) {
        return create2Address(decode(suite).factory, salt(suite, chainId), suite.creationCode);
    }

    function recordedAddress(DeploySuite memory suite, uint256 chainId) internal pure returns (address) {
        MockCreate2Mechanism memory mechanism = decode(suite);
        if (mechanism.networks.length == 0) {
            return suite.storedDeployedAddress;
        }
        (bool found, uint256 index) = networkIndex(mechanism, chainId);
        if (!found) {
            revert MockCreate2NetworkUndeclared(suite.suite, chainId);
        }
        return mechanism.networks[index].deployedAddress;
    }

    function addressChainIds(DeploySuite memory suite) internal pure returns (uint256[] memory) {
        MockCreate2Mechanism memory mechanism = decode(suite);
        uint256[] memory chainIds = new uint256[](mechanism.networks.length);
        for (uint256 i = 0; i < chainIds.length; i++) {
            chainIds[i] = mechanism.networks[i].chainId;
        }
        return chainIds;
    }

    function deployStepData(DeploySuite memory suite, uint256 chainId) internal pure returns (bytes memory) {
        return abi.encode(decode(suite).factory, salt(suite, chainId), suite.creationCode);
    }

    function deployStep(DeploySuite memory)
        internal
        pure
        returns (function(Vm, string memory, address, bytes memory) internal returns (address))
    {
        return create2DeployStep;
    }

    function deployLocally(Vm vm, DeploySuite memory suite) internal returns (address[] memory) {
        etchFactory(vm, suite);
        uint256[] memory chainIds = addressChainIds(suite);
        address[] memory deployed = new address[](chainIds.length == 0 ? 1 : chainIds.length);
        for (uint256 i = 0; i < deployed.length; i++) {
            uint256 chainId = chainIds.length == 0 ? 0 : chainIds[i];
            deployed[i] = deployedAddress(suite, chainId);
            deployAt(vm, suite, salt(suite, chainId), deployed[i]);
        }
        return deployed;
    }

    function deployLocallyOnChain(Vm vm, DeploySuite memory suite) internal {
        etchFactory(vm, suite);
        uint256 chainId = decode(suite).networks.length == 0 ? 0 : block.chainid;
        deployAt(vm, suite, salt(suite, chainId), deployedAddress(suite, chainId));
    }

    function withUnrecordedNetworks(DeploySuite memory suite, DeploySuite memory candidate, uint256[] memory chainIds)
        internal
        pure
        returns (DeploySuite memory)
    {
        MockCreate2Mechanism memory mechanism = decode(suite);
        if (mechanism.networks.length == 0 || !isMockCreate2(candidate)) {
            return suite;
        }
        MockCreate2Mechanism memory candidateMechanism = decode(candidate);
        ChainDeploy[] memory added = new ChainDeploy[](chainIds.length);
        uint256 count = 0;
        for (uint256 i = 0; i < chainIds.length; i++) {
            (bool recorded,) = networkIndex(mechanism, chainIds[i]);
            (bool candidateHas, uint256 index) = networkIndex(candidateMechanism, chainIds[i]);
            if (!recorded && candidateHas) {
                added[count++] = derivedNetwork(suite, candidateMechanism.networks[index]);
            }
        }
        return withNetworks(suite, mechanism, added, count);
    }

    function derivedNetwork(DeploySuite memory suite, ChainDeploy memory candidateNetwork)
        internal
        pure
        returns (ChainDeploy memory)
    {
        MockCreate2Mechanism memory mechanism = decode(suite);
        return ChainDeploy({
            chainId: candidateNetwork.chainId,
            data: candidateNetwork.data,
            deployedAddress: create2Address(
                mechanism.factory, networkSalt(mechanism.salt, candidateNetwork.data), suite.creationCode
            )
        });
    }

    function withNetworks(
        DeploySuite memory suite,
        MockCreate2Mechanism memory mechanism,
        ChainDeploy[] memory more,
        uint256 count
    ) internal pure returns (DeploySuite memory) {
        ChainDeploy[] memory networks = new ChainDeploy[](mechanism.networks.length + count);
        for (uint256 i = 0; i < mechanism.networks.length; i++) {
            networks[i] = mechanism.networks[i];
        }
        for (uint256 i = 0; i < count; i++) {
            networks[mechanism.networks.length + i] = more[i];
        }
        mechanism.networks = networks;
        return withMechanism(suite, mechanism);
    }

    function appendExtendedNetworks(DeploySuite memory suite, ChainDeploy[] memory extended)
        internal
        pure
        returns (DeploySuite memory)
    {
        if (extended.length == 0) {
            return suite;
        }
        MockCreate2Mechanism memory mechanism = decode(suite);
        if (mechanism.networks.length == 0) {
            revert ExtendedNetworksUnexpected(suite.suite);
        }
        return withNetworks(suite, mechanism, extended, extended.length);
    }

    function checkNetworkFrozen(DeploySuite memory frozen, string memory network, uint256 chainId, address where)
        internal
        pure
    {
        MockCreate2Mechanism memory mechanism = decode(frozen);
        if (mechanism.networks.length == 0) {
            return;
        }
        (bool found,) = networkIndex(mechanism, chainId);
        if (!found) {
            revert MockCreate2NetworkUnfrozen(frozen.suite, network, where);
        }
    }

    function suiteBeacon(DeploySuite memory suite, uint256) internal pure returns (address) {
        return decode(suite).beacon;
    }

    function logVerification(Vm, string[] memory networks, DeploySuite memory suite, address[] memory deployed)
        internal
    {
        emit MockCreate2Verification(networks, suite.suite, deployed);
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
