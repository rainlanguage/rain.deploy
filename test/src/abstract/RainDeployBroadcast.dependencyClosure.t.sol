// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeployDependency, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {TransitiveDependencyDeploy} from "../../concrete/TransitiveDependencyDeploy.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";
import {MockDependencyReader, READ_DEPENDENCY} from "../../concrete/MockDependencyReader.sol";
import {MockDependencyReaderCaller} from "../../concrete/MockDependencyReaderCaller.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {LibBeaconTest} from "../../lib/LibBeaconTest.sol";

contract RainDeployBroadcastDependencyClosureTest is Test {
    TransitiveDependencyDeploy internal sDeploy;

    function setUp() external {
        sDeploy = new TransitiveDependencyDeploy();
    }

    function arbitrum() internal pure returns (string[] memory) {
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        return networks;
    }

    /// The seat check runs a constructor calling a sibling that reads a dependency only it declares, leaving no etch.
    function testSeatCheckEtchesADependencyOfADeclaredDependency() external {
        DeploySuite memory suite = sDeploy.externalDependentSuite();
        address sibling = sDeploy.externalSiblingSuite().storedDeployedAddress;

        sDeploy.externalCheckSeatsNoDeployKey(
            suite, LibRainDeploy.networkChainIds(LibRainDeploy.declaredNetworkConfigs(suite.networks)), vm.addr(1)
        );

        assertEq(sibling.code.length, 0);
        assertEq(READ_DEPENDENCY.code.length, 0);
        assertEq(suite.storedDeployedAddress.code.length, 0);
    }

    /// A fork holding the declared sibling but not the dependency it declares is refused naming that dependency.
    function testBroadcastRefusesAForkMissingADependencyOfADeclaredDependency() external {
        DeploySuite memory suite = sDeploy.externalDependentSuite();
        vm.etch(sDeploy.externalSiblingSuite().storedDeployedAddress, type(MockDependencyReader).runtimeCode);
        LocalForkVm forkVm = new LocalForkVm();

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, READ_DEPENDENCY
            )
        );
        sDeploy.externalDeployAndBroadcast(Vm(address(forkVm)), arbitrum(), 1, suite, suite);
    }

    /// A suite depending on the declared candidate, so its closure reaches the candidate's dependency and the
    /// release's.
    function reachingSuite() internal view returns (DeploySuite memory) {
        DeploySuite memory suite = LibBeaconTest.zoltuSuite(
            "reaching",
            type(MockDeployable).creationCode,
            type(MockDeployable).runtimeCode,
            "test/concrete/MockDeployable.sol:MockDeployable"
        );
        suite.networks = arbitrum();
        suite.dependencies = new DeployDependency[](1);
        suite.dependencies[0] = DeployDependency({
            deployedAddress: sDeploy.externalDependentSuite().storedDeployedAddress,
            runtimeCode: type(MockDependencyReaderCaller).runtimeCode
        });
        return suite;
    }

    function testBroadcastLeavesTheDeclaredSuitesUnchanged() external {
        DeploySuite memory suite = reachingSuite();
        LibRainDeploy.etchZoltuFactory(vm);
        vm.etch(suite.dependencies[0].deployedAddress, type(MockDependencyReaderCaller).runtimeCode);
        vm.etch(sDeploy.externalSiblingSuite().storedDeployedAddress, type(MockDependencyReader).runtimeCode);
        vm.etch(READ_DEPENDENCY, type(MockDeployable).runtimeCode);

        (bytes memory declared, bytes memory broadcast) = sDeploy.externalDeclaredSuitesAroundDeployAndBroadcast(
            Vm(address(new LocalForkVm())), arbitrum(), 1, suite, suite
        );

        assertEq(suite.storedDeployedAddress.code, type(MockDeployable).runtimeCode);
        assertEq(broadcast, declared);
    }

    function testSeatCheckLeavesTheDeclaredSuitesUnchanged() external {
        DeploySuite memory suite = reachingSuite();

        (bytes memory declared, bytes memory checked) = sDeploy.externalDeclaredSuitesAroundCheckSeatsNoDeployKey(
            suite, LibRainDeploy.networkChainIds(LibRainDeploy.declaredNetworkConfigs(suite.networks)), vm.addr(1)
        );

        assertEq(checked, declared);
    }
}
