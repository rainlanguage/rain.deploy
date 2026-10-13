// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {DeployDependency, LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {PerNetworkCloneDeploys} from "../../abstract/PerNetworkCloneDeploys.sol";
import {exampleCloneImplementation} from "../../abstract/ExampleCloneDeploys.sol";
import {LibRainDeployMechanism} from "../../../src/lib/LibRainDeployMechanism.sol";
import {MockCloneFactory} from "../../concrete/MockCloneFactory.sol";
import {MockCloneable} from "../../concrete/MockCloneable.sol";

/// @title RainDeployVerifyChainDependenciesTest
/// @notice The chain matrix holds every released suite's declared dependencies
/// to the code declared for them on each network, before the suite's own
/// address: a clone at its address over a missing or changed implementation
/// has the right code hash and does not work.
///
/// Polygon is checked before Arbitrum One here, so a dependency that is on
/// Polygon and not on Arbitrum One is refused on the SECOND network checked:
/// Polygon's native token system contract, which Polygon has at
/// `POLYGON_SYSTEM_CONTRACT` and Arbitrum One does not. Its code is read from
/// Polygon by the test, so the declaration matches the chain wherever the chain
/// is.
contract RainDeployVerifyChainDependenciesTest is PerNetworkCloneDeploys, RainDeployVerifyChain {
    /// Polygon's native token system contract.
    address constant POLYGON_SYSTEM_CONTRACT = 0x0000000000000000000000000000000000001010;

    /// @inheritdoc RainDeploySuitesBase
    /// @dev Polygon, then Arbitrum One.
    function supportedNetworks()
        internal
        pure
        override(PerNetworkCloneDeploys, RainDeploySuitesBase)
        returns (string[] memory networks)
    {
        networks = new string[](2);
        networks[0] = LibRainDeploy.POLYGON;
        networks[1] = LibRainDeploy.ARBITRUM_ONE;
    }

    /// Puts the release's dependencies, and its clone at its address for each
    /// network, on every fork.
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
    /// @return suites The release, as the one suite to check.
    function releaseDeclaring(DeployDependency memory dependency) internal pure returns (DeploySuite[] memory suites) {
        suites = new DeploySuite[](1);
        suites[0] = releasedSuites()[0];
        DeployDependency[] memory dependencies = new DeployDependency[](suites[0].dependencies.length + 1);
        for (uint256 i = 0; i < suites[0].dependencies.length; i++) {
            dependencies[i] = suites[0].dependencies[i];
        }
        dependencies[dependencies.length - 1] = dependency;
        suites[0].dependencies = dependencies;
    }

    /// Polygon's system contract code, read from Polygon.
    /// @return code The code.
    function polygonSystemContractCode() internal returns (bytes memory code) {
        vm.createSelectFork(LibRainDeploy.POLYGON);
        code = POLYGON_SYSTEM_CONTRACT.code;
        assertGt(code.length, 0, "Polygon's system contract");
    }

    /// Without the implementation the matrix refuses on the first network,
    /// naming it as the missing dependency, though the clone is at its address.
    function testMissingImplementationIsRefusedNamingNetworkAndDependency() external {
        vm.etch(exampleCloneImplementation(), hex"");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.MissingDependency.selector, LibRainDeploy.POLYGON, exampleCloneImplementation()
            )
        );
        this.testSuitesLiveOnEverySupportedNetwork();
    }

    /// With other code at the implementation's address the matrix refuses on
    /// the first network, naming the dependency and both code hashes.
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

    /// A dependency on Polygon with the declared code and absent from Arbitrum
    /// One passes Polygon and is refused on Arbitrum One: every network is
    /// checked, not the first.
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

    /// A dependency declared with code other than Polygon's is refused on
    /// Polygon, naming the dependency, the declared hash and Polygon's.
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
}
