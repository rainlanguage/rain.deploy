// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployCandidate, DeployDeclaration, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {DeployDependency, LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";

/// @title RainDeployVerifyChainDependenciesTest
/// @notice The chain matrix holds every released suite's declared dependencies to the code declared
/// for them on each network, before the suite's own address.
contract RainDeployVerifyChainDependenciesTest is RainDeployVerifyChain {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployDeclaration.setNetworks(d, declaredNetworks());
        LibRainDeployZoltuMechanism.extend(d);
        LibRainDeployDeclaration.addReleased(d, declaredReleased());
        LibRainDeployDeclaration.addCandidates(d, declaredCandidates());
        return d;
    }

    /// Polygon's native token system contract.
    address constant POLYGON_SYSTEM_CONTRACT = 0x0000000000000000000000000000000000001010;

    /// Where the release's one declared dependency is.
    address constant DEPENDENCY = address(uint160(0xDE9E4DE4C1));

    function declaredNetworks() internal pure returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.POLYGON;
        networks[1] = LibRainDeploy.ARBITRUM_ONE;
        return networks;
    }

    /// `MockDeployable` under `key`, declaring `MockDeployableV2` at `DEPENDENCY`.
    /// @param key The suite key.
    /// @return The suite.
    function dependentSuite(string memory key) internal pure returns (DeploySuite memory) {
        DeployDependency[] memory dependencies = new DeployDependency[](1);
        dependencies[0] =
            DeployDependency({deployedAddress: DEPENDENCY, runtimeCode: type(MockDeployableV2).runtimeCode});
        return DeploySuite({
            networks: new string[](0),
            suite: key,
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode),
            storedBytecodeHash: keccak256(type(MockDeployable).runtimeCode),
            storedRuntimeCode: type(MockDeployable).runtimeCode,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: dependencies,
            mechanismData: LibRainDeployZoltuMechanism.mechanismData(),
            describedByMeta: ""
        });
    }

    function declaredReleased() internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = dependentSuite("mock-deployable@0_0_1");
        return suites;
    }

    function declaredCandidates() internal pure returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({snapshot: dependentSuite("mock-deployable"), unanchorableReason: ""});
        return candidates;
    }

    /// Puts the release's dependencies, and the release at its address, on every fork.
    function setUp() external {
        DeploySuite memory release = declaration().released[0];
        for (uint256 i = 0; i < release.dependencies.length; i++) {
            vm.etch(release.dependencies[i].deployedAddress, release.dependencies[i].runtimeCode);
            vm.makePersistent(release.dependencies[i].deployedAddress);
        }
        vm.etch(release.storedDeployedAddress, release.storedRuntimeCode);
        vm.makePersistent(release.storedDeployedAddress);
    }

    /// External wrapper for `checkDeployedOnSupportedNetworks`.
    /// @param suites The suites to check.
    function externalCheckDeployedOnSupportedNetworks(DeploySuite[] memory suites) external {
        checkDeployedOnSupportedNetworks(declaration(), suites);
    }

    /// The release with one more declared dependency.
    /// @param dependency The dependency to add.
    /// @return The release, as the one suite to check.
    function releaseDeclaring(DeployDependency memory dependency) internal pure returns (DeploySuite[] memory) {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = declaration().released[0];
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

    /// Without the dependency the matrix refuses on the first network, naming it as the missing
    /// dependency, though the release is at its address.
    function testMissingDependencyIsRefusedNamingNetworkAndDependency() external {
        vm.etch(DEPENDENCY, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.MissingDependency.selector, LibRainDeploy.POLYGON, DEPENDENCY)
        );
        this.testSuitesLiveOnEverySupportedNetwork();
    }

    /// With other code at the dependency's address the matrix refuses on the first network,
    /// naming the dependency and both code hashes.
    function testChangedDependencyIsRefusedNamingNetworkAndDependency() external {
        vm.etch(DEPENDENCY, type(MockDeployable).runtimeCode);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.DependencyChanged.selector,
                LibRainDeploy.POLYGON,
                DEPENDENCY,
                keccak256(type(MockDeployableV2).runtimeCode),
                keccak256(type(MockDeployable).runtimeCode)
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
            DeployDependency({
                deployedAddress: POLYGON_SYSTEM_CONTRACT, runtimeCode: type(MockDeployableV2).runtimeCode
            })
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.DependencyChanged.selector,
                LibRainDeploy.POLYGON,
                POLYGON_SYSTEM_CONTRACT,
                keccak256(type(MockDeployableV2).runtimeCode),
                keccak256(actual)
            )
        );
        this.externalCheckDeployedOnSupportedNetworks(suites);
    }

    /// With two suites, a dependency only the SECOND declares, absent from Arbitrum One, is refused
    /// on Arbitrum One naming it.
    function testSecondSuitesDependencyAbsentFromOneNetworkIsRefusedNamingThatNetworkAndDependency() external {
        DeploySuite[] memory suites = new DeploySuite[](2);
        suites[0] = declaration().released[0];
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

    /// With the release gone from Polygon, the first network checked, the suite is refused as not
    /// deployed there.
    function testReleaseGoneIsRefusedAsNotDeployedOnTheFirstNetwork() external {
        address deployed = declaration().released[0].storedDeployedAddress;
        vm.etch(deployed, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.POLYGON, deployed)
        );
        this.externalCheckDeployedOnSupportedNetworks(declaration().released);
    }

    /// On a network where the suite's dependency AND its address both fail, the dependency is the
    /// refusal.
    function testDependencyRefusalPrecedesTheAddressRefusalOnOneNetwork() external {
        vm.etch(declaration().released[0].storedDeployedAddress, hex"");
        vm.etch(DEPENDENCY, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.MissingDependency.selector, LibRainDeploy.POLYGON, DEPENDENCY)
        );
        this.externalCheckDeployedOnSupportedNetworks(declaration().released);
    }
}
