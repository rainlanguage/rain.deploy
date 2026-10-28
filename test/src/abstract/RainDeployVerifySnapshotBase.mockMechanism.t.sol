// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibMockCreate2Mechanism} from "../../lib/LibMockCreate2Mechanism.sol";

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    RainDeployVerifySnapshotBase,
    StoredAddressMismatch
} from "../../../src/abstract/RainDeployVerifySnapshotBase.sol";
import {ChainDeploy} from "../../../src/lib/LibRainDeployExtendedNetworks.sol";
import {MockCreate2DeploySuites, MockCreate2Mechanism} from "../../abstract/MockCreate2DeploySuites.sol";

/// @title RainDeployVerifySnapshotBaseMockMechanismTest
/// @notice The snapshot group checks each network's recorded address through a non-Zoltu mechanism handler.
contract RainDeployVerifySnapshotBaseMockMechanismTest is MockCreate2DeploySuites, RainDeployVerifySnapshotBase {
    function externalCheckInternallyConsistent(DeploySuite memory suite) external {
        checkInternallyConsistent(suite);
    }

    function releaseRecording(uint256 index, address recorded) internal pure returns (DeploySuite memory) {
        DeploySuite memory release = mockRelease();
        MockCreate2Mechanism memory mechanism = abi.decode(release.mechanismData, (MockCreate2Mechanism));
        mechanism.networks[index].deployedAddress = recorded;
        release.mechanismData = LibMockCreate2Mechanism.encode(mechanism);
        return release;
    }

    function testAcceptsEveryNetworkAtItsDerivedAddress() external {
        this.externalCheckInternallyConsistent(mockRelease());
    }

    function testRefusesAStaleFirstNetwork() external {
        DeploySuite memory release = releaseRecording(0, address(0xdead));
        vm.expectRevert(
            abi.encodeWithSelector(
                StoredAddressMismatch.selector, release.suite, address(0xdead), mockNetwork(42161).deployedAddress
            )
        );
        this.externalCheckInternallyConsistent(release);
    }

    function testRefusesAStaleSecondNetwork() external {
        DeploySuite memory release = releaseRecording(1, address(0xdead));
        vm.expectRevert(
            abi.encodeWithSelector(
                StoredAddressMismatch.selector, release.suite, address(0xdead), mockNetwork(137).deployedAddress
            )
        );
        this.externalCheckInternallyConsistent(release);
    }

    function testRefusesASecondNetworkRecordingTheFirstsAddress() external {
        DeploySuite memory release = releaseRecording(1, mockNetwork(42161).deployedAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                StoredAddressMismatch.selector,
                release.suite,
                mockNetwork(42161).deployedAddress,
                mockNetwork(137).deployedAddress
            )
        );
        this.externalCheckInternallyConsistent(release);
    }

    function extendedNetworksRoot()
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (string memory)
    {
        return super.extendedNetworksRoot();
    }

    function extendedNetworks(string memory suite)
        internal
        view
        override(RainDeploySuitesBase, MockCreate2DeploySuites)
        returns (ChainDeploy[] memory)
    {
        return super.extendedNetworks(suite);
    }
}
