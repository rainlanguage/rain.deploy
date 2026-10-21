// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {DeployMechanism, DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {BeaconProxyBeaconUndeclared} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {DeployDependency, LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployClone} from "../../../src/lib/LibRainDeployClone.sol";
import {BeaconProxyDeploy} from "../../../src/lib/LibRainDeployBeaconProxy.sol";
import {LibRainDeployMechanism} from "../../../src/lib/LibRainDeployMechanism.sol";
import {
    PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID,
    PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
    perNetworkCloneChainIds,
    perNetworkCloneInitData,
    perNetworkCloneReleaseAddress
} from "../../abstract/PerNetworkCloneDeploys.sol";
import {PerNetworkCloneBeaconVerifyChain} from "../../abstract/PerNetworkCloneBeaconVerifyChain.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";
import {MockBeaconProxyFactory} from "../../concrete/MockBeaconProxyFactory.sol";

/// @title RainDeployVerifyChainBeaconProxyTest
/// @notice The chain matrix, on local forks, over a beacon proxy suite whose beacon is the one declared on Polygon.
contract RainDeployVerifyChainBeaconProxyTest is PerNetworkCloneBeaconVerifyChain {
    /// The beacon proxy suite's key.
    string constant PROXY_SUITE = "beacon-proxy@0_0_1";

    /// The factory the proxy is deployed through.
    address internal sFactory;

    /// Whether `requiresSuiteOn` requires the proxy on every network rather than Polygon alone.
    bool internal sRequiredEverywhere;

    /// Puts the per-network clone release and the beacon at its Polygon clone on every fork, as
    /// `RainDeployVerifyChainBeaconPerNetworkCloneTestBase` does, plus the factory.
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
        sBeacon = address(new UpgradeableBeacon(addresses[1], OWNER));
        vm.makePersistent(sBeacon);
        sFactory = address(new MockBeaconProxyFactory());
        vm.makePersistent(sFactory);
    }

    /// The proxy on Polygon alone, unless `sRequiredEverywhere` is set.
    /// @inheritdoc RainDeploySuitesBase
    function requiresSuiteOn(DeploySuite memory suite, string memory network) internal view override returns (bool) {
        (suite);
        return sRequiredEverywhere || keccak256(bytes(network)) == keccak256(bytes(LibRainDeploy.POLYGON));
    }

    /// The one-data proxy suite over `beacon`, live at its derived address on every fork.
    /// @param beacon The beacon the proxy reads.
    /// @return The suite.
    function liveProxySuite(address beacon) internal returns (DeploySuite memory) {
        return liveProxySuite(beacon, false);
    }

    /// The proxy suite over `beacon`, live at each of its derived addresses on every fork.
    /// @param beacon The beacon the proxy reads.
    /// @param initDataPerNetwork Whether its init data, and so its address, is per network.
    /// @return The suite.
    function liveProxySuite(address beacon, bool initDataPerNetwork) internal returns (DeploySuite memory) {
        DeployDependency[] memory dependencies = new DeployDependency[](2);
        dependencies[0] = DeployDependency({deployedAddress: sFactory, runtimeCode: sFactory.code});
        dependencies[1] = DeployDependency({deployedAddress: beacon, runtimeCode: beacon.code});
        DeploySuite memory suite =
        LibRainDeployMechanism.beaconProxyCandidate(
            BeaconProxyDeploy({
                suite: PROXY_SUITE,
                factory: sFactory,
                beacon: beacon,
                data: initDataPerNetwork ? bytes("") : bytes(hex"deadbeef"),
                initDataPerNetwork: initDataPerNetwork,
                initData: initDataPerNetwork ? perNetworkCloneInitData : LibRainDeployClone.noInitDataPerNetwork,
                salt: bytes32(uint256(5)),
                dependencies: dependencies
            }),
            perNetworkCloneChainIds()
        )
        .snapshot;
        address[] memory deployed = LibRainDeployMechanism.deployedAddresses(suite);
        for (uint256 i = 0; i < deployed.length; i++) {
            vm.etch(deployed[i], suite.storedRuntimeCode);
            vm.makePersistent(deployed[i]);
        }
        return suite;
    }

    /// The matrix on local forks over `suite` alone.
    /// @param suite The suite.
    function externalCheckOnLocalForks(DeploySuite memory suite) external {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = suite;
        checkDeployedOnNetworks(
            Vm(address(new LocalForkVm())), LibRainDeploy.declaredNetworkConfigs(supportedNetworks()), suites
        );
    }

    /// A proxy over the beacon declared on Polygon passes on Polygon, with the beacon's own checks run after the
    /// local deploy replaced it with the stand-in.
    function testProxyOverTheDeclaredBeaconPasses() external {
        DeploySuite memory suite = liveProxySuite(sBeacon);
        bytes memory beaconCode = sBeacon.code;
        this.externalCheckOnLocalForks(suite);
        assertEq(sBeacon.code, beaconCode);
        assertEq(UpgradeableBeacon(sBeacon).owner(), OWNER);
    }

    /// Required on Arbitrum One too, where no beacon is declared, the proxy is refused naming Arbitrum One.
    function testProxyRequiredWhereItsBeaconIsUndeclaredIsRefused() external {
        DeploySuite memory suite = liveProxySuite(sBeacon);
        sRequiredEverywhere = true;
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconProxyBeaconUndeclared.selector, PROXY_SUITE, LibRainDeploy.ARBITRUM_ONE, sBeacon
            )
        );
        this.externalCheckOnLocalForks(suite);
    }

    /// A proxy over a beacon `beacons()` does not declare is refused on Polygon.
    function testProxyOverAnUndeclaredBeaconIsRefused() external {
        address other =
            address(new UpgradeableBeacon(perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID), OWNER));
        vm.makePersistent(other);
        DeploySuite memory suite = liveProxySuite(other);
        vm.expectRevert(
            abi.encodeWithSelector(BeaconProxyBeaconUndeclared.selector, PROXY_SUITE, LibRainDeploy.POLYGON, other)
        );
        this.externalCheckOnLocalForks(suite);
    }

    /// A declared beacon whose owner moved is caught by the beacon's checks.
    function testProxyOverTheDeclaredBeaconWithAnotherOwnerIsRefused() external {
        DeploySuite memory suite = liveProxySuite(sBeacon);
        address moved = address(0xC0FFEE);
        vm.prank(OWNER);
        UpgradeableBeacon(sBeacon).transferOwnership(moved);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector, LibRainDeploy.POLYGON, sBeacon, 1, OWNER, moved
            )
        );
        this.externalCheckOnLocalForks(suite);
    }

    /// A proxy that is not live at its derived address on Polygon is refused there.
    function testProxyNotLiveIsRefused() external {
        DeploySuite memory suite = liveProxySuite(sBeacon);
        vm.etch(suite.storedDeployedAddress, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.POLYGON, suite.storedDeployedAddress
            )
        );
        this.externalCheckOnLocalForks(suite);
    }

    /// A per-network proxy over the beacon declared on Polygon passes on Polygon, where it is required.
    function testPerNetworkProxyOverTheDeclaredBeaconPasses() external {
        DeploySuite memory suite = liveProxySuite(sBeacon, true);
        assertEq(uint256(suite.mechanism), uint256(DeployMechanism.BeaconProxyPerNetwork));
        this.externalCheckOnLocalForks(suite);
        assertEq(UpgradeableBeacon(sBeacon).owner(), OWNER);
    }

    /// Required on Arbitrum One too, where no beacon is declared, the per-network proxy is refused naming Arbitrum
    /// One and its beacon.
    function testPerNetworkProxyRequiredWhereItsBeaconIsUndeclaredIsRefused() external {
        DeploySuite memory suite = liveProxySuite(sBeacon, true);
        sRequiredEverywhere = true;
        vm.expectRevert(
            abi.encodeWithSelector(
                BeaconProxyBeaconUndeclared.selector, PROXY_SUITE, LibRainDeploy.ARBITRUM_ONE, sBeacon
            )
        );
        this.externalCheckOnLocalForks(suite);
    }
}
