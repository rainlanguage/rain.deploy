// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    ExtendedNetworkAddressMismatch,
    ExtendedNetworkUnfrozen,
    InitDataReaderUndeclared
} from "../../../src/lib/LibRainDeployMechanism.sol";
import {
    CloneDeploy,
    CloneNetwork,
    CloneNetworks,
    CloneTarget,
    LibRainDeployClone
} from "../../../src/lib/LibRainDeployClone.sol";
import {
    PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN,
    PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID,
    PER_NETWORK_CLONE_POLYGON_ADMIN,
    PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
    onlyFirstRecordedNetwork,
    perNetworkCloneRelease,
    perNetworkCloneReleaseAddress
} from "../../abstract/PerNetworkCloneDeploys.sol";
import {ZoltuDeployOrAdopt} from "../../abstract/ZoltuDeployOrAdopt.sol";
import {PerNetworkCloneDeploy} from "../../concrete/PerNetworkCloneDeploy.sol";
import {ReaderlessUpgradedPerNetworkCloneDeploy} from "../../concrete/ReaderlessUpgradedPerNetworkCloneDeploy.sol";
import {UpgradedPerNetworkCloneDeploy} from "../../concrete/UpgradedPerNetworkCloneDeploy.sol";
import {
    upgradedPerNetworkClone,
    upgradedPerNetworkCloneAddress
} from "../../abstract/UpgradedPerNetworkCloneDeploys.sol";
import {MockCloneFactory} from "../../concrete/MockCloneFactory.sol";
import {MockCloneable} from "../../concrete/MockCloneable.sol";

