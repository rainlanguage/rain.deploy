// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {NotDeployedOnNetwork, RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {CloneNetworks, LibRainDeployClone} from "../../../src/lib/LibRainDeployClone.sol";
import {
    PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID,
    PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
    PerNetworkCloneDeploys,
    onlyFirstRecordedNetwork,
    perNetworkCloneReleaseAddress
} from "../../abstract/PerNetworkCloneDeploys.sol";

/// @title RainDeployVerifyChainClonePerNetworkUnrecordedTest
/// @notice The chain matrix over a per-network clone release cut when the repo
/// supported Arbitrum One alone, in a repo that now supports Polygon too.
///
/// The release records nothing for Polygon. The matrix checks it there anyway,
/// at the address the declaration's Polygon init data derives under the
/// release's factory, implementation and salt — where a broadcast of the
/// release puts it — and at the recorded address on Arbitrum One.
contract RainDeployVerifyChainClonePerNetworkUnrecordedTest is PerNetworkCloneDeploys, RainDeployVerifyChain {
    /// @inheritdoc PerNetworkCloneDeploys
    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return PerNetworkCloneDeploys.supportedNetworks();
    }

    /// Puts the release's dependencies, and its clone at the address for each
    /// network, on every fork.
    function setUp() external {
        DeploySuite memory release = releasedSuites()[0];
        for (uint256 i = 0; i < release.dependencies.length; i++) {
            vm.etch(release.dependencies[i].deployedAddress, release.dependencies[i].runtimeCode);
            vm.makePersistent(release.dependencies[i].deployedAddress);
        }
        address[] memory addresses = new address[](2);
        addresses[0] = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        addresses[1] = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        for (uint256 i = 0; i < addresses.length; i++) {
            vm.etch(addresses[i], release.storedRuntimeCode);
            vm.makePersistent(addresses[i]);
        }
    }

    /// External wrapper for `checkDeployedOnSupportedNetworks`.
    /// @param suites The suites to check.
    function externalCheckDeployedOnSupportedNetworks(DeploySuite[] memory suites) external {
        checkDeployedOnSupportedNetworks(suites);
    }

    /// The release, recording Arbitrum One alone.
    /// @return suites It, as the one suite to check.
    function arbitrumOnlyRelease() internal pure returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](1);
        suites[0] = onlyFirstRecordedNetwork(releasedSuites()[0]);
        CloneNetworks memory clones = abi.decode(suites[0].mechanismData, (CloneNetworks));
        assertEq(clones.networks.length, 1);
        assertEq(clones.networks[0].chainId, PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        assertEq(
            clones.networks[0].deployedAddress, perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID)
        );
    }

    /// The release passes with its clone at the Polygon init data's address on
    /// Polygon, and with that address empty is refused on Polygon naming it:
    /// the matrix checked Polygon, at that address, though the release records
    /// nothing there.
    function testUnrecordedNetworkIsCheckedAtItsInitDataAddress() external {
        DeploySuite[] memory suites = arbitrumOnlyRelease();
        this.externalCheckDeployedOnSupportedNetworks(suites);

        address polygonAddress = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        assertNotEq(polygonAddress, perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID));
        vm.etch(polygonAddress, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                NotDeployedOnNetwork.selector, LibRainDeploy.POLYGON, suites[0].suite, polygonAddress
            )
        );
        this.externalCheckDeployedOnSupportedNetworks(suites);
    }

    /// The recorded network is still checked at its recorded address.
    function testRecordedNetworkIsStillCheckedAtItsRecordedAddress() external {
        DeploySuite[] memory suites = arbitrumOnlyRelease();
        address arbitrumAddress = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        vm.etch(arbitrumAddress, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                NotDeployedOnNetwork.selector, LibRainDeploy.ARBITRUM_ONE, suites[0].suite, arbitrumAddress
            )
        );
        this.externalCheckDeployedOnSupportedNetworks(suites);
    }

    /// A release no candidate is named by takes no network from one: the
    /// network it does not record is refused by chain id, before any fork.
    function testReleaseNoCandidateNamesIsRefusedOnItsUnrecordedNetworkBeforeAnyFork() external {
        DeploySuite[] memory suites = arbitrumOnlyRelease();
        suites[0].suite = "other-clone@0_0_1";
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployClone.CloneNetworkUndeclared.selector, PER_NETWORK_CLONE_POLYGON_CHAIN_ID
            )
        );
        this.externalCheckDeployedOnSupportedNetworks(suites);

        (bool forked,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(0)));
        assertFalse(forked, "the matrix forked a network before refusing the unrecorded one");
    }
}
