// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {DeployDependency, LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ExampleDeploy} from "../../concrete/ExampleDeploy.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";

/// @title RainDeployBroadcastDeployAndBroadcastTest
/// @notice `deployAndBroadcast` over a Zoltu suite.
contract RainDeployBroadcastDeployAndBroadcastTest is Test {
    ExampleDeploy internal sDeploy;

    function setUp() external {
        sDeploy = new ExampleDeploy();
    }

    function zoltuSuite(address recordedAddress) internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: "zoltu",
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: recordedAddress,
            storedBytecodeHash: bytes32(0),
            storedRuntimeCode: "",
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new DeployDependency[](0),
            mechanismData: ""
        });
    }

    function anyForkExists() internal returns (bool) {
        (bool forked,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(0)));
        return forked;
    }

    function arbitrumAndPolygon() internal pure returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        return networks;
    }

    /// A Zoltu broadcast under a compiled artifact path formats one verify command per network.
    function testZoltuBroadcastUnderACompiledArtifactPrintsVerifyCommands() external {
        LibRainDeploy.etchZoltuFactory(vm);
        DeploySuite memory suite = zoltuSuite(LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode));
        suite.storedBytecodeHash = keccak256(type(MockDeployable).runtimeCode);
        LocalForkVm forkVm = new LocalForkVm();
        vm.expectCall(address(forkVm), abi.encodeWithSignature("toString(address)", suite.storedDeployedAddress), 2);
        sDeploy.externalDeployAndBroadcast(Vm(address(forkVm)), arbitrumAndPolygon(), 1, suite, suite);
    }

    /// Key zero has no wallet, so `NoNetworks` proves the list is refused before the key, and a
    /// stale recorded address proves it is refused before the address check.
    function testNoNetworksRevertsBeforeTheKeyAndTheAddress() external {
        DeploySuite memory suite = zoltuSuite(address(1));
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        sDeploy.externalDeployAndBroadcast(vm, new string[](0), 0, suite, suite);
    }

    function testZoltuStaleRecordedAddressRevertsBeforeForking() external {
        address derived = LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode);
        address stale = address(uint160(derived) + 1);
        DeploySuite memory suite = zoltuSuite(stale);

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.UnexpectedDeployedAddress.selector, stale, derived));
        sDeploy.externalDeployAndBroadcast(vm, arbitrumAndPolygon(), 1, suite, suite);
        assertFalse(anyForkExists());
    }
}
