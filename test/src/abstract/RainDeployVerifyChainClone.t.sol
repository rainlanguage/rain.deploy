// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {NotDeployedOnNetwork, RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ExampleCloneDeploys} from "../../abstract/ExampleCloneDeploys.sol";

/// @title RainDeployVerifyChainCloneTest
/// @notice The chain matrix over a clone deploy repo's frozen release.
///
/// The released clone's runtime code is etched at the CLONE's address and made
/// persistent, so it is present on every fork, and the inherited
/// `testSuitesLiveOnEverySupportedNetwork` passes only if the matrix looks for
/// the release there. A matrix that derived the release as Zoltu would look at
/// the Zoltu address of the proxy's creation code, which is empty on every
/// network, and fail.
contract RainDeployVerifyChainCloneTest is ExampleCloneDeploys, RainDeployVerifyChain {
    /// Puts the release's dependencies, and its clone at its address, on every
    /// fork.
    function setUp() external {
        DeploySuite memory release = releasedSuites()[0];
        for (uint256 i = 0; i < release.dependencies.length; i++) {
            vm.etch(release.dependencies[i].deployedAddress, release.dependencies[i].runtimeCode);
            vm.makePersistent(release.dependencies[i].deployedAddress);
        }
        vm.etch(release.storedDeployedAddress, release.storedRuntimeCode);
        vm.makePersistent(release.storedDeployedAddress);
    }

    /// Without the clone at its address the matrix refuses on the first
    /// network, naming the release and the CLONE address — not the Zoltu
    /// address of its creation code, and not a candidate's.
    function testCloneReleaseMissingFromANetworkIsRefusedAtTheCloneAddress() external {
        DeploySuite memory release = releasedSuites()[0];
        assertNotEq(release.storedDeployedAddress, LibRainDeploy.zoltuAddress(release.creationCode));
        vm.etch(release.storedDeployedAddress, hex"");

        vm.expectRevert(
            abi.encodeWithSelector(
                NotDeployedOnNetwork.selector, supportedNetworks()[0], release.suite, release.storedDeployedAddress
            )
        );
        this.testSuitesLiveOnEverySupportedNetwork();
    }
}
