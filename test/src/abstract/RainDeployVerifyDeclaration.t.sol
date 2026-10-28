// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    CandidateArtifactNotSource,
    DependencyRuntimeCodeMismatch,
    DispatchChoiceNotDeclared,
    DispatchChoiceRepeated,
    DispatchChoicesUnreadable,
    RainDeployDeclarationChecks,
    RepeatedDependency,
    RuntimeCodeExceedsEip170,
    SuiteNotDispatchable,
    UndeclaredDependency,
    UnknownDependency,
    UnreachedDependency,
    ZeroDependency
} from "../../../src/abstract/RainDeployDeclarationChecks.sol";
import {RainDeployVerifyDeclaration} from "../../../src/abstract/RainDeployVerifyDeclaration.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    DeclarationDefect,
    MOCK_EXTERNAL_RUNTIME_CODE,
    ReachingDeploySuites
} from "../../abstract/ReachingDeploySuites.sol";
import {DefectiveReleaseDeploySuites} from "../../abstract/DefectiveReleaseDeploySuites.sol";
import {UndeclaredSiblingReleaseDeploySuites} from "../../concrete/UndeclaredSiblingReleaseDeploySuites.sol";
import {UnknownDependencyReleaseDeploySuites} from "../../concrete/UnknownDependencyReleaseDeploySuites.sol";
import {ZeroDependencyReleaseDeploySuites} from "../../concrete/ZeroDependencyReleaseDeploySuites.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {
    MOCK_DEPLOYABLE_ADDRESS,
    MOCK_EXTERNAL_ADDRESS,
    MockReachingDeployable
} from "../../concrete/MockReachingDeployable.sol";

