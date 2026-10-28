// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RegistryDeploySuites} from "../../../src/abstract/RegistryDeploySuites.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";

/// @title RegistryDeploySuitesRetiredNetworksTest
/// @notice The retired address registry releases name their own networks, so a declaration whose networks differ
/// from them fills only the other releases.
contract RegistryDeploySuitesRetiredNetworksTest is Test, RegistryDeploySuites {
    function testRetiredAddressRegistryReleasesKeepTheirNetworksUnderANarrowerDeclaration() external pure {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        d.networks = new string[](1);
        d.networks[0] = LibRainDeploy.ARBITRUM_ONE;
        LibRainDeployDeclaration.addReleased(d, registryReleasedSuites());
        string[] memory retiredNetworks = addressRegistryNetworks();
        uint256 retired = 0;
        uint256 others = 0;
        for (uint256 i = 0; i < d.released.length; i++) {
            DeploySuite memory suite = d.released[i];
            if (keccak256(bytes(suiteKeyName(suite.suite))) == keccak256(bytes(ADDRESS_REGISTRY_SUITE))) {
                retired++;
                assertEq(suite.networks, retiredNetworks, suite.suite);
            } else {
                others++;
                assertEq(suite.networks, d.networks, suite.suite);
            }
        }
        assertGt(retired, 1);
        assertGt(others, 0);
    }
}
