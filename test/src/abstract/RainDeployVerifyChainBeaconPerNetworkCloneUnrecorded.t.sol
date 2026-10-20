// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {CloneNetwork} from "../../../src/lib/LibRainDeployClone.sol";
import {LibRainDeployExtendedNetworks} from "../../../src/lib/LibRainDeployExtendedNetworks.sol";
import {
    PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
    PerNetworkCloneDeploys,
    onlyFirstRecordedNetwork,
    perNetworkCloneInitData,
    perNetworkCloneReleaseAddress
} from "../../abstract/PerNetworkCloneDeploys.sol";
import {
    RainDeployVerifyChainBeaconPerNetworkCloneTestBase
} from "../../abstract/RainDeployVerifyChainBeaconPerNetworkCloneTestBase.sol";
import {LibExtendedNetworksFixture} from "../../lib/LibExtendedNetworksFixture.sol";

/// @title RainDeployVerifyChainBeaconPerNetworkCloneUnrecordedTest
/// @notice A beacon on a network the per-network clone release never recorded, but declares as extended, must
/// point at its init data's clone.
contract RainDeployVerifyChainBeaconPerNetworkCloneUnrecordedTest is
    RainDeployVerifyChainBeaconPerNetworkCloneTestBase
{
    /// The fixture root Polygon's extended networks record is written under.
    string sExtendedRoot;

    /// Records Polygon as an extended network of the release, as the build would.
    constructor() {
        sExtendedRoot = LibExtendedNetworksFixture.freshRoot(
            vm, "fixture-lib/extended-networks", "beacon-per-network-clone-unrecorded", "per-network-clone@0_0_1"
        );
        LibRainDeployExtendedNetworks.writeExtendedNetworks(
            vm, sExtendedRoot, "per-network-clone@0_0_1", extendedNetworks("per-network-clone@0_0_1")
        );
    }

    /// The release, recording Arbitrum One alone.
    /// @return The released suites.
    function releasedSuites()
        internal
        pure
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (DeploySuite[] memory)
    {
        DeploySuite[] memory suites = PerNetworkCloneDeploys.releasedSuites();
        suites[0] = onlyFirstRecordedNetwork(suites[0]);
        return suites;
    }

    /// Polygon at the address it derives under its init data.
    /// @param suite The release's suite key.
    /// @return The networks.
    function extendedNetworks(string memory suite) internal pure override returns (CloneNetwork[] memory) {
        if (keccak256(bytes(suite)) != keccak256("per-network-clone@0_0_1")) {
            return new CloneNetwork[](0);
        }
        CloneNetwork[] memory networks = new CloneNetwork[](1);
        networks[0] = CloneNetwork({
            chainId: PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
            data: perNetworkCloneInitData(PER_NETWORK_CLONE_POLYGON_CHAIN_ID),
            deployedAddress: perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID)
        });
        return networks;
    }

    /// @inheritdoc RainDeploySuitesBase
    function extendedNetworksRoot() internal view override returns (string memory) {
        return sExtendedRoot;
    }
}
