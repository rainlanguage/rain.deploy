// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeployDependency, LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";

/// @title LibRainDeploySelectCheckedForkTest
/// @notice `selectCheckedFork` on local forks.
contract LibRainDeploySelectCheckedForkTest is Test {
    LocalForkVm internal sForkVm;

    function setUp() external {
        sForkVm = new LocalForkVm();
    }

    function externalSelectCheckedFork(
        SupportedNetwork memory network,
        uint256 forkId,
        DeployDependency[] memory dependencies
    ) external {
        LibRainDeploy.selectCheckedFork(Vm(address(sForkVm)), network, forkId, dependencies);
    }

    function catalogued(string memory name) internal pure returns (SupportedNetwork memory) {
        string[] memory names = new string[](1);
        names[0] = name;
        return LibRainDeploy.declaredNetworkConfigs(names)[0];
    }

    function dependencies(address first, address second) internal pure returns (DeployDependency[] memory) {
        DeployDependency[] memory declared = new DeployDependency[](2);
        declared[0] = DeployDependency({deployedAddress: first, runtimeCode: hex"00"});
        declared[1] = DeployDependency({deployedAddress: second, runtimeCode: hex"01"});
        return declared;
    }

    /// The fork is selected before its chain id is checked, and stays selected.
    function testSelectsTheForkThenChecksItsChainId() external {
        assertTrue(block.chainid != 137);
        vm.expectCall(address(sForkVm), abi.encodeCall(LocalForkVm.selectFork, (137)), 1);
        this.externalSelectCheckedFork(catalogued(LibRainDeploy.POLYGON), 137, new DeployDependency[](0));
        assertEq(block.chainid, 137);
    }

    /// A fork reporting another chain than the network's is refused naming both.
    function testRefusesAForkOfAnotherChain() external {
        sForkVm.setReportedChainId(1);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NetworkChainIdMismatch.selector, LibRainDeploy.ARBITRUM_ONE, 42161, 1)
        );
        this.externalSelectCheckedFork(catalogued(LibRainDeploy.ARBITRUM_ONE), 42161, new DeployDependency[](0));
    }

    /// The chain id is checked before the dependencies.
    function testChecksTheChainIdBeforeTheDependencies() external {
        sForkVm.setReportedChainId(1);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NetworkChainIdMismatch.selector, LibRainDeploy.ARBITRUM_ONE, 42161, 1)
        );
        this.externalSelectCheckedFork(
            catalogued(LibRainDeploy.ARBITRUM_ONE), 42161, dependencies(address(0xabc), address(0xdef))
        );
    }

    /// Every declared dependency is checked: one without code is refused naming the network and it.
    function testRefusesAMissingDependency() external {
        vm.etch(address(0xabc), hex"00");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.MissingDependency.selector, LibRainDeploy.POLYGON, address(0xdef))
        );
        this.externalSelectCheckedFork(
            catalogued(LibRainDeploy.POLYGON), 137, dependencies(address(0xabc), address(0xdef))
        );
    }

    /// A declared dependency holding other code is refused naming both code hashes.
    function testRefusesAChangedDependency() external {
        vm.etch(address(0xabc), hex"02");
        vm.etch(address(0xdef), hex"01");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.DependencyChanged.selector,
                LibRainDeploy.POLYGON,
                address(0xabc),
                keccak256(hex"00"),
                keccak256(hex"02")
            )
        );
        this.externalSelectCheckedFork(
            catalogued(LibRainDeploy.POLYGON), 137, dependencies(address(0xabc), address(0xdef))
        );
    }

    /// The network's own fork with every declared dependency in place passes.
    function testAcceptsTheNetworksForkWithItsDependencies() external {
        vm.etch(address(0xabc), hex"00");
        vm.etch(address(0xdef), hex"01");
        this.externalSelectCheckedFork(
            catalogued(LibRainDeploy.POLYGON), 137, dependencies(address(0xabc), address(0xdef))
        );
        assertEq(block.chainid, 137);
    }
}
