// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {CloneNetworks, LibRainDeployClone} from "../../../src/lib/LibRainDeployClone.sol";
import {
    PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN,
    PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID,
    PER_NETWORK_CLONE_POLYGON_ADMIN,
    PER_NETWORK_CLONE_POLYGON_CHAIN_ID
} from "../../abstract/PerNetworkCloneDeploys.sol";
import {ZoltuDeployOrAdopt} from "../../abstract/ZoltuDeployOrAdopt.sol";
import {PerNetworkCloneDeploy} from "../../concrete/PerNetworkCloneDeploy.sol";
import {MockCloneFactory} from "../../concrete/MockCloneFactory.sol";
import {MockCloneable} from "../../concrete/MockCloneable.sol";

/// @title RainDeployBroadcastClonePerNetworkTest
/// @notice The broadcast of a frozen per-network clone release, selected by
/// its key, to Arbitrum One and Polygon: each network gets the clone its own
/// admin derives, at the address the record holds for that network, and
/// nothing at the other network's address.
contract RainDeployBroadcastClonePerNetworkTest is ZoltuDeployOrAdopt {
    /// The release's recorded `CloneNetworks`, its entries asserted to be
    /// Arbitrum One's then Polygon's.
    /// @param release The release suite.
    /// @return clones The decoded per-network clone.
    function releaseNetworks(DeploySuite memory release) internal pure returns (CloneNetworks memory clones) {
        clones = abi.decode(release.mechanismData, (CloneNetworks));
        assertEq(clones.networks.length, 2);
        assertEq(clones.networks[0].chainId, PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        assertEq(clones.networks[1].chainId, PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
    }

    /// Arbitrum One then Polygon.
    /// @return networks The two networks.
    function bothNetworks() internal pure returns (string[] memory networks) {
        networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
    }

    /// Whether any fork exists. Fork ids are handed out from zero.
    /// @return Whether fork 0 can be selected.
    function anyForkExists() internal returns (bool) {
        (bool forked,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(0)));
        return forked;
    }

    /// The release lands at its recorded address on each network, a different
    /// address on each, initialized with that network's admin, and the other
    /// network's address stays empty on each fork. Broadcasting one address
    /// everywhere, or one network's data everywhere, puts a clone where the
    /// other network's record says nothing is, or the wrong admin in it.
    function testBroadcastsThePerNetworkReleaseToEachNetworkAtItsOwnAddress() external {
        PerNetworkCloneDeploy deploy = new PerNetworkCloneDeploy();
        vm.makePersistent(address(this));
        vm.makePersistent(address(deploy));

        DeploySuite memory release = deploy.externalSuiteByName("per-network-clone@0_0_1");
        CloneNetworks memory clones = releaseNetworks(release);
        address[] memory recorded = new address[](2);
        recorded[0] = clones.networks[0].deployedAddress;
        recorded[1] = clones.networks[1].deployedAddress;
        assertNotEq(recorded[0], recorded[1], "the two networks' clones must derive apart");

        bytes[] memory admins = new bytes[](2);
        admins[0] = abi.encode(PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN);
        admins[1] = abi.encode(PER_NETWORK_CLONE_POLYGON_ADMIN);
        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID;
        chainIds[1] = PER_NETWORK_CLONE_POLYGON_CHAIN_ID;

        string[] memory networks = bothNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.createSelectFork(networks[i]);
            vm.makePersistent(
                zoltuDeployOrAdopt(type(MockCloneFactory).creationCode, type(MockCloneFactory).runtimeCode)
            );
            vm.makePersistent(zoltuDeployOrAdopt(type(MockCloneable).creationCode, type(MockCloneable).runtimeCode));
            assertEq(recorded[0].code.length, 0, networks[i]);
            assertEq(recorded[1].code.length, 0, networks[i]);
        }

        (address[] memory deployed, uint256[] memory forkIds) = deploy.externalBroadcastSuite(release, networks, 1);
        assertEq(deployed.length, 2);
        assertEq(forkIds.length, 2);
        assertEq(deployed[0], recorded[0]);
        assertEq(deployed[1], recorded[1]);

        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            assertEq(block.chainid, chainIds[i], networks[i]);
            assertEq(recorded[i].codehash, release.storedBytecodeHash, networks[i]);
            assertEq(MockCloneable(recorded[i]).sInitData(), admins[i], networks[i]);
            assertEq(recorded[1 - i].code.length, 0, networks[i]);
        }
    }

    /// A network the release has no entry for is refused by its chain id
    /// before any network is forked, though the networks before it have
    /// entries.
    function testBroadcastRefusesAnUndeclaredNetworkBeforeAnyFork() external {
        PerNetworkCloneDeploy deploy = new PerNetworkCloneDeploy();
        DeploySuite memory release = deploy.externalSuiteByName("per-network-clone@0_0_1");

        string[] memory networks = new string[](3);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        networks[2] = LibRainDeploy.BASE;

        vm.expectRevert(abi.encodeWithSelector(LibRainDeployClone.CloneNetworkUndeclared.selector, 8453));
        deploy.externalBroadcastSuite(release, networks, 1);
        assertFalse(anyForkExists(), "a network was forked before the undeclared one was refused");
    }

    /// A release whose recorded address for one network is not the address
    /// that network's data derives is refused before any network is forked,
    /// naming that network's recorded and derived addresses. Polygon's is
    /// staled, so a check of the first entry only passes it.
    function testBroadcastRefusesAStaleRecordedAddressBeforeAnyFork() external {
        PerNetworkCloneDeploy deploy = new PerNetworkCloneDeploy();
        DeploySuite memory release = deploy.externalSuiteByName("per-network-clone@0_0_1");
        CloneNetworks memory clones = releaseNetworks(release);
        address derived = clones.networks[1].deployedAddress;
        address stale = address(uint160(derived) + 1);
        clones.networks[1].deployedAddress = stale;
        release.mechanismData = abi.encode(clones);

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.UnexpectedDeployedAddress.selector, stale, derived));
        deploy.externalBroadcastSuite(release, bothNetworks(), 1);
        assertFalse(anyForkExists(), "a network was forked before the stale address was refused");
    }
}
