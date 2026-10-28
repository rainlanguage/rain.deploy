// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DerivedDeploy, NoDerivedDeployment, RainDeployVerifyBase} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {DeployDeclaration, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {MockCreate2DeploySuites} from "../../abstract/MockCreate2DeploySuites.sol";
import {LibMockCreate2Mechanism} from "../../lib/LibMockCreate2Mechanism.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";

/// @title RainDeployVerifyBaseMockMechanismTest
/// @notice The derivation's code hash through a per-network mechanism that leaves a network with nothing recorded at
/// `address(0)`.
contract RainDeployVerifyBaseMockMechanismTest is MockCreate2DeploySuites, RainDeployVerifyBase {
    function declaration() internal view override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibMockCreate2Mechanism.extend(d);
        addMockCreate2(d);
        return d;
    }

    function externalDeriveDeployment(DeploySuite memory suite) external returns (DerivedDeploy memory) {
        return deriveDeployment(declaration(), suite);
    }

    /// The release, with `networks` its suite's networks in that order.
    function releaseOn(string[] memory networks) internal view returns (DeploySuite memory) {
        DeploySuite memory release = mockRelease();
        release.networks = networks;
        return release;
    }

    /// A network ahead of the recorded ones leaves slot 0 at `address(0)`, and the hash still comes from the code
    /// the mechanism deployed.
    function testCodeHashSkipsAnUnrecordedFirstNetwork() external {
        string[] memory networks = new string[](3);
        networks[0] = LibRainDeploy.BASE;
        networks[1] = LibRainDeploy.ARBITRUM_ONE;
        networks[2] = LibRainDeploy.POLYGON;

        DerivedDeploy memory derived = this.externalDeriveDeployment(releaseOn(networks));

        assertEq(derived.deployedAddresses.length, 3);
        assertEq(derived.deployedAddresses[0], address(0));
        assertEq(derived.deployedAddresses[1], mockNetwork(42161).deployedAddress);
        assertEq(derived.deployedAddresses[2], mockNetwork(137).deployedAddress);
        assertEq(derived.bytecodeHash, keccak256(type(MockDeployable).runtimeCode));
    }

    /// An unrecorded network between recorded ones changes nothing about the hash.
    function testCodeHashSkipsAnUnrecordedMiddleNetwork() external {
        string[] memory networks = new string[](3);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.BASE;
        networks[2] = LibRainDeploy.POLYGON;

        DerivedDeploy memory derived = this.externalDeriveDeployment(releaseOn(networks));

        assertEq(derived.deployedAddresses[0], mockNetwork(42161).deployedAddress);
        assertEq(derived.deployedAddresses[1], address(0));
        assertEq(derived.deployedAddresses[2], mockNetwork(137).deployedAddress);
        assertEq(derived.bytecodeHash, keccak256(type(MockDeployable).runtimeCode));
    }

    /// Every network unrecorded leaves no code to hash, and the derivation refuses rather than hashing `address(0)`.
    function testRefusesWhenNoNetworkIsRecorded() external {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.BASE;
        networks[1] = LibRainDeploy.ETHEREUM;
        DeploySuite memory release = releaseOn(networks);

        vm.expectRevert(abi.encodeWithSelector(NoDerivedDeployment.selector, release.suite));
        this.externalDeriveDeployment(release);
    }

    /// No networks at all is the same refusal, not an out-of-bounds panic.
    function testRefusesASuiteOnNoNetworks() external {
        DeploySuite memory release = releaseOn(new string[](0));

        vm.expectRevert(abi.encodeWithSelector(NoDerivedDeployment.selector, release.suite));
        this.externalDeriveDeployment(release);
    }
}
