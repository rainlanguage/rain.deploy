// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    RainDeployVerifySnapshotBase,
    StoredAddressMismatch
} from "../../../src/abstract/RainDeployVerifySnapshotBase.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {MockCreate2DeploySuites} from "../../abstract/MockCreate2DeploySuites.sol";
import {
    LibMockCreate2Mechanism,
    MOCK_CREATE2_MECHANISM_ID,
    MockCreate2Mechanism
} from "../../lib/LibMockCreate2Mechanism.sol";
import {IMockMechanismProbe, MOCK_MECHANISM_PROBE} from "../../lib/LibMockMechanismProbe.sol";
import {LibMockSaltMechanism, MOCK_SALT_MECHANISM_ID} from "../../lib/LibMockSaltMechanism.sol";

/// @title RainDeployVerifySnapshotBaseMockMechanismTest
/// @notice The snapshot group checks each network's recorded address through a non-Zoltu mechanism handler.
contract RainDeployVerifySnapshotBaseMockMechanismTest is MockCreate2DeploySuites, RainDeployVerifySnapshotBase {
    function declaration() internal view override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibMockCreate2Mechanism.extend(d);
        LibMockSaltMechanism.extend(d);
        addMockCreate2(d);
        return d;
    }

    function externalCheckInternallyConsistent(DeploySuite memory suite) external {
        checkInternallyConsistent(declaration(), suite);
    }

    function releaseRecording(uint256 index, address recorded) internal view returns (DeploySuite memory) {
        DeploySuite memory release = mockRelease();
        MockCreate2Mechanism memory mechanism = LibMockCreate2Mechanism.decode(release);
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

    /// `checkDeclaration` runs once per declared mechanism.
    function testMechanismDeclarationsResolveChecksEachMechanismOnce() external {
        vm.expectCall(
            MOCK_MECHANISM_PROBE, abi.encodeCall(IMockMechanismProbe.checkDeclaration, (MOCK_CREATE2_MECHANISM_ID)), 1
        );
        vm.expectCall(
            MOCK_MECHANISM_PROBE, abi.encodeCall(IMockMechanismProbe.checkDeclaration, (MOCK_SALT_MECHANISM_ID)), 1
        );
        this.testMechanismDeclarationsResolve();
    }

    function testMechanismDeclarationsResolveRefusalPropagates() external {
        vm.mockCallRevert(
            MOCK_MECHANISM_PROBE,
            abi.encodeCall(IMockMechanismProbe.checkDeclaration, (MOCK_SALT_MECHANISM_ID)),
            abi.encode("refused")
        );
        vm.expectRevert(abi.encode("refused"));
        this.testMechanismDeclarationsResolve();
    }
}
