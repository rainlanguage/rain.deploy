// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {
    DeploySuite,
    ExtendedNetworksUnexpected,
    MechanismUnclaimed,
    UnexpectedMechanismData
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {DeployDependency, LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ChainDeploy} from "../../../src/lib/LibRainDeployExtendedNetworks.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {ExampleDeploy} from "../../concrete/ExampleDeploy.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";

/// @title RainDeploySuitesBaseZoltuMechanismTest
/// @notice `LibRainDeployZoltuMechanism` through a Zoltu-only declaration.
contract RainDeploySuitesBaseZoltuMechanismTest is Test {
    ExampleDeploy internal sDeploy;

    function setUp() external {
        sDeploy = new ExampleDeploy();
    }

    /// `MockDeployable` as a Zoltu suite.
    /// @param suite The suite key.
    /// @return The suite.
    function zoltuMockDeployableSuite(string memory suite) internal pure returns (DeploySuite memory) {
        return DeploySuite({
            networks: new string[](0),
            suite: suite,
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode),
            storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
            storedRuntimeCode: type(MockDeployable).runtimeCode,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new DeployDependency[](0),
            mechanismData: ""
        });
    }

    function zoltuDeployedAddress(DeploySuite memory suite) external pure returns (address) {
        return LibRainDeployZoltuMechanism.deployedAddress(suite, 0);
    }

    function zoltuDeployStepData(DeploySuite memory suite) external pure returns (bytes memory) {
        return LibRainDeployZoltuMechanism.deployStepData(suite, 0);
    }

    /// A Zoltu-only declaration claims no suite carrying mechanism data, and the Zoltu mechanism refuses one.
    function testZoltuSuiteCarryingMechanismDataIsRefused() external {
        DeploySuite memory suite = zoltuMockDeployableSuite("zoltu-with-data");
        assertEq(sDeploy.externalDeployedAddresses(suite)[0], suite.storedDeployedAddress);

        suite.mechanismData = hex"00";
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;

        vm.expectRevert(abi.encodeWithSelector(MechanismUnclaimed.selector, suite.suite));
        sDeploy.externalDeployedAddresses(suite);
        vm.expectRevert(abi.encodeWithSelector(MechanismUnclaimed.selector, suite.suite));
        sDeploy.externalDeployLocally(vm, suite);
        vm.expectRevert(abi.encodeWithSelector(MechanismUnclaimed.selector, suite.suite));
        sDeploy.externalDeployAndBroadcast(vm, networks, 1, suite, suite);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMechanismData.selector, suite.suite));
        this.zoltuDeployedAddress(suite);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMechanismData.selector, suite.suite));
        this.zoltuDeployStepData(suite);
    }

    /// The Zoltu step deploys its suite to the suite's derived address.
    function testDeployStepDeploysToTheDerivedAddress() external {
        DeploySuite memory zoltu = zoltuMockDeployableSuite("zoltu");
        LibRainDeploy.etchZoltuFactory(vm);
        address deployed = sDeploy.externalRunDeployStep(
            Vm(address(new LocalForkVm())),
            zoltu,
            LibRainDeploy.ARBITRUM_ONE,
            address(this),
            sDeploy.externalDeployStepData(zoltu, 42161)
        );
        assertEq(deployed, zoltu.storedDeployedAddress);
        assertEq(deployed.code, zoltu.storedRuntimeCode);
    }

    /// A suite at one address on every network has no per-address chain ids.
    function testAddressChainIdsIsEmptyForAOneAddressSuite() external view {
        assertEq(sDeploy.externalAddressChainIds(zoltuMockDeployableSuite("zoltu")).length, 0);
    }

    /// Extended networks on a Zoltu suite are refused.
    function testExtendedNetworksOnAZoltuSuiteAreRefused() external {
        ChainDeploy[] memory extended = new ChainDeploy[](1);
        extended[0] = ChainDeploy({chainId: 137, data: hex"deadbeef", deployedAddress: address(1)});
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnexpected.selector, "zoltu"));
        sDeploy.externalAppendExtendedNetworks(zoltuMockDeployableSuite("zoltu"), extended);
    }
}
