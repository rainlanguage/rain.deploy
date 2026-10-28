// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {
    DeployDeclaration,
    DeploySuite,
    MechanismUnclaimed,
    UnexpectedMechanismData
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {DeployDependency, LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployZoltuMechanism, ZOLTU_MECHANISM_ID} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
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

    /// `MockDeployable` as a Zoltu suite on two networks.
    /// @param suite The suite key.
    /// @return The suite.
    function zoltuMockDeployableSuite(string memory suite) internal pure returns (DeploySuite memory) {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.BASE;
        return DeploySuite({
            networks: networks,
            suite: suite,
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode),
            storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
            storedRuntimeCode: type(MockDeployable).runtimeCode,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new DeployDependency[](0),
            mechanismData: LibRainDeployZoltuMechanism.mechanismData()
        });
    }

    function zoltuDeployedAddress(DeploySuite memory suite) external pure returns (address) {
        DeployDeclaration memory d;
        return LibRainDeployZoltuMechanism.deployedAddress(d, suite, 0);
    }

    function zoltuDeployStepData(DeploySuite memory suite) external pure returns (bytes memory) {
        DeployDeclaration memory d;
        return LibRainDeployZoltuMechanism.deployStepData(d, suite, 0);
    }

    /// Mechanism data shorter than an id is claimed by no mechanism.
    function testMechanismDataShorterThanAnIdIsUnclaimed() external {
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
    }

    /// The Zoltu id followed by any payload dispatches to Zoltu, which refuses it.
    /// @param payload The trailing payload.
    function testZoltuIdCarryingAPayloadIsRefused(bytes memory payload) external {
        vm.assume(payload.length > 0);
        DeploySuite memory suite = zoltuMockDeployableSuite("zoltu-with-data");
        suite.mechanismData = bytes.concat(abi.encode(ZOLTU_MECHANISM_ID), payload);
        assertEq(sDeploy.externalMechanismOf(suite), ZOLTU_MECHANISM_ID);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMechanismData.selector, suite.suite));
        sDeploy.externalDeployedAddresses(suite);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedMechanismData.selector, suite.suite));
        sDeploy.externalRecordedAddresses(suite);
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

    /// Zoltu answers one address for every network the suite lists, derived, recorded or deployed locally.
    function testZoltuAnswersOneAddressOnEveryListedNetwork() external {
        DeploySuite memory zoltu = zoltuMockDeployableSuite("zoltu");
        address[] memory deployed = sDeploy.externalDeployedAddresses(zoltu);
        address[] memory recorded = sDeploy.externalRecordedAddresses(zoltu);
        address[] memory local = sDeploy.externalDeployLocally(vm, zoltu);
        assertEq(deployed.length, 2);
        assertEq(recorded.length, 2);
        assertEq(local.length, 2);
        for (uint256 i = 0; i < 2; i++) {
            assertEq(deployed[i], LibRainDeploy.zoltuAddress(zoltu.creationCode));
            assertEq(recorded[i], zoltu.storedDeployedAddress);
            assertEq(local[i], deployed[i]);
        }
        assertEq(local[0].code, zoltu.storedRuntimeCode);
    }
}
