// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
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
/// forks as the local EVM, where the first release is live and the second is
/// absent.
contract RainDeployVerifyChainNotRequiredLocalTest is ExampleDeploySuites, RainDeployVerifyChain {
    /// Whether the second release is required on base.
    bool internal sSecondRequiredOnBase;

    /// The local fork seam.
    LocalForkVm internal sForkVm;

    /// The second suite's address.
    /// @return The address.
    function secondDeployedAddress() internal pure returns (address) {
        return LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode);
    }

    /// @inheritdoc RainDeploySuitesBase
    /// @dev The second release on base only when `sSecondRequiredOnBase`, and
    /// nowhere otherwise; everything else everywhere.
    function requiresSuiteOn(DeploySuite memory suite, string memory network) internal view override returns (bool) {
        return keccak256(bytes(suite.suite)) != keccak256("second-address")
            || (sSecondRequiredOnBase && keccak256(bytes(network)) == keccak256(bytes(LibRainDeploy.BASE)));
    }

    /// The first release live and the second absent.
    function setUp() external {
        sForkVm = new LocalForkVm();
        vm.etch(CONFIG_REGISTRY_DEPLOYED_ADDRESS, CONFIG_REGISTRY_RUNTIME_CODE);
        vm.etch(secondDeployedAddress(), hex"");
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

    /// The fixture is only meaningful if base is not the first network walked.
    function testBaseIsNotTheFirstSupportedNetwork() external view {
        assertNotEq(supportedNetworks()[0], LibRainDeploy.BASE);
    }

    /// An absent release required nowhere passes.
    function testNotRequiredEverywherePasses() external {
        this.checkLocally();
    }

    /// The absent release is reported on the one network it is required on.
    function testNotRequiredNetworksAreSkipped() external {
        sSecondRequiredOnBase = true;
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
