// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {CloneDeploy, CloneNetwork, CloneTarget, LibRainDeployClone} from "../../../src/lib/LibRainDeployClone.sol";
import {
    ExtendedNetworksUnrecorded,
    LibRainDeployExtendedNetworks
} from "../../../src/lib/LibRainDeployExtendedNetworks.sol";
import {ExtendedNetworkAddressMismatch, ExtendedNetworkUnfrozen} from "../../../src/lib/LibRainDeployMechanism.sol";
import {
    PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID,
    PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
    PerNetworkCloneDeploys,
    onlyFirstRecordedNetwork,
    perNetworkClone,
    perNetworkCloneInitData,
    perNetworkCloneRelease,
    perNetworkCloneReleaseAddress
} from "../../abstract/PerNetworkCloneDeploys.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";

/// @dev Polygon's admin after the candidate moved it.
address constant MOVED_POLYGON_ADMIN = address(0xC4c4c4C4C4c4C4c4c4C4c4c4c4c4c4C4c4c4c4C4);

/// The per-network init data with Polygon's admin moved.
/// @param chainId The network's chain id.
/// @return The init data on that network.
function movedInitData(uint256 chainId) pure returns (bytes memory) {
    if (chainId == PER_NETWORK_CLONE_POLYGON_CHAIN_ID) {
        return abi.encode(MOVED_POLYGON_ADMIN);
    }
    return perNetworkCloneInitData(chainId);
}

/// The address the release derives on Polygon at the moved init data.
/// @return The address.
function movedReleaseAddress() pure returns (address) {
    CloneDeploy memory release = perNetworkCloneRelease();
    return LibRainDeployClone.cloneDeployedAddress(
        CloneTarget({
            factory: release.factory,
            implementation: release.implementation,
            data: movedInitData(PER_NETWORK_CLONE_POLYGON_CHAIN_ID),
            salt: release.salt
        })
    );
}

