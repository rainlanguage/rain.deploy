// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {BeaconProxyBeaconUndeclared, RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ChainDeploy, LibRainDeployExtendedNetworks} from "../../../src/lib/LibRainDeployExtendedNetworks.sol";
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
/// @notice The chain group derives, freezes and reads beacons through a non-Zoltu mechanism handler.
contract RainDeployVerifyChainMockMechanismTest is MockCreate2DeploySuites, RainDeployVerifyChain {
    LocalForkVm internal sForkVm;

    function setUp() external {
        sForkVm = new LocalForkVm();
    }

    function releasedSuites()
        internal
        pure
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (DeploySuite[] memory)
    {
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

    function testChecksARecordedExtendedNetworkAtItsDeclaredAddress() external {
        string memory root = "test/generated-snapshot/mock-create2-verify-chain-extended";
        //forge-lint: disable-next-line(unsafe-cheatcode)
        try vm.removeDir(root, true) {} catch {}
        etchLive(42161);
        etchLive(8453);
        ChainDeploy[] memory extended = new ChainDeploy[](1);
        extended[0] =
            ChainDeploy({chainId: 8453, data: abi.encode(uint256(8453)), deployedAddress: networkAddress(8453)});
        DeploySuite memory release = mockRelease();
        LibRainDeployExtendedNetworks.writeExtendedNetworks(vm, root, release.suite, extended);
        this.setMockExtendedNetworksRoot(root);
        this.setMockExtendedNetworks(extended);
        this.checkOn(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE, release);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(root, true);
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
}
