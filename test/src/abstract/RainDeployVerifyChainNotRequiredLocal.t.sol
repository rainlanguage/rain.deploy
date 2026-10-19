// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain, SuiteRequiredNowhere} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ExampleDeploySuites} from "../../abstract/ExampleDeploySuites.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";
import {
    DEPLOYED_ADDRESS as CONFIG_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as CONFIG_REGISTRY_RUNTIME_CODE
} from "../../../src/generated/candidate/ConfigRegistry.sol";

/// @title RainDeployVerifyChainNotRequiredLocalTest
/// @notice `RainDeployVerifyChainNotRequiredTest` without an RPC: every network
/// forks as the local EVM, where both releases are live until a test removes
/// one.
contract RainDeployVerifyChainNotRequiredLocalTest is ExampleDeploySuites, RainDeployVerifyChain {
    /// The one network the second release is required on, or empty for none.
    string internal sSecondRequiredOn = LibRainDeploy.BASE;

    /// The local fork seam.
    LocalForkVm internal sForkVm;

    /// The second suite's address.
    /// @return The address.
    function secondDeployedAddress() internal pure returns (address) {
        return LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode);
    }

    /// @inheritdoc RainDeploySuitesBase
    /// @dev The second release on `sSecondRequiredOn` alone; everything else
    /// everywhere.
    function requiresSuiteOn(DeploySuite memory suite, string memory network) internal view override returns (bool) {
        return keccak256(bytes(suite.suite)) != keccak256("second-address")
            || keccak256(bytes(network)) == keccak256(bytes(sSecondRequiredOn));
    }

    /// Both releases live.
    function setUp() external {
        sForkVm = new LocalForkVm();
        vm.etch(CONFIG_REGISTRY_DEPLOYED_ADDRESS, CONFIG_REGISTRY_RUNTIME_CODE);
        vm.makePersistent(CONFIG_REGISTRY_DEPLOYED_ADDRESS);
        vm.etch(secondDeployedAddress(), type(MockDeployableV2).runtimeCode);
        vm.makePersistent(secondDeployedAddress());
    }

    /// The released suites, second first so a skip precedes a required suite,
    /// against every supported network on the local seam.
    function checkLocally() external {
        DeploySuite[] memory released = releasedSuites();
        DeploySuite[] memory suites = new DeploySuite[](2);
        suites[0] = released[1];
        suites[1] = released[0];
        checkDeployedOnNetworks(Vm(address(sForkVm)), LibRainDeploy.declaredNetworkConfigs(supportedNetworks()), suites);
    }

    /// The released suites in declared order, so the last suite is the second
    /// release, against every supported network on the local seam.
    function checkLocallyInDeclaredOrder() external {
        checkDeployedOnNetworks(
            Vm(address(sForkVm)), LibRainDeploy.declaredNetworkConfigs(supportedNetworks()), releasedSuites()
        );
    }

    /// The fixture is only meaningful if base is not the first network walked.
    function testBaseIsNotTheFirstSupportedNetwork() external view {
        assertNotEq(supportedNetworks()[0], LibRainDeploy.BASE);
    }

    /// Both releases live where they are required passes.
    function testRequiredWhereLivePasses() external {
        this.checkLocally();
    }

    /// A release required on the first network alone is required somewhere.
    function testRequiredOnTheFirstNetworkAlonePasses() external {
        sSecondRequiredOn = supportedNetworks()[0];
        this.checkLocally();
    }

    /// A release required on the last network alone is required somewhere.
    function testRequiredOnTheLastNetworkAlonePasses() external {
        string[] memory networks = supportedNetworks();
        sSecondRequiredOn = networks[networks.length - 1];
        this.checkLocally();
    }

    /// A release required on no network is refused rather than passed unchecked.
    function testSuiteRequiredNowhereReverts() external {
        sSecondRequiredOn = "";
        vm.expectRevert(abi.encodeWithSelector(SuiteRequiredNowhere.selector, "second-address"));
        this.checkLocally();
    }

    /// The last suite is held to the same floor, and the refusal names it.
    function testSuiteRequiredNowhereRevertsAsTheLastSuite() external {
        sSecondRequiredOn = "";
        vm.expectRevert(abi.encodeWithSelector(SuiteRequiredNowhere.selector, "second-address"));
        this.checkLocallyInDeclaredOrder();
    }

    /// The refusal comes before any network is walked, ahead of a release
    /// absent from the first network.
    function testSuiteRequiredNowherePrecedesTheMatrix() external {
        sSecondRequiredOn = "";
        vm.etch(CONFIG_REGISTRY_DEPLOYED_ADDRESS, hex"");
        vm.expectRevert(abi.encodeWithSelector(SuiteRequiredNowhere.selector, "second-address"));
        this.checkLocally();
    }

    /// The absent release is reported on the one network it is required on.
    function testNotRequiredNetworksAreSkipped() external {
        vm.etch(secondDeployedAddress(), hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.BASE, secondDeployedAddress()
            )
        );
        this.checkLocally();
    }

    /// A suite required everywhere is still checked on the first network.
    function testRequiredSuiteIsStillCheckedEverywhere() external {
        vm.etch(CONFIG_REGISTRY_DEPLOYED_ADDRESS, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NotDeployedOnNetwork.selector,
                LibRainDeploy.ARBITRUM_ONE,
                CONFIG_REGISTRY_DEPLOYED_ADDRESS
            )
        );
        this.checkLocally();
    }
}
