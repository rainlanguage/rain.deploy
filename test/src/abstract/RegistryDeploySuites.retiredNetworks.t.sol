// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RegistryDeploySuites} from "../../../src/abstract/RegistryDeploySuites.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibReleasedSuites} from "../../../src/lib/LibReleasedSuites.sol";

/// @title RegistryDeploySuitesRetiredNetworksTest
/// @notice The retired address registry releases and the releases cut before `zerog` name their own networks, so a
/// declaration whose networks differ from them fills only the later releases.
contract RegistryDeploySuitesRetiredNetworksTest is Test, RegistryDeploySuites {
    function testNarrowedReleasesKeepTheirNetworksUnderANarrowerDeclaration() external pure {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        LibRainDeployDeclaration.setNetworks(d, networks);

        DeploySuite[] memory record = LibReleasedSuites.releasedSuites();
        DeploySuite[] memory released = new DeploySuite[](record.length + 1);
        for (uint256 i = 0; i < record.length; i++) {
            released[i] = record[i];
        }
        released[record.length] = abi.decode(abi.encode(record[record.length - 1]), (DeploySuite));
        released[record.length].suite = "config-registry@0_1_31";
        LibRainDeployDeclaration.addReleased(d, narrowReleasedNetworks(released));

        string[] memory retiredNetworks = addressRegistryNetworks();
        string[] memory before = networksBeforeZerog();
        uint256 retired = 0;
        uint256 beforeZerog = 0;
        uint256 others = 0;
        for (uint256 i = 0; i < d.released.length; i++) {
            DeploySuite memory suite = d.released[i];
            if (keccak256(bytes(suiteKeyName(suite.suite))) == keccak256(bytes(ADDRESS_REGISTRY_SUITE))) {
                retired++;
                assertEq(suite.networks, retiredNetworks, suite.suite);
            } else if (releasedBeforeZerog(suite.suite)) {
                beforeZerog++;
                assertEq(suite.networks, before, suite.suite);
            } else {
                others++;
                assertEq(suite.networks, d.networks, suite.suite);
            }
        }
        assertGt(retired, 1);
        assertGt(beforeZerog, 1);
        assertEq(others, 1);
    }
}
