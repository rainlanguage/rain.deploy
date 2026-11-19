// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {TRANSITIVE_DEPENDENCY} from "../../abstract/TransitiveDependencyDeploySuites.sol";
import {TransitiveDependencyDeploy} from "../../concrete/TransitiveDependencyDeploy.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";

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

    /// The seat check runs a constructor reading a dependency only its declared sibling declares, leaving no etch.
    function testSeatCheckEtchesADependencyOfADeclaredDependency() external {
        DeploySuite memory suite = sDeploy.externalDependentSuite();
        address sibling = sDeploy.externalSiblingSuite().storedDeployedAddress;

        sDeploy.externalCheckSeatsNoDeployKey(
            suite, LibRainDeploy.networkChainIds(LibRainDeploy.declaredNetworkConfigs(suite.networks)), vm.addr(1)
        );

        assertEq(sibling.code.length, 0);
        assertEq(TRANSITIVE_DEPENDENCY.code.length, 0);
        assertEq(suite.storedDeployedAddress.code.length, 0);
    }

    /// A fork holding the declared sibling but not the dependency it declares is refused naming that dependency.
    function testBroadcastRefusesAForkMissingADependencyOfADeclaredDependency() external {
        DeploySuite memory suite = sDeploy.externalDependentSuite();
        vm.etch(sDeploy.externalSiblingSuite().storedDeployedAddress, type(MockDeployable).runtimeCode);
        LocalForkVm forkVm = new LocalForkVm();

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, TRANSITIVE_DEPENDENCY
            )
        );
        sDeploy.externalDeployAndBroadcast(Vm(address(forkVm)), arbitrum(), 1, suite, suite);
    }
}
