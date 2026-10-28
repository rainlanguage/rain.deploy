// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {BeaconProxyBeaconUndeclared, RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ChainDeploy} from "../../../src/lib/LibRainDeployExtendedNetworks.sol";
import {
    MOCK_CREATE2_FACTORY,
    MOCK_CREATE2_SALT,
    MockCreate2DeploySuites,
    MockCreate2Mechanism,
    MockCreate2NetworkUnfrozen
} from "../../abstract/MockCreate2DeploySuites.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";

/// @title RainDeployVerifyChainMockMechanismTest
/// @notice The chain group derives, freezes and reads beacons through an overriding mechanism's hooks.
contract RainDeployVerifyChainMockMechanismTest is MockCreate2DeploySuites, RainDeployVerifyChain {
    LocalForkVm internal sForkVm;

    function setUp() external {
        sForkVm = new LocalForkVm();
    }

    function releasedSuites() internal pure override(RainDeploySuitesBase, MockCreate2DeploySuites) returns (DeploySuite[] memory) {
        return new DeploySuite[](0);
    }

    function supportedNetworks() internal pure override returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        return networks;
    }

    function networkAddress(uint256 chainId) internal pure returns (address) {
        bytes32 salt = keccak256(abi.encode(MOCK_CREATE2_SALT, abi.encode(chainId)));
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), MOCK_CREATE2_FACTORY, salt, keccak256(type(MockDeployable).creationCode)
                        )
                    )
                )
            )
        );
    }

    function etchLive(uint256 chainId) internal {
        vm.etch(networkAddress(chainId), type(MockDeployable).runtimeCode);
        vm.makePersistent(networkAddress(chainId));
    }

    function checkOn(string memory a, string memory b, DeploySuite memory suite) external {
        string[] memory names = new string[](2);
        names[0] = a;
        names[1] = b;
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = suite;
        checkDeployedOnNetworks(Vm(address(sForkVm)), LibRainDeploy.declaredNetworkConfigs(names), suites);
    }

    function testChecksEachNetworkAtItsOwnAddress() external {
        etchLive(42161);
        etchLive(137);
        this.checkOn(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON, mockRelease());
    }

    function testRefusesANetworkWhoseOwnAddressIsEmpty() external {
        etchLive(42161);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.POLYGON, networkAddress(137)
            )
        );
        this.checkOn(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON, mockRelease());
    }

    /// A network the candidate adds but the release does not record is refused as unfrozen, whether or not its
    /// address is live.
    function testRefusesAnUnrecordedCandidateNetworkAsUnfrozen() external {
        etchLive(42161);
        etchLive(8453);
        DeploySuite memory release = mockRelease();
        vm.expectRevert(
            abi.encodeWithSelector(
                MockCreate2NetworkUnfrozen.selector, release.suite, LibRainDeploy.BASE, networkAddress(8453)
            )
        );
        this.checkOn(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE, release);
    }

    function testRefusesAnUndeclaredBeacon() external {
        etchLive(42161);
        etchLive(137);
        DeploySuite memory release = mockRelease();
        MockCreate2Mechanism memory mechanism = abi.decode(release.mechanismData, (MockCreate2Mechanism));
        mechanism.beacon = address(0xbeac);
        release.mechanismData = abi.encode(mechanism);
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconProxyBeaconUndeclared.selector, release.suite, LibRainDeploy.ARBITRUM_ONE, address(0xbeac)
            )
        );
        this.checkOn(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON, release);
    }

    function testChecksAnExtendedNetworkAtItsDeclaredAddress() external {
        etchLive(42161);
        etchLive(8453);
        ChainDeploy[] memory extended = new ChainDeploy[](1);
        extended[0] =
            ChainDeploy({chainId: 8453, data: abi.encode(uint256(8453)), deployedAddress: networkAddress(8453)});
        this.checkOn(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE, appendExtendedNetworks(mockRelease(), extended));
    }

    function extendedNetworksRoot()
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (string memory)
    {
        return super.extendedNetworksRoot();
    }

    function extendedNetworks(string memory suite)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (ChainDeploy[] memory)
    {
        return super.extendedNetworks(suite);
    }

    function deployedAddress(DeploySuite memory suite, uint256 chainId)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (address)
    {
        return super.deployedAddress(suite, chainId);
    }

    function recordedAddress(DeploySuite memory suite, uint256 chainId)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (address)
    {
        return super.recordedAddress(suite, chainId);
    }

    function addressChainIds(DeploySuite memory suite)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (uint256[] memory)
    {
        return super.addressChainIds(suite);
    }

    function deployStepData(DeploySuite memory suite, uint256 chainId)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (bytes memory)
    {
        return super.deployStepData(suite, chainId);
    }

    function deployStep(DeploySuite memory suite)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (function(Vm, string memory, address, bytes memory) internal returns (address))
    {
        return super.deployStep(suite);
    }

    function deployLocally(Vm localVm, DeploySuite memory suite)
        internal
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (address[] memory)
    {
        return super.deployLocally(localVm, suite);
    }

    function deployLocallyOnChain(Vm localVm, DeploySuite memory suite)
        internal
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
    {
        super.deployLocallyOnChain(localVm, suite);
    }

    function withUnrecordedNetworks(DeploySuite memory suite, DeploySuite memory candidate, uint256[] memory chainIds)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (DeploySuite memory)
    {
        return super.withUnrecordedNetworks(suite, candidate, chainIds);
    }

    function appendExtendedNetworks(DeploySuite memory suite, ChainDeploy[] memory extended)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (DeploySuite memory)
    {
        return super.appendExtendedNetworks(suite, extended);
    }

    function checkNetworkFrozen(DeploySuite memory frozen, string memory network, uint256 chainId, address where)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
    {
        super.checkNetworkFrozen(frozen, network, chainId, where);
    }

    function suiteBeacon(DeploySuite memory suite, uint256 chainId)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (address)
    {
        return super.suiteBeacon(suite, chainId);
    }

    function logVerification(Vm logVm, string[] memory networks, DeploySuite memory suite, address[] memory deployed)
        internal
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
    {
        super.logVerification(logVm, networks, suite, deployed);
    }

    function writeSuiteSnapshot(
        Vm fileVm,
        string memory root,
        string memory dir,
        string memory contractName,
        string memory spdxLicenseIdentifier,
        string memory copyrightText,
        DeploySuite memory suite
    ) internal override(RainDeploySuitesBase, MockCreate2DeploySuites) returns (string memory) {
        return super.writeSuiteSnapshot(fileVm, root, dir, contractName, spdxLicenseIdentifier, copyrightText, suite);
    }

    function releasedMechanismData(Vm fileVm, string memory path, string memory prefix)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (string memory)
    {
        return super.releasedMechanismData(fileVm, path, prefix);
    }
}
