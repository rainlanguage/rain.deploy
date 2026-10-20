// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {DeployDependency, LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {ExampleCloneDeploys} from "../../abstract/ExampleCloneDeploys.sol";
import {CloneTarget} from "../../../src/lib/LibRainDeployClone.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";

/// @title RainDeployVerifyChainCloneTest
/// @notice The chain matrix over a clone deploy repo's frozen release.
contract RainDeployVerifyChainCloneTest is ExampleCloneDeploys, RainDeployVerifyChain {
    /// Puts the release's dependencies, and its clone at its address, on every fork.
    function setUp() external {
        DeploySuite memory release = releasedSuites()[0];
        for (uint256 i = 0; i < release.dependencies.length; i++) {
            vm.etch(release.dependencies[i].deployedAddress, release.dependencies[i].runtimeCode);
            vm.makePersistent(release.dependencies[i].deployedAddress);
        }
        vm.etch(release.storedDeployedAddress, release.storedRuntimeCode);
        vm.makePersistent(release.storedDeployedAddress);
    }

    /// Without the clone at its address the matrix refuses on the first network, naming the release
    /// and the CLONE address — not the Zoltu address of its creation code, and not a candidate's.
    function testCloneReleaseMissingFromANetworkIsRefusedAtTheCloneAddress() external {
        DeploySuite memory release = releasedSuites()[0];
        assertNotEq(release.storedDeployedAddress, LibRainDeploy.zoltuAddress(release.creationCode));
        vm.etch(release.storedDeployedAddress, hex"");

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NotDeployedOnNetwork.selector, supportedNetworks()[0], release.storedDeployedAddress
            )
        );
        this.testSuitesLiveOnEverySupportedNetwork();
    }

    /// The matrix on local forks.
    /// @param forkVm The local fork Vm.
    function externalCheckOnLocalForks(LocalForkVm forkVm) external {
        checkDeployedOnNetworks(
            Vm(address(forkVm)), LibRainDeploy.declaredNetworkConfigs(supportedNetworks()), releasedSuites()
        );
    }

    /// A clone whose proxy code is right MUST still be refused when its implementation is missing.
    function testMatrixRefusesCloneWithMissingImplementation() external {
        address implementation = abi.decode(releasedSuites()[0].mechanismData, (CloneTarget)).implementation;
        LocalForkVm forkVm = new LocalForkVm();
        vm.etch(implementation, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.MissingDependency.selector, supportedNetworks()[0], implementation)
        );
        this.externalCheckOnLocalForks(forkVm);
    }

    /// A fork reporting another chain than its catalogue entry MUST be refused, even when every suite is live on it.
    function testMatrixRefusesForkReportingAnotherChain() external {
        LocalForkVm forkVm = new LocalForkVm();
        SupportedNetwork memory network = LibRainDeploy.declaredNetworkConfigs(supportedNetworks())[0];
        forkVm.setReportedChainId(network.chainId + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NetworkChainIdMismatch.selector, network.name, network.chainId, network.chainId + 1
            )
        );
        this.externalCheckOnLocalForks(forkVm);
    }

    /// Every suite live on local forks passes the matrix.
    function testMatrixPassesLiveSuitesOnLocalForks() external {
        this.externalCheckOnLocalForks(new LocalForkVm());
    }

    /// A clone address holding other code MUST be refused on a local fork.
    function testMatrixRefusesCloneWithOtherCode() external {
        DeploySuite memory suite = releasedSuites()[0];
        LocalForkVm forkVm = new LocalForkVm();
        vm.etch(suite.storedDeployedAddress, hex"00");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.CodeHashMismatchOnNetwork.selector,
                supportedNetworks()[0],
                suite.storedDeployedAddress,
                suite.storedBytecodeHash,
                keccak256(hex"00")
            )
        );
        this.externalCheckOnLocalForks(forkVm);
    }

    /// A clone address with no code MUST be refused on a local fork.
    function testMatrixRefusesMissingClone() external {
        DeploySuite memory suite = releasedSuites()[0];
        LocalForkVm forkVm = new LocalForkVm();
        vm.etch(suite.storedDeployedAddress, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.NotDeployedOnNetwork.selector, supportedNetworks()[0], suite.storedDeployedAddress
            )
        );
        this.externalCheckOnLocalForks(forkVm);
    }

    /// A dependency only the SECOND suite declares, with no code on the first network, is refused there naming it.
    function testMatrixRefusesALaterSuitesMissingDependency() external {
        address missing = address(0xdEaD);
        assertEq(missing.code.length, 0);
        DeploySuite[] memory suites = new DeploySuite[](2);
        suites[0] = releasedSuites()[0];
        suites[1] = releasedSuites()[0];
        DeployDependency[] memory dependencies = new DeployDependency[](suites[1].dependencies.length + 1);
        for (uint256 i = 0; i < suites[1].dependencies.length; i++) {
            dependencies[i] = suites[1].dependencies[i];
        }
        dependencies[dependencies.length - 1] = DeployDependency({deployedAddress: missing, runtimeCode: hex"6001"});
        suites[1].dependencies = dependencies;
        LocalForkVm forkVm = new LocalForkVm();
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.MissingDependency.selector, supportedNetworks()[0], missing)
        );
        this.externalCheckSuitesOnLocalForks(forkVm, suites);
    }

    /// The matrix on local forks over the given suites.
    /// @param forkVm The local fork Vm.
    /// @param suites The suites to check.
    function externalCheckSuitesOnLocalForks(LocalForkVm forkVm, DeploySuite[] memory suites) external {
        checkDeployedOnNetworks(Vm(address(forkVm)), LibRainDeploy.declaredNetworkConfigs(supportedNetworks()), suites);
    }
}
