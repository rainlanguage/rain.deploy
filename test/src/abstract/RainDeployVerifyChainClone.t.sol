// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ExampleCloneDeploys} from "../../abstract/ExampleCloneDeploys.sol";

/// @title RainDeployVerifyChainCloneTest
/// @notice The chain matrix over a clone deploy repo's frozen release.
contract RainDeployVerifyChainCloneTest is ExampleCloneDeploys, RainDeployVerifyChain {
    /// Puts the release's dependencies, and its clone at its address, on every fork.
    function setUp() external {
        DeploySuite memory release = releasedSuites()[0];
        for (uint256 i = 0; i < release.dependencies.length; i++) {
            vm.etch(release.dependencies[i].deployedAddress, release.dependencies[i].runtimeCode);
            vm.makePersistent(release.dependencies[i].deployedAddress);
        }
        vm.etch(release.storedDeployedAddress, release.storedRuntimeCode);
        vm.makePersistent(release.storedDeployedAddress);
    }

    /// Without the clone at its address the matrix refuses on the first network, naming the release
    /// and the CLONE address — not the Zoltu address of its creation code, and not a candidate's.
    function testCloneReleaseMissingFromANetworkIsRefusedAtTheCloneAddress() external {
        DeploySuite memory release = releasedSuites()[0];
        assertNotEq(release.storedDeployedAddress, LibRainDeploy.zoltuAddress(release.creationCode));
        vm.etch(release.storedDeployedAddress, hex"");

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NotDeployedOnNetwork.selector, supportedNetworks()[0], release.storedDeployedAddress
            )
        );
        this.testSuitesLiveOnEverySupportedNetwork();
    }
}