/// @title RainDeployBroadcastClonePerNetworkTest
/// @notice The broadcast of a frozen per-network clone release, selected by its key, to Arbitrum
/// One and Polygon.
contract RainDeployBroadcastClonePerNetworkTest is ZoltuDeployOrAdopt {
    /// The release's recorded `CloneNetworks`, its entries asserted to be Arbitrum One's then
    /// Polygon's.
    /// @param release The release suite.
    /// @return The decoded per-network clone.
    function releaseNetworks(DeploySuite memory release) internal pure returns (CloneNetworks memory) {
        CloneNetworks memory clones = abi.decode(release.mechanismData, (CloneNetworks));
        assertEq(clones.networks.length, 2);
        assertEq(clones.networks[0].chainId, PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        assertEq(clones.networks[1].chainId, PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        return clones;
    }

    /// Arbitrum One then Polygon.
    /// @return The two networks.
    function bothNetworks() internal pure returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        return networks;
    }

    /// Polygon at its admin's init data and the address the release derives there, as `extendedNetworks` declares
    /// it before it is broadcast.
    /// @return The declaration.
    function declaredPolygon() internal pure returns (CloneNetwork[] memory) {
        CloneNetwork[] memory networks = new CloneNetwork[](1);
        networks[0] = CloneNetwork({
            chainId: PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
            data: abi.encode(PER_NETWORK_CLONE_POLYGON_ADMIN),
            deployedAddress: perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID)
        });
        return networks;
    }

    /// Whether any fork exists.
    /// @return Whether fork 0 can be selected.
    function anyForkExists() internal returns (bool) {
        (bool forked,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(0)));
        return forked;
    }

    /// The release lands at its recorded address on each network, a different address on each,
    /// initialized with that network's admin, and the other network's address stays empty on each
    /// fork.
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

    /// A network the release has no entry for is refused by its chain id before any network is
    /// forked, though the networks before it have entries.
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

    /// A release whose recorded address for one network is not the address that network's data
    /// derives is refused before any network is forked, naming that network's recorded and derived
    /// addresses.
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

    /// A release cut when the repo supported Arbitrum One alone, broadcast to Arbitrum One and
    /// Polygon.
    function testBroadcastsAnUnrecordedNetworkAtItsInitDataAddress() external {
        PerNetworkCloneDeploy deploy = new PerNetworkCloneDeploy();
        deploy.setExtendedNetworks("per-network-clone@0_0_1", declaredPolygon());
        vm.makePersistent(address(this));
        vm.makePersistent(address(deploy));

        DeploySuite memory release = onlyFirstRecordedNetwork(deploy.externalSuiteByName("per-network-clone@0_0_1"));
        CloneNetworks memory clones = abi.decode(release.mechanismData, (CloneNetworks));
        assertEq(clones.networks.length, 1);
        assertEq(clones.networks[0].chainId, PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        address arbitrumAddress = clones.networks[0].deployedAddress;
        address polygonAddress = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        assertEq(arbitrumAddress, perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID));
        assertNotEq(arbitrumAddress, polygonAddress);

        string[] memory networks = bothNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.createSelectFork(networks[i]);
            vm.makePersistent(
                zoltuDeployOrAdopt(type(MockCloneFactory).creationCode, type(MockCloneFactory).runtimeCode)
            );
            vm.makePersistent(zoltuDeployOrAdopt(type(MockCloneable).creationCode, type(MockCloneable).runtimeCode));
            assertEq(arbitrumAddress.code.length, 0, networks[i]);
            assertEq(polygonAddress.code.length, 0, networks[i]);
        }

        (address[] memory deployed, uint256[] memory forkIds) = deploy.externalBroadcastSuite(release, networks, 1);
        assertEq(deployed.length, 2);
        assertEq(forkIds.length, 2);
        assertEq(deployed[0], arbitrumAddress);
        assertEq(deployed[1], polygonAddress);

        vm.selectFork(forkIds[0]);
        assertEq(block.chainid, PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        assertEq(arbitrumAddress.codehash, release.storedBytecodeHash);
        assertEq(MockCloneable(arbitrumAddress).sInitData(), abi.encode(PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN));
        assertEq(polygonAddress.code.length, 0);

        vm.selectFork(forkIds[1]);
        assertEq(block.chainid, PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        assertEq(polygonAddress.codehash, release.storedBytecodeHash);
        assertEq(MockCloneable(polygonAddress).sInitData(), abi.encode(PER_NETWORK_CLONE_POLYGON_ADMIN));
        assertEq(arbitrumAddress.code.length, 0);
    }

    /// A release recording Arbitrum One alone, broadcast to both networks by a repo whose candidate
    /// has since moved to another factory, implementation and salt, puts Polygon's clone where the
    /// RELEASE's factory, implementation and salt derive it with the candidate's Polygon init data.
    function testBroadcastsAnUnrecordedNetworkUnderTheReleasesFactoryAndImplementation() external {
        UpgradedPerNetworkCloneDeploy deploy = new UpgradedPerNetworkCloneDeploy();
        deploy.setExtendedNetworks("per-network-clone@0_0_1", declaredPolygon());
        vm.makePersistent(address(this));
        vm.makePersistent(address(deploy));

        DeploySuite memory release = onlyFirstRecordedNetwork(deploy.externalSuiteByName("per-network-clone@0_0_1"));
        CloneNetworks memory clones = abi.decode(release.mechanismData, (CloneNetworks));
        assertEq(clones.networks.length, 1);
        assertEq(clones.networks[0].chainId, PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        CloneDeploy memory candidate = upgradedPerNetworkClone();
        assertNotEq(candidate.factory, clones.factory);
        assertNotEq(candidate.implementation, clones.implementation);
        assertNotEq(candidate.salt, clones.salt);

        address arbitrumAddress = clones.networks[0].deployedAddress;
        address polygonAddress = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        address candidatePolygonAddress = upgradedPerNetworkCloneAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        assertNotEq(polygonAddress, candidatePolygonAddress);

        string[] memory networks = bothNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.createSelectFork(networks[i]);
            vm.makePersistent(
                zoltuDeployOrAdopt(type(MockCloneFactory).creationCode, type(MockCloneFactory).runtimeCode)
            );
            vm.makePersistent(zoltuDeployOrAdopt(type(MockCloneable).creationCode, type(MockCloneable).runtimeCode));
            assertEq(polygonAddress.code.length, 0, networks[i]);
            assertEq(candidate.factory.code.length, 0, networks[i]);
            assertEq(candidate.implementation.code.length, 0, networks[i]);
        }

        (address[] memory deployed, uint256[] memory forkIds) = deploy.externalBroadcastSuite(release, networks, 1);
        assertEq(deployed.length, 2);
        assertEq(deployed[0], arbitrumAddress);
        assertEq(deployed[1], polygonAddress);

        vm.selectFork(forkIds[1]);
        assertEq(block.chainid, PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        assertEq(polygonAddress.codehash, release.storedBytecodeHash);
        assertEq(MockCloneable(polygonAddress).sInitData(), abi.encode(PER_NETWORK_CLONE_POLYGON_ADMIN));
        assertEq(candidatePolygonAddress.code.length, 0);
    }

    /// A release recording Arbitrum One alone, broadcast with Polygon too, still has its stale
    /// recorded Arbitrum One address refused before any network is forked.
    function testBroadcastRefusesAStaleRecordedAddressBesideAnUnrecordedNetworkBeforeAnyFork() external {
        PerNetworkCloneDeploy deploy = new PerNetworkCloneDeploy();
        deploy.setExtendedNetworks("per-network-clone@0_0_1", declaredPolygon());
        DeploySuite memory release = onlyFirstRecordedNetwork(deploy.externalSuiteByName("per-network-clone@0_0_1"));
        CloneNetworks memory clones = abi.decode(release.mechanismData, (CloneNetworks));
        address derived = clones.networks[0].deployedAddress;
        address stale = address(uint160(derived) + 1);
        clones.networks[0].deployedAddress = stale;
        release.mechanismData = abi.encode(clones);

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.UnexpectedDeployedAddress.selector, stale, derived));
        deploy.externalBroadcastSuite(release, bothNetworks(), 1);
        assertFalse(anyForkExists(), "a network was forked before the stale address was refused");
    }

    /// A release recording Arbitrum One alone, with Polygon declared at an address its init data does not derive, is
    /// refused before any network is forked, naming both addresses.
    function testBroadcastRefusesAMisdeclaredExtendedNetworkBeforeAnyFork() external {
        PerNetworkCloneDeploy deploy = new PerNetworkCloneDeploy();
        CloneNetwork[] memory declared = declaredPolygon();
        address derived = declared[0].deployedAddress;
        declared[0].deployedAddress = address(0xdead);
        deploy.setExtendedNetworks("per-network-clone@0_0_1", declared);
        DeploySuite memory release = onlyFirstRecordedNetwork(deploy.externalSuiteByName("per-network-clone@0_0_1"));

        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkAddressMismatch.selector,
                release.suite,
                PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
                derived,
                address(0xdead)
            )
        );
        deploy.externalBroadcastSuite(release, bothNetworks(), 1);
        assertFalse(anyForkExists(), "a network was forked before the misdeclared one was refused");
    }

    /// A release recording Arbitrum One alone is refused a broadcast to Polygon, which it does not declare, before any
    /// network is forked, naming the address Polygon would take.
    function testBroadcastRefusesAnUndeclaredUnrecordedNetworkBeforeAnyFork() external {
        PerNetworkCloneDeploy deploy = new PerNetworkCloneDeploy();
        DeploySuite memory release = onlyFirstRecordedNetwork(deploy.externalSuiteByName("per-network-clone@0_0_1"));

        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkUnfrozen.selector,
                release.suite,
                LibRainDeploy.POLYGON,
                perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID)
            )
        );
        deploy.externalBroadcastSuite(release, bothNetworks(), 1);
        assertFalse(anyForkExists(), "a network was forked before the undeclared one was refused");
    }

    /// A release recording Arbitrum One alone, with Polygon declared at init data other than the candidate's, lands on
    /// Polygon at the declared address with the declared data, not where the candidate's data derives.
    function testBroadcastsAnExtendedNetworkAtItsDeclaredData() external {
        PerNetworkCloneDeploy deploy = new PerNetworkCloneDeploy();
        bytes memory declaredData = abi.encode(address(0xC4c4c4C4C4c4C4c4c4C4c4c4c4c4c4C4c4c4c4C4));
        CloneDeploy memory release = perNetworkCloneRelease();
        address declaredAddress = LibRainDeployClone.cloneDeployedAddress(
            CloneTarget({
                factory: release.factory, implementation: release.implementation, data: declaredData, salt: release.salt
            })
        );
        address candidateAddress = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        assertNotEq(declaredAddress, candidateAddress);
        CloneNetwork[] memory declared = new CloneNetwork[](1);
        declared[0] = CloneNetwork({
            chainId: PER_NETWORK_CLONE_POLYGON_CHAIN_ID, data: declaredData, deployedAddress: declaredAddress
        });
        deploy.setExtendedNetworks("per-network-clone@0_0_1", declared);
        vm.makePersistent(address(this));
        vm.makePersistent(address(deploy));

        DeploySuite memory suite = onlyFirstRecordedNetwork(deploy.externalSuiteByName("per-network-clone@0_0_1"));

        string[] memory networks = bothNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            vm.createSelectFork(networks[i]);
            vm.makePersistent(
                zoltuDeployOrAdopt(type(MockCloneFactory).creationCode, type(MockCloneFactory).runtimeCode)
            );
            vm.makePersistent(zoltuDeployOrAdopt(type(MockCloneable).creationCode, type(MockCloneable).runtimeCode));
            assertEq(declaredAddress.code.length, 0, networks[i]);
            assertEq(candidateAddress.code.length, 0, networks[i]);
        }

        (address[] memory deployed, uint256[] memory forkIds) = deploy.externalBroadcastSuite(suite, networks, 1);
        assertEq(deployed.length, 2);
        assertEq(deployed[1], declaredAddress);

        vm.selectFork(forkIds[1]);
        assertEq(block.chainid, PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        assertEq(declaredAddress.codehash, suite.storedBytecodeHash);
        assertEq(MockCloneable(declaredAddress).sInitData(), declaredData);
        assertEq(candidateAddress.code.length, 0);
    }

    /// A release recording Arbitrum One alone, under an implementation the candidate no longer uses and with no init
    /// data reader declared, is refused the full set before any fork, and broadcast to its recorded Arbitrum One alone
    /// needs no reader.
    function testBroadcastToTheRecordedSubsetNeedsNoInitDataReader() external {
        ReaderlessUpgradedPerNetworkCloneDeploy deploy = new ReaderlessUpgradedPerNetworkCloneDeploy();
        vm.makePersistent(address(this));
        vm.makePersistent(address(deploy));

        DeploySuite memory suite = onlyFirstRecordedNetwork(deploy.externalSuiteByName("per-network-clone@0_0_1"));
        CloneNetworks memory clones = abi.decode(suite.mechanismData, (CloneNetworks));
        assertEq(clones.networks.length, 1);
        assertNotEq(clones.implementation, upgradedPerNetworkClone().implementation);

        vm.expectRevert(abi.encodeWithSelector(InitDataReaderUndeclared.selector, suite.suite, clones.implementation));
        deploy.externalBroadcastSuite(suite, bothNetworks(), 1);
        assertFalse(anyForkExists(), "a network was forked before the undeclared reader was refused");

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        vm.createSelectFork(networks[0]);
        vm.makePersistent(zoltuDeployOrAdopt(type(MockCloneFactory).creationCode, type(MockCloneFactory).runtimeCode));
        vm.makePersistent(zoltuDeployOrAdopt(type(MockCloneable).creationCode, type(MockCloneable).runtimeCode));
        address arbitrumAddress = clones.networks[0].deployedAddress;
        assertEq(arbitrumAddress.code.length, 0);

        (address[] memory deployed, uint256[] memory forkIds) = deploy.externalBroadcastSuite(suite, networks, 1);
        assertEq(deployed.length, 1);
        assertEq(deployed[0], arbitrumAddress);
        vm.selectFork(forkIds[0]);
        assertEq(block.chainid, PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        assertEq(arbitrumAddress.codehash, suite.storedBytecodeHash);
        assertEq(MockCloneable(arbitrumAddress).sInitData(), abi.encode(PER_NETWORK_CLONE_ARBITRUM_ONE_ADMIN));
    }
}
