// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy, NetworkDeploys, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";

/// @title LibRainDeployCheckNetworkDeploysTest
/// @notice The refusals `checkNetworkDeploys` makes before anything is forked.
contract LibRainDeployCheckNetworkDeploysTest is Test {
    function externalCheckNetworkDeploys(SupportedNetwork[] memory networks, NetworkDeploys memory deploys)
        external
        pure
    {
        LibRainDeploy.checkNetworkDeploys(networks, deploys);
    }

    /// Lists of the given lengths, each expected address `0x1000 + i` and each derived address `0x2000 + i`.
    function mismatchedLists(uint256 stepDataLength, uint256 expectedLength, uint256 derivedLength)
        internal
        pure
        returns (NetworkDeploys memory)
    {
        NetworkDeploys memory deploys = NetworkDeploys({
            deployStepData: new bytes[](stepDataLength),
            expectedAddresses: new address[](expectedLength),
            derivedAddresses: new address[](derivedLength)
        });
        for (uint256 i = 0; i < expectedLength; i++) {
            deploys.expectedAddresses[i] = address(uint160(0x1000 + i));
        }
        for (uint256 i = 0; i < derivedLength; i++) {
            deploys.derivedAddresses[i] = address(uint160(0x2000 + i));
        }
        return deploys;
    }

    /// `length` networks with every derived address its expected address.
    function pairedLists(uint256 length) internal pure returns (NetworkDeploys memory) {
        NetworkDeploys memory deploys = mismatchedLists(length, length, length);
        for (uint256 i = 0; i < length; i++) {
            deploys.derivedAddresses[i] = deploys.expectedAddresses[i];
        }
        return deploys;
    }

    /// An empty network set is refused whatever the lists hold.
    function testRefusesNoNetworks(uint256 stepDataLength, uint256 expectedLength, uint256 derivedLength) external {
        stepDataLength = bound(stepDataLength, 0, 8);
        expectedLength = bound(expectedLength, 0, 8);
        derivedLength = bound(derivedLength, 0, 8);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalCheckNetworkDeploys(
            new SupportedNetwork[](0), mismatchedLists(stepDataLength, expectedLength, derivedLength)
        );
    }

    /// Any list not paired one to one with the networks is refused naming every length, before any derived address
    /// is compared.
    function testRefusesUnpairedLists(
        uint256 networksLength,
        uint256 stepDataLength,
        uint256 expectedLength,
        uint256 derivedLength
    ) external {
        networksLength = bound(networksLength, 1, 8);
        stepDataLength = bound(stepDataLength, 0, 8);
        expectedLength = bound(expectedLength, 0, 8);
        derivedLength = bound(derivedLength, 0, 8);
        vm.assume(
            stepDataLength != networksLength || expectedLength != networksLength || derivedLength != networksLength
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.DeployStepNetworksMismatch.selector,
                networksLength,
                stepDataLength,
                expectedLength,
                derivedLength
            )
        );
        this.externalCheckNetworkDeploys(
            new SupportedNetwork[](networksLength), mismatchedLists(stepDataLength, expectedLength, derivedLength)
        );
    }

    /// The first network whose derived address is not its expected address is refused naming both.
    function testRefusesTheFirstDerivedAddressNotExpected(uint256 length, uint256 index) external {
        length = bound(length, 1, 8);
        index = bound(index, 0, length - 1);
        NetworkDeploys memory deploys = pairedLists(length);
        for (uint256 i = index; i < length; i++) {
            deploys.derivedAddresses[i] = address(uint160(0x2000 + i));
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedDeployedAddress.selector,
                address(uint160(0x1000 + index)),
                address(uint160(0x2000 + index))
            )
        );
        this.externalCheckNetworkDeploys(new SupportedNetwork[](length), deploys);
    }

    /// Paired lists whose derived addresses are their expected addresses pass.
    function testAcceptsPairedListsOfExpectedAddresses(uint256 length) external view {
        length = bound(length, 1, 8);
        this.externalCheckNetworkDeploys(new SupportedNetwork[](length), pairedLists(length));
    }
}
