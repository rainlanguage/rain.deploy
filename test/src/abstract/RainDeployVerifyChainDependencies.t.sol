// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {DeployDependency, LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    PER_NETWORK_CLONE_POLYGON_CHAIN_ID,
    PerNetworkCloneDeploys,
    perNetworkCloneReleaseAddress
} from "../../abstract/PerNetworkCloneDeploys.sol";
import {exampleCloneImplementation} from "../../abstract/ExampleCloneDeploys.sol";
import {LibRainDeployMechanism} from "../../../src/lib/LibRainDeployMechanism.sol";
import {MockCloneFactory} from "../../concrete/MockCloneFactory.sol";
import {MockCloneable} from "../../concrete/MockCloneable.sol";

/// @title RainDeployVerifyChainDependenciesTest
/// @notice The chain matrix holds every released suite's declared dependencies to the code declared
/// for them on each network, before the suite's own address.
contract RainDeployVerifyChainDependenciesTest is PerNetworkCloneDeploys, RainDeployVerifyChain {
    /// Polygon's native token system contract.
    address constant POLYGON_SYSTEM_CONTRACT = 0x0000000000000000000000000000000000001010;

    /// @inheritdoc RainDeploySuitesBase
    function supportedNetworks()
        internal
        pure
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory)
    {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.POLYGON;
        networks[1] = LibRainDeploy.ARBITRUM_ONE;
        return networks;
    }

    /// Puts the release's dependencies, and its clone at its address for each network, on every
    /// fork.
    function setUp() external {
        DeploySuite memory release = releasedSuites()[0];
        for (uint256 i = 0; i < release.dependencies.length; i++) {
            vm.etch(release.dependencies[i].deployedAddress, release.dependencies[i].runtimeCode);
            vm.makePersistent(release.dependencies[i].deployedAddress);
        }
        address[] memory addresses = LibRainDeployMechanism.deployedAddresses(release);
        for (uint256 i = 0; i < addresses.length; i++) {
            vm.etch(addresses[i], release.storedRuntimeCode);
            vm.makePersistent(addresses[i]);
        }
    }

    /// External wrapper for `checkDeployedOnSupportedNetworks`.
    /// @param suites The suites to check.
    function externalCheckDeployedOnSupportedNetworks(DeploySuite[] memory suites) external {
        checkDeployedOnSupportedNetworks(suites);
    }

    /// The release with one more declared dependency.
    /// @param dependency The dependency to add.
    /// @return The release, as the one suite to check.
    function releaseDeclaring(DeployDependency memory dependency) internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = releasedSuites()[0];
        DeployDependency[] memory dependencies = new DeployDependency[](suites[0].dependencies.length + 1);
        for (uint256 i = 0; i < suites[0].dependencies.length; i++) {
            dependencies[i] = suites[0].dependencies[i];
        }
        dependencies[dependencies.length - 1] = dependency;
        suites[0].dependencies = dependencies;
        return suites;
    }

    /// Polygon's system contract code, read from Polygon.
    /// @return The code.
    function polygonSystemContractCode() internal returns (bytes memory) {
        vm.createSelectFork(LibRainDeploy.POLYGON);
        bytes memory code = POLYGON_SYSTEM_CONTRACT.code;
        assertGt(code.length, 0, "Polygon's system contract");
        return code;
    }

    /// Without the implementation the matrix refuses on the first network, naming it as the missing
    /// dependency, though the clone is at its address.
    function testMissingImplementationIsRefusedNamingNetworkAndDependency() external {
        vm.etch(exampleCloneImplementation(), hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.POLYGON, exampleCloneImplementation()
            )
        );
        this.testSuitesLiveOnEverySupportedNetwork();
    }

    /// With other code at the implementation's address the matrix refuses on the first network,
    /// naming the dependency and both code hashes.
    function testChangedImplementationIsRefusedNamingNetworkAndDependency() external {
        vm.etch(exampleCloneImplementation(), type(MockCloneFactory).runtimeCode);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.DependencyChanged.selector,
                LibRainDeploy.POLYGON,
                exampleCloneImplementation(),
                keccak256(type(MockCloneable).runtimeCode),
                keccak256(type(MockCloneFactory).runtimeCode)
            )
        );
        this.testSuitesLiveOnEverySupportedNetwork();
    }

    /// A dependency on Polygon with the declared code and absent from Arbitrum One passes Polygon
    /// and is refused on Arbitrum One.
    function testDependencyAbsentFromOneNetworkIsRefusedOnThatNetwork() external {
        DeploySuite[] memory suites = releaseDeclaring(
            DeployDependency({deployedAddress: POLYGON_SYSTEM_CONTRACT, runtimeCode: polygonSystemContractCode()})
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, POLYGON_SYSTEM_CONTRACT
            )
        );
        this.externalCheckDeployedOnSupportedNetworks(suites);
    }

    /// A dependency declared with code other than Polygon's is refused on Polygon, naming the
    /// dependency, the declared hash and Polygon's.
    function testDependencyWithOtherCodeOnOneNetworkIsRefusedOnThatNetwork() external {
        bytes memory actual = polygonSystemContractCode();
        DeploySuite[] memory suites = releaseDeclaring(
            DeployDependency({deployedAddress: POLYGON_SYSTEM_CONTRACT, runtimeCode: type(MockCloneable).runtimeCode})
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.DependencyChanged.selector,
                LibRainDeploy.POLYGON,
                POLYGON_SYSTEM_CONTRACT,
                keccak256(type(MockCloneable).runtimeCode),
                keccak256(actual)
            )
        );
        this.externalCheckDeployedOnSupportedNetworks(suites);
    }

    /// With two suites, a dependency only the SECOND declares, absent from Arbitrum One, is refused
    /// on Arbitrum One naming it.
    function testSecondSuitesDependencyAbsentFromOneNetworkIsRefusedNamingThatNetworkAndDependency() external {
        DeploySuite[] memory suites = new DeploySuite[](2);
        suites[0] = releasedSuites()[0];
        suites[1] = releaseDeclaring(
            DeployDependency({deployedAddress: POLYGON_SYSTEM_CONTRACT, runtimeCode: polygonSystemContractCode()})
        )[0];
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, POLYGON_SYSTEM_CONTRACT
            )
        );
        this.externalCheckDeployedOnSupportedNetworks(suites);
    }

    /// With only its clone gone from Polygon, the first network checked, the suite is refused as
    /// not deployed there.
    function testCloneGoneFromOneNetworkIsRefusedAsNotDeployedThere() external {
        address polygonAddress = perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID);
        vm.etch(polygonAddress, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.POLYGON, polygonAddress)
        );
        this.externalCheckDeployedOnSupportedNetworks(releasedSuites());
    }

    /// On a network where the suite's dependency AND its address both fail, the dependency is the
    /// refusal.
    function testDependencyRefusalPrecedesTheAddressRefusalOnOneNetwork() external {
        vm.etch(perNetworkCloneReleaseAddress(PER_NETWORK_CLONE_POLYGON_CHAIN_ID), hex"");
        vm.etch(exampleCloneImplementation(), hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.POLYGON, exampleCloneImplementation()
            )
        );
        this.externalCheckDeployedOnSupportedNetworks(releasedSuites());
    }
}
