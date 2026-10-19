// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {CloneDeploy, CloneNetwork, CloneTarget, LibRainDeployClone} from "../../../src/lib/LibRainDeployClone.sol";
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
    }

    /// The matrix on local forks, over the release recording Arbitrum One alone.
    function externalCheckOnLocalForks() external {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = onlyFirstRecordedNetwork(releasedSuites()[0]);
        checkDeployedOnNetworks(
            Vm(address(new LocalForkVm())), LibRainDeploy.declaredNetworkConfigs(supportedNetworks()), suites
        );
    }

    /// Unfrozen, Polygon takes the candidate's moved init data, and once a clone is live there it is refused as
    /// unfrozen, naming the address.
    function testUnfrozenNetworkLiveAtTheCandidatesDataIsRefused() external {
        address moved = movedReleaseAddress();
        assertNotEq(moved, sFrozenAddress);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.POLYGON, moved)
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

    /// Frozen, Polygon is checked at the address it was broadcast to, whatever the candidate's init data now is.
    function testFrozenNetworkIsCheckedAtItsFrozenAddress() external {
        sFrozen = true;
        this.externalCheckOnLocalForks();

        vm.etch(sFrozenAddress, hex"");
        vm.etch(movedReleaseAddress(), releasedSuites()[0].storedRuntimeCode);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.POLYGON, sFrozenAddress)
        );
        this.externalCheckOnLocalForks();
    }

    /// A frozen network whose address its init data does not derive is refused before any fork.
    function testFrozenNetworkAtAnotherAddressIsRefused() external {
        sFrozen = true;
        address derived = sFrozenAddress;
        sFrozenAddress = movedReleaseAddress();
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
