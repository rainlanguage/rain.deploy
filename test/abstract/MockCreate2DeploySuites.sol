// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {
    DeployCandidate,
    DeployDependency,
    DeploySuite,
    ExtendedNetworksUnexpected,
    RainDeploySuitesBase
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {ChainDeploy} from "../../src/lib/LibRainDeployExtendedNetworks.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {MockCreate2Factory} from "../concrete/MockCreate2Factory.sol";
import {MockDeployable} from "../concrete/MockDeployable.sol";

/// The mechanism data of a `MockCreate2DeploySuites` suite. Empty `networks` is one address on every network, at
/// `salt`; otherwise each network deploys at `keccak256(abi.encode(salt, data))`.
struct MockCreate2Mechanism {
    address factory;
    bytes32 salt;
    address beacon;
    ChainDeploy[] networks;
}

address constant MOCK_CREATE2_FACTORY = address(uint160(uint256(keccak256("rain.deploy.mock.create2.factory"))));

bytes32 constant MOCK_CREATE2_SALT = keccak256("rain.deploy.mock.create2.salt");

error MockCreate2NetworkUndeclared(string suite, uint256 chainId);

error MockCreate2NetworkUnfrozen(string suite, string network, address where);

error MockCreate2DerivationMismatch(string suite, address derived, address deployed);