contract RainDeployVerifyDeclarationTest is ReachingDeploySuites, RainDeployVerifyDeclaration {
    function dispatchWorkflow()
        internal
        view
        override(ReachingDeploySuites, RainDeployDeclarationChecks)
        returns (string memory)
    {
        return ReachingDeploySuites.dispatchWorkflow();
    }

    function externalCheckDispatchChoicesAreTheSuiteKeys() external view {
        checkDispatchChoicesAreTheSuiteKeys();
    }

    function externalCheckCandidateArtifactPathsAreSource() external view {
        checkCandidateArtifactPathsAreSource();
    }

    function externalCheckDependenciesAreNonZeroAndUnique() external view {
        checkDependenciesAreNonZeroAndUnique();
    }

    function externalCheckDependenciesAreTheEmbeddedDeployments() external view {
        checkDependenciesAreTheEmbeddedDeployments();
    }

    function externalCheckDependencyRuntimeCodeIsKnown() external view {
        checkDependencyRuntimeCodeIsKnown();
    }

    function externalCheckCandidateRuntimeCodeFitsEip170() external view {
        checkCandidateRuntimeCodeFitsEip170();
    }

    function reachingAddress() internal pure returns (address) {
        return LibRainDeploy.zoltuAddress(type(MockReachingDeployable).creationCode);
    }

    function testMockDeployableAddressIsItsZoltuAddress() external pure {
        assertEq(MOCK_DEPLOYABLE_ADDRESS, LibRainDeploy.zoltuAddress(type(MockDeployable).creationCode));
    }

    function testDispatchDefaultsToTheManualArtifactsWorkflow() external {
        sWorkflow = RainDeployDeclarationChecks.dispatchWorkflow();
        string[] memory choices = dispatchChoices();
        assertEq(choices.length, 2);
        assertEq(choices[0], "config-registry");
        assertEq(choices[1], "migration-registry");
    }

    function testDispatchChoicesAreReadPastCommentsAndBlankLines() external view {
        string[] memory choices = dispatchChoices();
        assertEq(choices.length, 3);
        assertEq(choices[0], "mock-deployable");
        assertEq(choices[1], "mock-reaching-deployable");
        assertEq(choices[2], "mock-deployable@0_0_1");
    }

    function testDispatchChoiceNotDeclared() external {
        sWorkflow = "test/fixture-dispatch/undeclared-choice.yaml";
        vm.expectRevert(abi.encodeWithSelector(DispatchChoiceNotDeclared.selector, "mock-undeclared"));
        this.externalCheckDispatchChoicesAreTheSuiteKeys();
    }

    function testDispatchChoiceRepeated() external {
        sWorkflow = "test/fixture-dispatch/repeated-choice.yaml";
        vm.expectRevert(abi.encodeWithSelector(DispatchChoiceRepeated.selector, "mock-deployable"));
        this.externalCheckDispatchChoicesAreTheSuiteKeys();
    }

    function testReleasedSuiteNotDispatchable() external {
        sWorkflow = "test/fixture-dispatch/missing-release.yaml";
        vm.expectRevert(abi.encodeWithSelector(SuiteNotDispatchable.selector, "mock-deployable@0_0_1"));
        this.externalCheckDispatchChoicesAreTheSuiteKeys();
    }

    function checkUnreadable(string memory workflow) internal {
        sWorkflow = workflow;
        vm.expectRevert(abi.encodeWithSelector(DispatchChoicesUnreadable.selector, workflow));
        this.externalCheckDispatchChoicesAreTheSuiteKeys();
    }

    function testDispatchWithoutSuiteInputIsUnreadable() external {
        checkUnreadable("test/fixture-dispatch/no-suite-input.yaml");
    }

    function testDispatchWithoutOptionsIsUnreadable() external {
        checkUnreadable("test/fixture-dispatch/no-options.yaml");
    }

    function testDispatchWithEmptyOptionsIsUnreadable() external {
        checkUnreadable("test/fixture-dispatch/empty-options.yaml");
    }

    function testDispatchNeverReadsAnotherInputsOptions() external {
        checkUnreadable("test/fixture-dispatch/options-of-another-input.yaml");
    }

    function testArtifactPathOfOtherSource() external {
        sDefect = DeclarationDefect.ArtifactPathOfOtherSource;
        vm.expectRevert(
            abi.encodeWithSelector(
                CandidateArtifactNotSource.selector,
                "mock-reaching-deployable",
                "test/concrete/MockDeployable.sol:MockDeployable"
            )
        );
        this.externalCheckCandidateArtifactPathsAreSource();
    }

    function testZeroDependency() external {
        sDefect = DeclarationDefect.ZeroDependency;
        vm.expectRevert(abi.encodeWithSelector(ZeroDependency.selector, "mock-deployable"));
        this.externalCheckDependenciesAreNonZeroAndUnique();
    }

    function testRepeatedDependency() external {
        sDefect = DeclarationDefect.RepeatedDependency;
        vm.expectRevert(
            abi.encodeWithSelector(RepeatedDependency.selector, "mock-reaching-deployable", MOCK_DEPLOYABLE_ADDRESS)
        );
        this.externalCheckDependenciesAreNonZeroAndUnique();
    }

    function testAdjacentRepeatedDependency() external {
        sDefect = DeclarationDefect.AdjacentRepeatedDependency;
        vm.expectRevert(
            abi.encodeWithSelector(RepeatedDependency.selector, "mock-reaching-deployable", MOCK_EXTERNAL_ADDRESS)
        );
        this.externalCheckDependenciesAreNonZeroAndUnique();
    }

    function testUndeclaredSibling() external {
        sDefect = DeclarationDefect.UndeclaredSibling;
        vm.expectRevert(
            abi.encodeWithSelector(UndeclaredDependency.selector, "mock-reaching-deployable", MOCK_DEPLOYABLE_ADDRESS)
        );
        this.externalCheckDependenciesAreTheEmbeddedDeployments();
    }

    function testUndeclaredExternalWithALeadingZeroByte() external {
        sDefect = DeclarationDefect.UndeclaredExternal;
        vm.expectRevert(
            abi.encodeWithSelector(UndeclaredDependency.selector, "mock-reaching-deployable", MOCK_EXTERNAL_ADDRESS)
        );
        this.externalCheckDependenciesAreTheEmbeddedDeployments();
    }

    function testUnreachedDependency() external {
        sDefect = DeclarationDefect.UnreachedDependency;
        vm.expectRevert(abi.encodeWithSelector(UnreachedDependency.selector, "mock-deployable", reachingAddress()));
        this.externalCheckDependenciesAreTheEmbeddedDeployments();
    }

    function testUnknownDependency() external {
        sDefect = DeclarationDefect.UnknownDependency;
        vm.expectRevert(abi.encodeWithSelector(UnknownDependency.selector, "mock-deployable", address(0xdead)));
        this.externalCheckDependencyRuntimeCodeIsKnown();
    }

    function testSiblingDependencyRuntimeCodeMismatch() external {
        sDefect = DeclarationDefect.SiblingRuntimeCode;
        vm.expectRevert(
            abi.encodeWithSelector(
                DependencyRuntimeCodeMismatch.selector,
                "mock-reaching-deployable",
                MOCK_DEPLOYABLE_ADDRESS,
                keccak256(type(MockReachingDeployable).runtimeCode),
                keccak256(type(MockDeployable).runtimeCode)
            )
        );
        this.externalCheckDependencyRuntimeCodeIsKnown();
    }

    function testExternalDependencyRuntimeCodeMismatch() external {
        sDefect = DeclarationDefect.ExternalRuntimeCode;
        vm.expectRevert(
            abi.encodeWithSelector(
                DependencyRuntimeCodeMismatch.selector,
                "mock-reaching-deployable",
                MOCK_EXTERNAL_ADDRESS,
                keccak256(hex"00"),
                keccak256(MOCK_EXTERNAL_RUNTIME_CODE)
            )
        );
        this.externalCheckDependencyRuntimeCodeIsKnown();
    }

    function testRuntimeCodeAtEip170Fits() external {
        sDefect = DeclarationDefect.RuntimeCodeAtEip170;
        this.externalCheckCandidateRuntimeCodeFitsEip170();
    }

    function testRuntimeCodeOverEip170() external {
        sDefect = DeclarationDefect.RuntimeCodeOverEip170;
        vm.expectRevert(abi.encodeWithSelector(RuntimeCodeExceedsEip170.selector, "mock-deployable", 0x6001));
        this.externalCheckCandidateRuntimeCodeFitsEip170();
    }

    function testReleasedZeroDependency() external {
        DefectiveReleaseDeploySuites declaration = new ZeroDependencyReleaseDeploySuites();
        vm.expectRevert(abi.encodeWithSelector(ZeroDependency.selector, "mock-deployable@0_0_1"));
        declaration.externalCheckDependenciesAreNonZeroAndUnique();
    }

    function testReleasedUndeclaredSibling() external {
        DefectiveReleaseDeploySuites declaration = new UndeclaredSiblingReleaseDeploySuites();
        vm.expectRevert(
            abi.encodeWithSelector(
                UndeclaredDependency.selector, "mock-reaching-deployable@0_0_1", MOCK_DEPLOYABLE_ADDRESS
            )
        );
        declaration.externalCheckDependenciesAreTheEmbeddedDeployments();
    }

    function testReleasedUnknownDependency() external {
        DefectiveReleaseDeploySuites declaration = new UnknownDependencyReleaseDeploySuites();
        vm.expectRevert(abi.encodeWithSelector(UnknownDependency.selector, "mock-deployable@0_0_1", address(0xdead)));
        declaration.externalCheckDependencyRuntimeCodeIsKnown();
    }

    function testBlankAndCommentLinesAreInert() external pure {
        assertTrue(isInert(""));
        assertTrue(isInert("      "));
        assertTrue(isInert("          # Frozen releases."));
        assertFalse(isInert("          - mock-deployable"));
    }

    function testContainsAddressFindsTheStrippedPushImmediate() external pure {
        bytes memory stripped = hex"c0ffee0000000000000000000000000000c0de";
        assertTrue(containsAddress(stripped, MOCK_EXTERNAL_ADDRESS));
        assertTrue(containsAddress(abi.encodePacked(hex"5f72", stripped), MOCK_EXTERNAL_ADDRESS));
        assertTrue(containsAddress(abi.encodePacked(hex"72", stripped, hex"5f"), MOCK_EXTERNAL_ADDRESS));
        assertFalse(containsAddress(hex"c0ffee0000000000000000000000000000c0", MOCK_EXTERNAL_ADDRESS));
        assertFalse(containsAddress(hex"c0ffee0000000000000000000000000000c0df", MOCK_EXTERNAL_ADDRESS));
        assertFalse(containsAddress(abi.encodePacked(MOCK_EXTERNAL_ADDRESS), address(0)));
        assertFalse(containsAddress("", MOCK_EXTERNAL_ADDRESS));
    }

    function testEveryEntryPointRunsItsCheck() external {
        sWorkflow = "test/fixture-dispatch/undeclared-choice.yaml";
        vm.expectRevert(abi.encodeWithSelector(DispatchChoiceNotDeclared.selector, "mock-undeclared"));
        this.testDispatchChoicesAreTheSuiteKeys();
        sWorkflow = "test/fixture-dispatch/dispatchable.yaml";

        sDefect = DeclarationDefect.ArtifactPathOfOtherSource;
        vm.expectPartialRevert(CandidateArtifactNotSource.selector);
        this.testCandidateArtifactPathsAreSource();

        sDefect = DeclarationDefect.ZeroDependency;
        vm.expectPartialRevert(ZeroDependency.selector);
        this.testDependenciesAreNonZeroAndUnique();

        sDefect = DeclarationDefect.UndeclaredSibling;
        vm.expectPartialRevert(UndeclaredDependency.selector);
        this.testDependenciesAreTheEmbeddedDeployments();

        sDefect = DeclarationDefect.UnknownDependency;
        vm.expectPartialRevert(UnknownDependency.selector);
        this.testDependencyRuntimeCodeIsKnown();

        sDefect = DeclarationDefect.RuntimeCodeOverEip170;
        vm.expectPartialRevert(RuntimeCodeExceedsEip170.selector);
        this.testCandidateRuntimeCodeFitsEip170();
    }
}
