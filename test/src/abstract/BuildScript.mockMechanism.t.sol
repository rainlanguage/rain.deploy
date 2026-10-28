// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibCodeGen, RAIN_COPYRIGHT_TEXT, RAIN_SPDX_LICENSE_IDENTIFIER} from "rain-sol-codegen-0.1.39/src/lib/LibCodeGen.sol";
import {
    ChainDeploy,
    ExtendedNetworksRewritten,
    LibRainDeployExtendedNetworks
} from "../../../src/lib/LibRainDeployExtendedNetworks.sol";
import {MockCreate2BuildScriptHarness} from "../../concrete/MockCreate2BuildScriptHarness.sol";

/// @title BuildScriptMockMechanismTest
/// @notice The build writes the extended networks record of a per-network release whose mechanism accepts them.
contract BuildScriptMockMechanismTest is Test {
    string constant ROOT = "fixture-lib/buildscript-mock-create2";

    function extended(uint256 chainId) internal pure returns (ChainDeploy memory) {
        return ChainDeploy({chainId: chainId, data: abi.encode(chainId), deployedAddress: address(uint160(chainId))});
    }

    function testRegenerateExtendedNetworksWritesAPerNetworkReleasesRecord() external {
        if (vm.exists(ROOT)) {
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.removeDir(ROOT, true);
        }
        MockCreate2BuildScriptHarness harness = new MockCreate2BuildScriptHarness();
        harness.setMockExtendedNetworksRoot(ROOT);
        (,, string memory path) = LibRainDeployExtendedNetworks.extendedNetworksPath(ROOT, "mock-create2@0_0_1");

        harness.externalRegenerateExtendedNetworks();
        bool writtenForNothing = vm.exists(path);

        ChainDeploy[] memory networks = new ChainDeploy[](2);
        networks[0] = extended(8453);
        networks[1] = extended(10);
        harness.setMockExtendedNetworks(networks);
        harness.externalRegenerateExtendedNetworks();
        string memory record = vm.readFile(path);
        string[] memory paths = harness.externalExtendedNetworksPaths();

        harness.setMockExtendedNetworks(new ChainDeploy[](0));
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksRewritten.selector, "mock-create2@0_0_1", 0));
        harness.externalRegenerateExtendedNetworks();
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(ROOT, true);

        assertFalse(writtenForNothing, "a release declaring nothing has no record");
        assertEq(
            record,
            string.concat(
                LibCodeGen.filePrefix(RAIN_SPDX_LICENSE_IDENTIFIER, RAIN_COPYRIGHT_TEXT),
                LibRainDeployExtendedNetworks.extendedNetworksBody(vm, networks)
            )
        );
        assertEq(paths.length, 1);
        assertEq(paths[0], path);
    }
}
