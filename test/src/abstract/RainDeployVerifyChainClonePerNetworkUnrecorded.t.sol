// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {ICloneableFactoryV4} from "rain-factory-0.2.6/src/interface/deprecated/ICloneableFactoryV4.sol";
import {RainDeployVerifyChain, SuiteRequiredNowhere} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {ExtendedNetworkUnfrozen} from "../../../src/lib/LibRainDeployMechanism.sol";
import {CloneNetworks, LibRainDeployClone} from "../../../src/lib/LibRainDeployClone.sol";
import {
    PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID,
    PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
    PerNetworkCloneDeploys,
    etchPerNetworkCloneRelease,
    onlyFirstRecordedNetworkSuites,
    perNetworkCloneReleaseAddress,
    perNetworkCloneReleaseAddresses
} from "../../abstract/PerNetworkCloneDeploys.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";

/// Thrown by the test's `requiresSuiteOn` when asked about a suite on a network it refuses to be asked about.
/// @param suite The suite asked about.
/// @param network The network asked about.
error RequiresSuiteOnAsked(string suite, string network);

/// @title RainDeployVerifyChainClonePerNetworkUnrecordedTest
/// @notice The chain matrix over a per-network clone release cut when the repo supported Arbitrum
/// One alone, in a repo that now supports Polygon too.
contract RainDeployVerifyChainClonePerNetworkUnrecordedTest is PerNetworkCloneDeploys, RainDeployVerifyChain {
    /// Whether the release is required on no network.
    bool internal sRequiredNowhere;

    /// Whether the release is not required on Polygon.
    bool internal sNotRequiredOnPolygon;

    /// Whether the suite other than the release is required on no network.
    bool internal sOtherRequiredNowhere;

    /// Whether asking if the release is required on Polygon reverts.
    bool internal sReleaseOnPolygonReverts;

    /// @inheritdoc RainDeploySuitesBase
    function requiresSuiteOn(DeploySuite memory suite, string memory network) internal view override returns (bool) {
        if (
            sReleaseOnPolygonReverts && keccak256(bytes(suite.suite)) == keccak256(bytes("per-network-clone@0_0_1"))
                && keccak256(bytes(network)) == keccak256(bytes(LibRainDeploy.POLYGON))
        ) {
            revert RequiresSuiteOnAsked(suite.suite, network);
        }
        return !sRequiredNowhere
            && !(sOtherRequiredNowhere && keccak256(bytes(suite.suite)) == keccak256(bytes("other-clone@0_0_1")))
            && !(sNotRequiredOnPolygon && keccak256(bytes(network)) == keccak256(bytes(LibRainDeploy.POLYGON)));
    }

    /// @inheritdoc PerNetworkCloneDeploys
    function supportedNetworks()
        internal
        view
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        return PerNetworkCloneDeploys.supportedNetworks();
    }

    /// Puts the release's dependencies, and its clone at the address for each network, on every
    /// fork.
    function setUp() external {
        etchPerNetworkCloneRelease(vm, releasedSuites()[0], perNetworkCloneReleaseAddresses());
    }

    /// External wrapper for `checkDeployedOnNetworks`.
    /// @param networks The networks to check on.
    /// @param suites The suites to check.
    function externalCheckDeployedOnNetworks(SupportedNetwork[] memory networks, DeploySuite[] memory suites) external {
        checkDeployedOnNetworks(networks, suites);
    }

    /// `checkDeployedOnNetworks` over every supported network on local forks.
    /// @param suites The suites to check.
    function externalCheckOnLocalForks(DeploySuite[] memory suites) external {
        checkDeployedOnNetworks(
            Vm(address(new LocalForkVm())), LibRainDeploy.declaredNetworkConfigs(supportedNetworks()), suites
        );
    }

    /// External wrapper for `checkDeployedOnSupportedNetworks`.
    /// @param suites The suites to check.
    function externalCheckDeployedOnSupportedNetworks(DeploySuite[] memory suites) external {
        checkDeployedOnSupportedNetworks(suites);
    }

    /// The release, recording Arbitrum One alone.
    /// @return It, as the one suite to check.
    function arbitrumOnlyRelease() internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = onlyFirstRecordedNetworkSuites(releasedSuites()[0]);
        CloneNetworks memory clones = abi.decode(suites[0].mechanismData, (CloneNetworks));
        assertEq(clones.networks.length, 1);
        assertEq(clones.networks[0].chainId, PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        assertEq(
            clones.networks[0].deployedAddress, perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID)
        );
        return suites;
    }

    /// The release is refused on Polygon as unfrozen, naming the Polygon init data's address, whether
    /// its clone is there or that address is empty: the frozen check runs before the code check.
    function testUnrecordedNetworkIsRefusedAsUnfrozenWhetherOrNotItsCloneIsLive() external {
        DeploySuite[] memory suites = arbitrumOnlyRelease();
        address polygonAddress = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkUnfrozen.selector, "per-network-clone@0_0_1", LibRainDeploy.POLYGON, polygonAddress
            )
        );
        this.externalCheckDeployedOnSupportedNetworks(suites);

        vm.etch(polygonAddress, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkUnfrozen.selector, "per-network-clone@0_0_1", LibRainDeploy.POLYGON, polygonAddress
            )
        );
        this.externalCheckDeployedOnSupportedNetworks(suites);
    }

    /// The recorded network, checked alone, is still checked at its recorded address.
    function testRecordedNetworkIsStillCheckedAtItsRecordedAddress() external {
        DeploySuite[] memory suites = arbitrumOnlyRelease();
        address arbitrumAddress = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        vm.etch(arbitrumAddress, hex"");
        string[] memory arbitrum = new string[](1);
        arbitrum[0] = LibRainDeploy.ARBITRUM_ONE;
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.ARBITRUM_ONE, arbitrumAddress
            )
        );
        this.externalCheckDeployedOnNetworks(LibRainDeploy.declaredNetworkConfigs(arbitrum), suites);
    }

    /// A release no candidate is named by takes no network from one.
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

    /// An unrecorded network the release does not declare is refused as unfrozen before any network is forked or any
    /// suite is derived.
    function testUnrecordedNetworkIsRefusedAsUnfrozenBeforeAnyFork() external {
        DeploySuite[] memory suites = arbitrumOnlyRelease();
        address factory = abi.decode(suites[0].mechanismData, (CloneNetworks)).factory;
        vm.expectCall(factory, abi.encodeWithSelector(ICloneableFactoryV4.cloneDeterministicOpenSalt.selector), 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                ExtendedNetworkUnfrozen.selector,
                "per-network-clone@0_0_1",
                LibRainDeploy.POLYGON,
                perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID)
            )
        );
        this.externalCheckDeployedOnSupportedNetworks(suites);

        (bool forked,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(0)));
        assertFalse(forked, "the matrix forked a network before refusing the unfrozen one");
    }

    /// A release required nowhere is refused as such before its unrecorded network is refused as unfrozen, and so is a
    /// suite required nowhere checked after a release required on its unrecorded network.
    function testSuiteRequiredNowherePrecedesTheFrozenCheck() external {
        sRequiredNowhere = true;
        vm.expectRevert(abi.encodeWithSelector(SuiteRequiredNowhere.selector, "per-network-clone@0_0_1"));
        this.externalCheckDeployedOnSupportedNetworks(arbitrumOnlyRelease());

        sRequiredNowhere = false;
        sOtherRequiredNowhere = true;
        DeploySuite[] memory suites = new DeploySuite[](2);
        suites[0] = arbitrumOnlyRelease()[0];
        suites[1] = arbitrumOnlyRelease()[0];
        suites[1].suite = "other-clone@0_0_1";
        vm.expectRevert(abi.encodeWithSelector(SuiteRequiredNowhere.selector, "other-clone@0_0_1"));
        this.externalCheckDeployedOnSupportedNetworks(suites);
    }

    /// The required-nowhere scan asks no further about a suite once a network requires it: a later suite required
    /// nowhere is refused as such, not with what asking about the release on Polygon, after Arbitrum One, would throw.
    function testSuiteRequiredNowhereScanStopsAtTheFirstRequiringNetwork() external {
        sOtherRequiredNowhere = true;
        sReleaseOnPolygonReverts = true;
        DeploySuite[] memory suites = new DeploySuite[](2);
        suites[0] = arbitrumOnlyRelease()[0];
        suites[1] = arbitrumOnlyRelease()[0];
        suites[1].suite = "other-clone@0_0_1";
        vm.expectRevert(abi.encodeWithSelector(SuiteRequiredNowhere.selector, "other-clone@0_0_1"));
        this.externalCheckDeployedOnSupportedNetworks(suites);

        sOtherRequiredNowhere = false;
        vm.expectRevert(
            abi.encodeWithSelector(RequiresSuiteOnAsked.selector, "per-network-clone@0_0_1", LibRainDeploy.POLYGON)
        );
        this.externalCheckDeployedOnSupportedNetworks(suites);
    }

    /// A release required nowhere is refused as such before an address is derived on a network its candidate has no
    /// entry for.
    function testSuiteRequiredNowherePrecedesTheAddressDerivation() external {
        sRequiredNowhere = true;
        DeploySuite[] memory suites = arbitrumOnlyRelease();
        suites[0].suite = "other-clone@0_0_1";
        vm.expectRevert(abi.encodeWithSelector(SuiteRequiredNowhere.selector, "other-clone@0_0_1"));
        this.externalCheckDeployedOnSupportedNetworks(suites);
    }

    /// A release not required on its unrecorded network is not refused there as unfrozen, and passes where it is
    /// required and live.
    function testUnrecordedNetworkNotRequiredIsNotRefusedAsUnfrozen() external {
        sNotRequiredOnPolygon = true;
        this.externalCheckOnLocalForks(arbitrumOnlyRelease());
    }

    /// A release not required on its unrecorded network is still checked where it is required.
    function testUnrecordedNetworkNotRequiredLeavesTheRecordedNetworkChecked() external {
        sNotRequiredOnPolygon = true;
        address arbitrumAddress = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_ARBITRUM_ONE_CHAIN_ID);
        vm.etch(arbitrumAddress, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.ARBITRUM_ONE, arbitrumAddress
            )
        );
        this.externalCheckOnLocalForks(arbitrumOnlyRelease());
    }
}