/// @title MockCreate2DeploySuites
/// @notice A test-only mechanism overriding every hook: CREATE2 through `MockCreate2Factory`, its salt in
/// `mechanismData`, falling through to the Zoltu defaults for empty `mechanismData`.
abstract contract MockCreate2DeploySuites is RainDeploySuitesBase {
    event MockCreate2Verification(string[] networks, string suite, address[] deployed);

    ChainDeploy[] internal sMockExtendedNetworks;

    string internal sMockExtendedNetworksRoot;

    function setMockExtendedNetworksRoot(string memory root) external {
        sMockExtendedNetworksRoot = root;
    }

    function extendedNetworksRoot() internal view virtual override returns (string memory) {
        if (bytes(sMockExtendedNetworksRoot).length == 0) {
            return super.extendedNetworksRoot();
        }
        return sMockExtendedNetworksRoot;
    }

    function setMockExtendedNetworks(ChainDeploy[] memory networks) external {
        delete sMockExtendedNetworks;
        for (uint256 i = 0; i < networks.length; i++) {
            sMockExtendedNetworks.push(networks[i]);
        }
    }

    function mockCreate2Address(address factory, bytes32 salt, bytes memory creationCode)
        internal
        pure
        returns (address)
    {
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), factory, salt, keccak256(creationCode)))))
        );
    }

    function mockNetworkSalt(bytes32 salt, bytes memory data) internal pure returns (bytes32) {
        return keccak256(abi.encode(salt, data));
    }

    function mockNetwork(uint256 chainId) internal pure returns (ChainDeploy memory) {
        bytes memory data = abi.encode(chainId);
        return ChainDeploy({
            chainId: chainId,
            data: data,
            deployedAddress: mockCreate2Address(
                MOCK_CREATE2_FACTORY,
                mockNetworkSalt(MOCK_CREATE2_SALT, data),
                type(MockDeployable).creationCode
            )
        });
    }

    function mockSuite(string memory key, address beacon, ChainDeploy[] memory networks)
        internal
        pure
        returns (DeploySuite memory)
    {
        return DeploySuite({
            suite: key,
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: networks.length == 0
                ? mockCreate2Address(MOCK_CREATE2_FACTORY, MOCK_CREATE2_SALT, type(MockDeployable).creationCode)
                : address(0),
            storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
            storedRuntimeCode: type(MockDeployable).runtimeCode,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new DeployDependency[](0),
            mechanismData: abi.encode(
                MockCreate2Mechanism({
                    factory: MOCK_CREATE2_FACTORY, salt: MOCK_CREATE2_SALT, beacon: beacon, networks: networks
                })
            )
        });
    }

    /// The per-network release, recording Arbitrum One and Polygon.
    function mockRelease() internal pure returns (DeploySuite memory) {
        ChainDeploy[] memory networks = new ChainDeploy[](2);
        networks[0] = mockNetwork(42161);
        networks[1] = mockNetwork(137);
        return mockSuite("mock-create2@0_0_1", address(0), networks);
    }

    /// The release's candidate, on Arbitrum One, Polygon and Base.
    function mockCandidate() internal pure returns (DeploySuite memory) {
        ChainDeploy[] memory networks = new ChainDeploy[](3);
        networks[0] = mockNetwork(42161);
        networks[1] = mockNetwork(137);
        networks[2] = mockNetwork(8453);
        return mockSuite("mock-create2", address(0), networks);
    }

    function releasedSuites() internal pure virtual override returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = mockRelease();
        return suites;
    }

    function candidateSuites() internal view virtual override returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({snapshot: mockCandidate(), unanchorableReason: ""});
        return candidates;
    }

    function extendedNetworks(string memory suite) internal view virtual override returns (ChainDeploy[] memory) {
        (suite);
        return sMockExtendedNetworks;
    }

    function decodeMock(DeploySuite memory suite) internal pure returns (MockCreate2Mechanism memory) {
        return abi.decode(suite.mechanismData, (MockCreate2Mechanism));
    }

    function withMock(DeploySuite memory suite, MockCreate2Mechanism memory mechanism)
        internal
        pure
        returns (DeploySuite memory)
    {
        DeploySuite memory copy = abi.decode(abi.encode(suite), (DeploySuite));
        copy.mechanismData = abi.encode(mechanism);
        return copy;
    }

    function mockNetworkIndex(MockCreate2Mechanism memory mechanism, uint256 chainId)
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

    function mockSalt(DeploySuite memory suite, uint256 chainId) internal pure returns (bytes32) {
        MockCreate2Mechanism memory mechanism = decodeMock(suite);
        if (mechanism.networks.length == 0) {
            return mechanism.salt;
        }
        (bool found, uint256 index) = mockNetworkIndex(mechanism, chainId);
        if (!found) {
            revert MockCreate2NetworkUndeclared(suite.suite, chainId);
        }
        return mockNetworkSalt(mechanism.salt, mechanism.networks[index].data);
    }

    function mockCreate2DeployStep(Vm vm, string memory network, address deployer, bytes memory data)
        internal
        returns (address)
    {
        (network);
        (address factory, bytes32 salt, bytes memory creationCode) = abi.decode(data, (address, bytes32, bytes));
        vm.startBroadcast(deployer);
        address deployed = MockCreate2Factory(factory).deploy(salt, creationCode);
        vm.stopBroadcast();
        return deployed;
    }

    function mockDeployAt(Vm vm, DeploySuite memory suite, bytes32 salt, address derived) internal {
        vm.etch(derived, hex"");
        vm.resetNonce(derived);
        address deployed = MockCreate2Factory(decodeMock(suite).factory).deploy(salt, suite.creationCode);
        if (deployed != derived) {
            revert MockCreate2DerivationMismatch(suite.suite, derived, deployed);
        }
    }

    function etchMockFactory(Vm vm, DeploySuite memory suite) internal {
        etchDependencies(vm, suite);
        vm.etch(decodeMock(suite).factory, type(MockCreate2Factory).runtimeCode);
    }

    function deployedAddress(DeploySuite memory suite, uint256 chainId) internal view virtual override returns (address) {
        if (suite.mechanismData.length == 0) {
            return super.deployedAddress(suite, chainId);
        }
        return mockCreate2Address(decodeMock(suite).factory, mockSalt(suite, chainId), suite.creationCode);
    }

    function recordedAddress(DeploySuite memory suite, uint256 chainId) internal view virtual override returns (address) {
        if (suite.mechanismData.length == 0) {
            return super.recordedAddress(suite, chainId);
        }
        MockCreate2Mechanism memory mechanism = decodeMock(suite);
        if (mechanism.networks.length == 0) {
            return suite.storedDeployedAddress;
        }
        (bool found, uint256 index) = mockNetworkIndex(mechanism, chainId);
        if (!found) {
            revert MockCreate2NetworkUndeclared(suite.suite, chainId);
        }
        return mechanism.networks[index].deployedAddress;
    }

    function addressChainIds(DeploySuite memory suite) internal view virtual override returns (uint256[] memory) {
        if (suite.mechanismData.length == 0) {
            return super.addressChainIds(suite);
        }
        MockCreate2Mechanism memory mechanism = decodeMock(suite);
        uint256[] memory chainIds = new uint256[](mechanism.networks.length);
        for (uint256 i = 0; i < chainIds.length; i++) {
            chainIds[i] = mechanism.networks[i].chainId;
        }
        return chainIds;
    }

    function deployStepData(DeploySuite memory suite, uint256 chainId)
        internal
        view
        virtual
        override
        returns (bytes memory)
    {
        if (suite.mechanismData.length == 0) {
            return super.deployStepData(suite, chainId);
        }
        return abi.encode(decodeMock(suite).factory, mockSalt(suite, chainId), suite.creationCode);
    }

    function deployStep(DeploySuite memory suite)
        internal
        view
        virtual
        override
        returns (function(Vm, string memory, address, bytes memory) internal returns (address))
    {
        if (suite.mechanismData.length == 0) {
            return super.deployStep(suite);
        }
        return mockCreate2DeployStep;
    }

    function deployLocally(Vm vm, DeploySuite memory suite) internal virtual override returns (address[] memory) {
        if (suite.mechanismData.length == 0) {
            return super.deployLocally(vm, suite);
        }
        etchMockFactory(vm, suite);
        address[] memory deployed = deployedAddresses(suite);
        uint256[] memory chainIds = addressChainIds(suite);
        for (uint256 i = 0; i < deployed.length; i++) {
            mockDeployAt(vm, suite, mockSalt(suite, chainIds.length == 0 ? 0 : chainIds[i]), deployed[i]);
        }
        return deployed;
    }

    function deployLocallyOnChain(Vm vm, DeploySuite memory suite) internal virtual override {
        if (suite.mechanismData.length == 0 || decodeMock(suite).networks.length == 0) {
            super.deployLocallyOnChain(vm, suite);
            return;
        }
        etchMockFactory(vm, suite);
        mockDeployAt(vm, suite, mockSalt(suite, block.chainid), deployedAddress(suite, block.chainid));
    }

    function withUnrecordedNetworks(DeploySuite memory suite, DeploySuite memory candidate, uint256[] memory chainIds)
        internal
        view
        virtual
        override
        returns (DeploySuite memory)
    {
        if (suite.mechanismData.length == 0) {
            return super.withUnrecordedNetworks(suite, candidate, chainIds);
        }
        MockCreate2Mechanism memory mechanism = decodeMock(suite);
        if (mechanism.networks.length == 0 || candidate.mechanismData.length == 0) {
            return suite;
        }
        MockCreate2Mechanism memory candidateMechanism = decodeMock(candidate);
        ChainDeploy[] memory added = new ChainDeploy[](chainIds.length);
        uint256 count = 0;
        for (uint256 i = 0; i < chainIds.length; i++) {
            (bool recorded,) = mockNetworkIndex(mechanism, chainIds[i]);
            (bool candidateHas, uint256 index) = mockNetworkIndex(candidateMechanism, chainIds[i]);
            if (!recorded && candidateHas) {
                added[count++] = mockDerivedNetwork(suite, candidateMechanism.networks[index]);
            }
        }
        return withMockNetworks(suite, mechanism, added, count);
    }

    function mockDerivedNetwork(DeploySuite memory suite, ChainDeploy memory candidateNetwork)
        internal
        pure
        returns (ChainDeploy memory)
    {
        MockCreate2Mechanism memory mechanism = decodeMock(suite);
        return ChainDeploy({
            chainId: candidateNetwork.chainId,
            data: candidateNetwork.data,
            deployedAddress: mockCreate2Address(
                mechanism.factory, mockNetworkSalt(mechanism.salt, candidateNetwork.data), suite.creationCode
            )
        });
    }

    function withMockNetworks(
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
        return withMock(suite, mechanism);
    }

    function appendExtendedNetworks(DeploySuite memory suite, ChainDeploy[] memory extended)
        internal
        view
        virtual
        override
        returns (DeploySuite memory)
    {
        if (suite.mechanismData.length == 0) {
            return super.appendExtendedNetworks(suite, extended);
        }
        if (extended.length == 0) {
            return suite;
        }
        MockCreate2Mechanism memory mechanism = decodeMock(suite);
        if (mechanism.networks.length == 0) {
            revert ExtendedNetworksUnexpected(suite.suite);
        }
        return withMockNetworks(suite, mechanism, extended, extended.length);
    }

    function checkNetworkFrozen(DeploySuite memory frozen, string memory network, uint256 chainId, address where)
        internal
        view
        virtual
        override
    {
        if (frozen.mechanismData.length == 0) {
            super.checkNetworkFrozen(frozen, network, chainId, where);
            return;
        }
        MockCreate2Mechanism memory mechanism = decodeMock(frozen);
        if (mechanism.networks.length == 0) {
            return;
        }
        (bool found,) = mockNetworkIndex(mechanism, chainId);
        if (!found) {
            revert MockCreate2NetworkUnfrozen(frozen.suite, network, where);
        }
    }

    function suiteBeacon(DeploySuite memory suite, uint256 chainId) internal view virtual override returns (address) {
        if (suite.mechanismData.length == 0) {
            return super.suiteBeacon(suite, chainId);
        }
        return decodeMock(suite).beacon;
    }

    function logVerification(Vm vm, string[] memory networks, DeploySuite memory suite, address[] memory deployed)
        internal
        virtual
        override
    {
        if (suite.mechanismData.length == 0) {
            super.logVerification(vm, networks, suite, deployed);
            return;
        }
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
    ) internal virtual override returns (string memory) {
        if (suite.mechanismData.length == 0) {
            return super.writeSuiteSnapshot(vm, root, dir, contractName, spdxLicenseIdentifier, copyrightText, suite);
        }
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

    function releasedMechanismData(Vm vm, string memory path, string memory prefix)
        internal
        view
        virtual
        override
        returns (string memory)
    {
        if (LibRainDeploySnapshot.recordDeclaresMechanismData(vm, path)) {
            return string.concat(prefix, "_MECHANISM_DATA");
        }
        return super.releasedMechanismData(vm, path, prefix);
    }
}