/// @title RainDeployVerifyChainClonePerNetworkExtendedTest
/// @notice The chain matrix, on local forks, over a per-network release recording Arbitrum One alone that was
/// broadcast to Polygon after its cut, in a repo whose candidate has since moved Polygon's init data.
contract RainDeployVerifyChainClonePerNetworkExtendedTest is PerNetworkCloneDeploys, RainDeployVerifyChain {
    /// Whether `extendedNetworks` declares Polygon.
    bool internal sFrozen;

    /// The address `extendedNetworks` declares for Polygon.
    address internal sFrozenAddress;

    /// The fork cheatcodes the matrix runs against.
    LocalForkVm internal sForkVm;

    /// The record root the extended networks record is read from: one nothing writes to until `record` names
    /// another.
    string internal sExtendedRoot = "fixture-lib/extended-networks/verify-extended-none";

    /// @inheritdoc PerNetworkCloneDeploys
    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return PerNetworkCloneDeploys.supportedNetworks();
    }

    /// The candidate, with Polygon's init data moved.
    /// @return The candidate's declaration.
    function cloneDeploys() internal pure override returns (CloneDeploy[] memory) {
        CloneDeploy[] memory clones = new CloneDeploy[](1);
        clones[0] = perNetworkClone("per-network-clone", bytes32(uint256(4)));
        clones[0].initData = movedInitData;
        return clones;
    }

    /// Polygon at its original init data, as it was broadcast, once `sFrozen` is set.
    /// @param suite The release's suite key.
    /// @return The networks.
    function extendedNetworks(string memory suite) internal view override returns (CloneNetwork[] memory) {
        if (!sFrozen || keccak256(bytes(suite)) != keccak256("per-network-clone@0_0_1")) {
            return new CloneNetwork[](0);
        }
        CloneNetwork[] memory networks = new CloneNetwork[](1);
        networks[0] = CloneNetwork({
            chainId: PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
            data: perNetworkCloneInitData(PER_NETWORK_CLONE_POLYGON_CHAIN_ID),
            deployedAddress: sFrozenAddress
        });
        return networks;
    }

    /// @inheritdoc RainDeploySuitesBase
    function extendedNetworksRoot() internal view override returns (string memory) {
        return sExtendedRoot;
    }

    /// Records what `extendedNetworks` now declares, as the build would, under a fixture root of its own after
    /// removing whatever an earlier run left there.
    /// @param label The fixture root's directory under `fixture-lib/extended-networks`, one per test.
    function record(string memory label) internal {
        sExtendedRoot = string.concat("fixture-lib/extended-networks/", label);
        (,, string memory path) =
            LibRainDeployExtendedNetworks.extendedNetworksPath(sExtendedRoot, "per-network-clone@0_0_1");
        if (vm.exists(path)) {
            vm.removeFile(path);
        }
        LibRainDeployExtendedNetworks.writeExtendedNetworks(
            vm, sExtendedRoot, "per-network-clone@0_0_1", extendedNetworks("per-network-clone@0_0_1")
        );
    }

    /// Puts the release's dependencies, and its clone at its original address on each network, on every fork.
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
        sFrozenAddress = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        sForkVm = new LocalForkVm();
    }

    /// The matrix on local forks, over the release recording Arbitrum One alone.
    function externalCheckOnLocalForks() external {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = onlyFirstRecordedNetwork(releasedSuites()[0]);
        checkDeployedOnNetworks(Vm(address(sForkVm)), LibRainDeploy.declaredNetworkConfigs(supportedNetworks()), suites);
    }

    /// Unfrozen, Polygon takes the candidate's moved init data and is refused as unfrozen, naming the address, whether
    /// or not a clone is live there: nothing is at the moved address while the release is live at its broadcast one.
    function testUnfrozenNetworkLiveAtTheCandidatesDataIsRefused() external {
        address moved = movedReleaseAddress();
        assertNotEq(moved, sFrozenAddress);
        assertEq(moved.code.length, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkUnfrozen.selector, "per-network-clone@0_0_1", LibRainDeploy.POLYGON, moved
            )
        );
        this.externalCheckOnLocalForks();

        vm.etch(moved, releasedSuites()[0].storedRuntimeCode);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkUnfrozen.selector, "per-network-clone@0_0_1", LibRainDeploy.POLYGON, moved
            )
        );
        this.externalCheckOnLocalForks();
    }

    /// The matrix on local forks over Polygon alone, over the release recording Arbitrum One alone.
    function externalCheckPolygonOnLocalForks() external {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = onlyFirstRecordedNetwork(releasedSuites()[0]);
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.POLYGON;
        checkDeployedOnNetworks(Vm(address(sForkVm)), LibRainDeploy.declaredNetworkConfigs(networks), suites);
    }

    /// Unfrozen, Polygon is refused as unfrozen even when a dependency is missing there: what the network lacks is a
    /// declaration, and the dependency check would describe a release the matrix cannot place on it.
    function testUnfrozenNetworkMissingADependencyIsRefusedAsUnfrozen() external {
        DeploySuite memory release = releasedSuites()[0];
        assertGt(release.dependencies.length, 0);
        vm.etch(release.dependencies[0].deployedAddress, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkUnfrozen.selector,
                "per-network-clone@0_0_1",
                LibRainDeploy.POLYGON,
                movedReleaseAddress()
            )
        );
        this.externalCheckPolygonOnLocalForks();
    }

    /// Frozen, Polygon is checked at the address it was broadcast to, whatever the candidate's init data now is.
    function testFrozenNetworkIsCheckedAtItsFrozenAddress() external {
        sFrozen = true;
        record("verify-extended-frozen");
        this.externalCheckOnLocalForks();

        vm.etch(sFrozenAddress, hex"");
        vm.etch(movedReleaseAddress(), releasedSuites()[0].storedRuntimeCode);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.POLYGON, sFrozenAddress)
        );
        this.externalCheckOnLocalForks();
    }

    /// A declared network the release's extended networks record does not hold is refused before any fork.
    function testDeclaredNetworkWithoutARecordIsRefused() external {
        sFrozen = true;
        vm.expectCall(address(sForkVm), abi.encodeWithSelector(LocalForkVm.createFork.selector), 0);
        vm.expectRevert(abi.encodeWithSelector(ExtendedNetworksUnrecorded.selector, "per-network-clone@0_0_1"));
        this.externalCheckOnLocalForks();
    }

    /// A frozen network whose address its init data does not derive is refused before any fork.
    function testFrozenNetworkAtAnotherAddressIsRefused() external {
        sFrozen = true;
        address derived = sFrozenAddress;
        sFrozenAddress = movedReleaseAddress();
        record("verify-extended-misdeclared");
        vm.expectCall(address(sForkVm), abi.encodeWithSelector(LocalForkVm.createFork.selector), 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkAddressMismatch.selector,
                "per-network-clone@0_0_1",
                PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
                derived,
                sFrozenAddress
            )
        );
        this.externalCheckOnLocalForks();
    }
}
