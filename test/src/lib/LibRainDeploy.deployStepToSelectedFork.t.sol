// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";

/// @title LibRainDeployDeployStepToSelectedForkTest
/// @notice `deployStepToSelectedFork` on the selected fork.
contract LibRainDeployDeployStepToSelectedForkTest is Test {
    enum Step {
        Unreachable,
        Etching,
        EtchingOther,
        Misreporting,
        Codeless
    }

    error DeployStepWasReached();

    address constant TARGET = address(0xabc);
    address constant DEPLOYER = address(0xd3);

    uint256 internal sStepCalls;
    string internal sStepNetwork;
    address internal sStepDeployer;
    bytes internal sStepData;

    function unreachableStep(Vm, string memory, address, bytes memory) internal pure returns (address) {
        revert DeployStepWasReached();
    }

    function etchingStep(Vm, string memory network, address deployer, bytes memory data) internal returns (address) {
        sStepCalls++;
        sStepNetwork = network;
        sStepDeployer = deployer;
        sStepData = data;
        vm.etch(TARGET, hex"00");
        return TARGET;
    }

    function etchingOtherStep(Vm, string memory, address, bytes memory) internal returns (address) {
        vm.etch(TARGET, hex"01");
        return TARGET;
    }

    function misreportingStep(Vm, string memory, address, bytes memory) internal returns (address) {
        vm.etch(TARGET, hex"00");
        return address(0xbad);
    }

    function codelessStep(Vm, string memory, address, bytes memory) internal pure returns (address) {
        return TARGET;
    }

    function externalDeployStepToSelectedFork(Step step, bytes memory data) external {
        LibRainDeploy.deployStepToSelectedFork(
            vm,
            LibRainDeploy.POLYGON,
            DEPLOYER,
            step == Step.Unreachable
                ? unreachableStep
                : step == Step.Etching
                    ? etchingStep
                    : step == Step.EtchingOther ? etchingOtherStep : step == Step.Misreporting ? misreportingStep : codelessStep,
            data,
            TARGET,
            keccak256(hex"00")
        );
    }

    /// A codeless expected address is deployed by the step, run once with the network, deployer and step data.
    function testRunsTheStepOnACodelessAddress(bytes memory data) external {
        this.externalDeployStepToSelectedFork(Step.Etching, data);
        assertEq(sStepCalls, 1);
        assertEq(sStepNetwork, LibRainDeploy.POLYGON);
        assertEq(sStepDeployer, DEPLOYER);
        assertEq(sStepData, data);
        assertEq(TARGET.code, hex"00");
    }

    /// An expected address already holding the expected code is not deployed again.
    function testSkipsTheStepWhereTheCodeIsDeployed() external {
        vm.etch(TARGET, hex"00");
        this.externalDeployStepToSelectedFork(Step.Unreachable, "");
    }

    /// A step reporting another address is refused even when the expected address then holds the expected code.
    function testRefusesAStepReportingAnotherAddress() external {
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.UnexpectedDeployedAddress.selector, TARGET, address(0xbad))
        );
        this.externalDeployStepToSelectedFork(Step.Misreporting, "");
    }

    /// A step reporting the expected address and leaving it codeless is refused naming the network.
    function testRefusesAStepLeavingTheAddressCodeless() external {
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.POLYGON, TARGET)
        );
        this.externalDeployStepToSelectedFork(Step.Codeless, "");
    }

    /// A step deploying other code is refused naming both code hashes.
    function testRefusesAStepDeployingOtherCode() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.CodeHashMismatchOnNetwork.selector,
                LibRainDeploy.POLYGON,
                TARGET,
                keccak256(hex"00"),
                keccak256(hex"01")
            )
        );
        this.externalDeployStepToSelectedFork(Step.EtchingOther, "");
    }

    /// Other code already at the expected address is refused without running the step.
    function testRefusesOtherCodeAlreadyDeployed() external {
        vm.etch(TARGET, hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.CodeHashMismatchOnNetwork.selector,
                LibRainDeploy.POLYGON,
                TARGET,
                keccak256(hex"00"),
                keccak256(hex"01")
            )
        );
        this.externalDeployStepToSelectedFork(Step.Unreachable, "");
    }
}
