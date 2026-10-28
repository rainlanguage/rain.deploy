// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism, ZOLTU_MECHANISM_ID} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {
    LibMockCreate2Mechanism,
    MOCK_CREATE2_FACTORY,
    MOCK_CREATE2_MECHANISM_ID,
    MOCK_CREATE2_SALT
} from "../../lib/LibMockCreate2Mechanism.sol";
import {LibMockSaltMechanism, MOCK_SALT_MECHANISM_ID} from "../../lib/LibMockSaltMechanism.sol";
import {LibBeaconTest} from "../../lib/LibBeaconTest.sol";
import {TwoMechanismDeploySuites, TWO_MECHANISM_SALT} from "../../abstract/TwoMechanismDeploySuites.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";

/// @title RainDeploySuitesBaseExtendChainTest
/// @notice A declaration composed as a consumer writes one: core, Zoltu, two mechanism layers, the consumer's own
/// networks, then its suites.
contract RainDeploySuitesBaseExtendChainTest is Test, TwoMechanismDeploySuites {
    function consumerNetworks() internal pure returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.BASE;
        return networks;
    }

    function zoltuSuite() internal pure returns (DeploySuite memory) {
        return LibBeaconTest.zoltuSuite(
            "mock-deployable@0_0_1",
            type(MockDeployable).creationCode,
            type(MockDeployable).runtimeCode,
            "test/concrete/MockDeployable.sol:MockDeployable"
        );
    }

    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        LibMockCreate2Mechanism.extend(d);
        LibMockSaltMechanism.extend(d);
        d.networks = consumerNetworks();
        DeploySuite[] memory released = new DeploySuite[](1);
        released[0] = zoltuSuite();
        LibRainDeployDeclaration.addReleased(d, released);
        addTwoMechanismCandidates(d);
        return d;
    }

    function testEveryLayersMechanismIsDeclaredInExtendOrder() external pure {
        DeployDeclaration memory d = declaration();
        assertEq(d.mechanisms.length, 3);
        assertEq(d.mechanisms[0].id, ZOLTU_MECHANISM_ID);
        assertEq(d.mechanisms[1].id, MOCK_CREATE2_MECHANISM_ID);
        assertEq(d.mechanisms[2].id, MOCK_SALT_MECHANISM_ID);
    }

    function testTheConsumersNetworksReplaceCoresDefault() external pure {
        DeployDeclaration memory d = declaration();
        assertEq(d.networks, consumerNetworks());
        assertGt(LibRainDeploy.supportedNetworks().length, d.networks.length);
    }

    function testSuitesNamingNoNetworksTakeTheConsumersNetworks() external pure {
        DeployDeclaration memory d = declaration();
        assertEq(d.released[0].networks, consumerNetworks());
        assertEq(d.candidates[1].snapshot.networks, consumerNetworks());
    }

    function testASuiteNamingItsNetworksKeepsThem() external pure {
        DeployDeclaration memory d = declaration();
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        assertEq(d.candidates[0].snapshot.networks, networks);
    }

    function testEachSuiteDispatchesToItsOwnLayersMechanism() external view {
        DeployDeclaration memory d = declaration();
        assertEq(mechanismOf(d, d.released[0]).id, ZOLTU_MECHANISM_ID);
        assertEq(mechanismOf(d, d.candidates[0].snapshot).id, MOCK_CREATE2_MECHANISM_ID);
        assertEq(mechanismOf(d, d.candidates[1].snapshot).id, MOCK_SALT_MECHANISM_ID);
        assertEq(deployedAddress(d, d.released[0], 8453), LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode));
        assertEq(
            deployedAddress(d, d.candidates[0].snapshot, 137),
            LibMockCreate2Mechanism.create2Address(
                MOCK_CREATE2_FACTORY,
                keccak256(abi.encode(MOCK_CREATE2_SALT, abi.encode(137))),
                type(MockDeployable).creationCode
            )
        );
        assertEq(
            deployedAddress(d, d.candidates[1].snapshot, 8453),
            LibMockCreate2Mechanism.create2Address(
                MOCK_CREATE2_FACTORY, TWO_MECHANISM_SALT, type(MockDeployableV2).creationCode
            )
        );
    }

    function testEachSuitesAddressesFollowTheConsumersNetworks() external view {
        DeployDeclaration memory d = declaration();
        address[] memory addresses = deployedAddresses(d, d.candidates[1].snapshot);
        assertEq(addresses.length, 2);
        assertEq(addresses[0], addresses[1]);
    }
}
