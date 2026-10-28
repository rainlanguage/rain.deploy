// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {
    DeploySuite,
    ExtendedNetworksUnexpected,
    UnexpectedMechanismData
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {DeployDependency, LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ChainDeploy} from "../../../src/lib/LibRainDeployExtendedNetworks.sol";
import {ExampleDeploy} from "../../concrete/ExampleDeploy.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";

/// @title RainDeploySuitesBaseZoltuMechanismTest
/// @notice The Zoltu defaults of the mechanism hooks on `RainDeploySuitesBase`.
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

    /// A Zoltu suite has no mechanism data.
    function testZoltuSuiteCarryingMechanismDataIsRefused() external {
        DeploySuite memory suite = zoltuMockDeployableSuite("zoltu-with-data");
        assertEq(sDeploy.externalDeployedAddresses(suite)[0], suite.storedDeployedAddress);

        suite.mechanismData = hex"00";
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;

        vm.expectRevert(abi.encodeWithSelector(UnexpectedMechanismData.selector, suite.suite));
        sDeploy.externalDeployedAddresses(suite);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMechanismData.selector, suite.suite));
        sDeploy.externalDeployLocally(vm, suite);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMechanismData.selector, suite.suite));
        sDeploy.externalDeployAndBroadcast(vm, networks, 1, suite, suite);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMechanismData.selector, suite.suite));
        sDeploy.externalDeployStepData(suite, 42161);
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
