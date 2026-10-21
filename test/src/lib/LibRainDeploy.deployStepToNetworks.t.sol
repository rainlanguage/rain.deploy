// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeployDependency, LibRainDeploy, NetworkDeploys, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";

/// @title LibRainDeployDeployStepToNetworksTest
/// @notice The shared per-network loop's guards, on local forks.
contract LibRainDeployDeployStepToNetworksTest is Test {
    /// The step `externalLoop` hands the loop.
    enum Step {
        Unreachable,
        Misreporting,
        Etching
    }

    /// Thrown when a step the loop must not reach is reached.
    error DeployStepWasReached();

    /// The local fork Vm the loop forks with.
    LocalForkVm internal sForkVm;

    /// Deploys the local fork Vm.
    function setUp() external {
        sForkVm = new LocalForkVm();
    }

    /// A step that reverts if reached.
    /// @return Never returns.
    function unreachableDeployStep(Vm, string memory, address, bytes memory) internal pure returns (address) {
        revert DeployStepWasReached();
    }

    /// Etches code at the step data's address and reports `address(0xbad)`.
    /// @param stepData The address to etch, encoded.
    /// @return `address(0xbad)`.
    function misreportingDeployStep(Vm, string memory, address, bytes memory stepData) internal returns (address) {
        vm.etch(abi.decode(stepData, (address)), hex"00");
        return address(0xbad);
    }

    /// Etches code at the step data's address and reports it.
    /// @param stepData The address to etch, encoded.
    /// @return The etched address.
    function etchingDeployStep(Vm, string memory, address, bytes memory stepData) internal returns (address) {
        address target = abi.decode(stepData, (address));
        vm.etch(target, hex"00");
        return target;
    }

    /// Arbitrum One, then Polygon when `length` is 2.
    /// @param length How many networks.
    /// @return Their catalogue entries.
    function networks(uint256 length) internal pure returns (SupportedNetwork[] memory) {
        string[] memory names = new string[](length);
        names[0] = LibRainDeploy.ARBITRUM_ONE;
        if (length > 1) {
            names[1] = LibRainDeploy.POLYGON;
        }
        return LibRainDeploy.declaredNetworkConfigs(names);
    }

    /// External wrapper for `LibRainDeploy.deployStepToNetworks` over the local fork Vm.
    /// @param step The step the loop runs.
    /// @param deploys The expected addresses and their deploy data.
    /// @param dependencies The declared dependencies.
    /// @return The fork of each network.
    function externalLoop(Step step, NetworkDeploys memory deploys, DeployDependency[] memory dependencies)
        external
        returns (uint256[] memory)
    {
        return LibRainDeploy.deployStepToNetworks(
            Vm(address(sForkVm)),
            networks(deploys.expectedAddresses.length),
            address(this),
            step == Step.Unreachable
                ? unreachableDeployStep
                : step == Step.Misreporting ? misreportingDeployStep : etchingDeployStep,
            deploys,
            keccak256(hex"00"),
            dependencies
        );
    }

    /// A missing declared dependency MUST be refused on a network whose target is already deployed.
    function testLoopRefusesMissingDependencyOnDeployedTarget() external {
        address target = address(0xabc);
        vm.etch(target, hex"00");
        DeployDependency[] memory dependencies = new DeployDependency[](1);
        dependencies[0] = DeployDependency(address(0xdef), hex"00");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, address(0xdef))
        );
        this.externalLoop(
            Step.Unreachable, LibRainDeploy.everyNetwork(1, abi.encode(target), target, target), dependencies
        );
    }

    /// A step that reports an address other than the expected one MUST be refused, even when the expected address then holds the expected code.
    function testLoopRefusesStepReportingAnotherAddress() external {
        address target = address(0xabc);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.UnexpectedDeployedAddress.selector, target, address(0xbad))
        );
        this.externalLoop(
            Step.Misreporting,
            LibRainDeploy.everyNetwork(1, abi.encode(target), target, target),
            new DeployDependency[](0)
        );
    }

    /// A fork reporting another chain than its catalogue entry MUST be refused, even when the target is already deployed.
    function testLoopRefusesForkReportingAnotherChain() external {
        SupportedNetwork memory network = networks(1)[0];
        sForkVm.setReportedChainId(network.chainId + 1);
        address target = address(0xabc);
        vm.etch(target, hex"00");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NetworkChainIdMismatch.selector, network.name, network.chainId, network.chainId + 1
            )
        );
        this.externalLoop(
            Step.Unreachable,
            LibRainDeploy.everyNetwork(1, abi.encode(target), target, target),
            new DeployDependency[](0)
        );
    }

    /// Each network MUST be deployed at its own expected address, so an occupied first address cannot hide a missing second.
    function testLoopDeploysEachNetworksOwnExpectedAddress() external {
        address first = address(0xabc);
        address second = address(0xdef);
        vm.etch(first, hex"00");
        NetworkDeploys memory deploys = LibRainDeploy.everyNetwork(2, abi.encode(first), first, first);
        deploys.deployStepData[1] = abi.encode(second);
        deploys.expectedAddresses[1] = second;
        deploys.derivedAddresses[1] = second;
        this.externalLoop(Step.Etching, deploys, new DeployDependency[](0));
        assertEq(second.code, hex"00");
    }

    /// An expected address already holding other code MUST be refused, naming the network and both code hashes.
    function testLoopRefusesTargetHoldingOtherCode() external {
        address target = address(0xabc);
        vm.etch(target, hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.CodeHashMismatchOnNetwork.selector,
                LibRainDeploy.ARBITRUM_ONE,
                target,
                keccak256(hex"00"),
                keccak256(hex"01")
            )
        );
        this.externalLoop(
            Step.Unreachable,
            LibRainDeploy.everyNetwork(1, abi.encode(target), target, target),
            new DeployDependency[](0)
        );
    }
}
