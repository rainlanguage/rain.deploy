// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {
    DeploySuite,
    DuplicateDeploySuite,
    NoDeployCandidates,
    UnknownDeploymentSuite
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {ExampleDeploy} from "../../concrete/ExampleDeploy.sol";
import {CollidingCandidateDeploySuites} from "../../concrete/CollidingCandidateDeploySuites.sol";
import {DuplicateDeploySuites} from "../../concrete/DuplicateDeploySuites.sol";
import {NoCandidateDeploySuites} from "../../concrete/NoCandidateDeploySuites.sol";

/// @title RainDeploySuitesBaseTest
/// @notice The registry itself: one declaration, keyed lookup, and the two ways
/// a key can be wrong.
///
/// The registry is what replaces a chain of `else if` arms. `st0x.deploy`'s
/// production script is ten such arms of identical shape, and it restates its
/// valid keys in a revert string that nothing keeps in step with the arms —
/// so the failure message and the actual set of suites are free to drift. Here
/// they are the same array, which is what these tests pin.
contract RainDeploySuitesBaseTest is Test {
    ExampleDeploy internal sSuites;

    /// The fixture declaration, as a deploy script would inherit it.
    function setUp() external {
        sSuites = new ExampleDeploy();
    }

    /// The registry MUST be the released suites followed by the candidates, in
    /// declaration order. Both sides of the repo read this one array, which is
    /// what makes deploying one thing and verifying another unrepresentable
    /// rather than merely unlikely.
    function testAllSuitesIsReleasedThenCandidates() external view {
        DeploySuite[] memory suites = sSuites.externalAllSuites();

        assertEq(suites.length, 4);
        assertEq(suites[0].suite, "address-registry-0-0-1");
        assertEq(suites[1].suite, "second-address");
        assertEq(suites[2].suite, "address-registry-candidate");
        assertEq(suites[3].suite, "second-address-candidate");
    }

    /// Every declared key MUST select its own suite. A deploy is dispatched per
    /// suite, so each has to be individually selectable — including a frozen
    /// release, which is how an old snapshot reaches a chain added after it.
    function testEverySuiteIsSelectableByKey() external view {
        DeploySuite[] memory suites = sSuites.externalAllSuites();

        for (uint256 i = 0; i < suites.length; i++) {
            DeploySuite memory selected = sSuites.externalSuiteByName(suites[i].suite);
            assertEq(selected.suite, suites[i].suite);
            assertEq(keccak256(selected.creationCode), keccak256(suites[i].creationCode));
            assertEq(selected.storedDeployedAddress, suites[i].storedDeployedAddress);
            assertEq(selected.artifactPath, suites[i].artifactPath);
        }
    }

    /// Two suites that record the SAME creation code MUST still be selectable
    /// apart. `0_0_2` and the candidate are the same bytes at the same address,
    /// so the key is the only thing that distinguishes them — and it has to,
    /// because they are separately deployable records.
    function testSuitesSharingCreationCodeSelectApart() external view {
        DeploySuite memory released = sSuites.externalSuiteByName("address-registry-0-0-1");
        DeploySuite memory candidate = sSuites.externalSuiteByName("address-registry-candidate");

        assertEq(keccak256(released.creationCode), keccak256(candidate.creationCode));
        assertEq(released.storedDeployedAddress, candidate.storedDeployedAddress);
        assertNotEq(keccak256(bytes(released.suite)), keccak256(bytes(candidate.suite)));
    }

    /// An unknown key MUST fail naming EVERY valid key. Not one hardcoded
    /// string: the list is built from the registry, so it cannot fall behind
    /// the suites it describes.
    function testUnknownSuiteNamesEveryValidSuite() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                UnknownDeploymentSuite.selector,
                "mock-deployable",
                "address-registry-0-0-1, second-address, address-registry-candidate, second-address-candidate"
            )
        );
        sSuites.externalSuiteByName("mock-deployable");
    }

    /// An empty key is just another unknown key, so an unset `DEPLOYMENT_SUITE`
    /// reports the valid set rather than silently taking a default.
    function testEmptySuiteIsUnknown() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                UnknownDeploymentSuite.selector,
                "",
                "address-registry-0-0-1, second-address, address-registry-candidate, second-address-candidate"
            )
        );
        sSuites.externalSuiteByName("");
    }

    /// The reported key list MUST be exactly the registry, in order.
    function testSuiteNamesIsTheRegistry() external view {
        assertEq(
            sSuites.externalSuiteNames(),
            "address-registry-0-0-1, second-address, address-registry-candidate, second-address-candidate"
        );
    }

    /// Two suites under one key MUST fail, on BOTH paths that read the
    /// registry. A duplicate makes selection ambiguous and leaves one record
    /// unreachable, and it is checked where both the deploy side and the verify
    /// side pay for it rather than in either one of them.
    function testDuplicateSuiteKeyReverts() external {
        DuplicateDeploySuites duplicates = new DuplicateDeploySuites();

        vm.expectRevert(abi.encodeWithSelector(DuplicateDeploySuite.selector, "collides"));
        duplicates.externalAllSuites();

        vm.expectRevert(abi.encodeWithSelector(DuplicateDeploySuite.selector, "collides"));
        duplicates.externalSuiteByName("collides");
    }

    /// Two CANDIDATES under one key MUST fail exactly as a release colliding
    /// with a candidate does. The uniqueness rule is about the registry, not
    /// about which side of it an entry came from, and this is the collision
    /// that only becomes representable once the candidate side is a list.
    function testDuplicateCandidateKeyReverts() external {
        CollidingCandidateDeploySuites candidates = new CollidingCandidateDeploySuites();

        vm.expectRevert(abi.encodeWithSelector(DuplicateDeploySuite.selector, "collides"));
        candidates.externalAllSuites();

        vm.expectRevert(abi.encodeWithSelector(DuplicateDeploySuite.selector, "collides"));
        candidates.externalSuiteByName("collides");

        vm.expectRevert(abi.encodeWithSelector(DuplicateDeploySuite.selector, "collides"));
        candidates.externalSuiteNames();
    }

    /// A declaration with NO candidate MUST be refused on every read.
    ///
    /// An empty candidate list reads as a repo with nothing left to declare and
    /// is a repo whose source anchor — the only check that catches a snapshot
    /// of the wrong contract — has been handed nothing to run over. It is
    /// refused rather than tolerated, and refused on EVERY reader, because a
    /// reader that answers from an empty declaration is a reader through which
    /// the whole registry can be empty and green.
    function testNoCandidateReverts() external {
        NoCandidateDeploySuites none = new NoCandidateDeploySuites();

        vm.expectRevert(abi.encodeWithSelector(NoDeployCandidates.selector));
        none.externalAllSuites();

        vm.expectRevert(abi.encodeWithSelector(NoDeployCandidates.selector));
        none.externalSuiteNames();

        // Refused BEFORE the key is even looked for: an empty declaration
        // cannot answer "no such suite" either, because it has no valid set to
        // report and the answer would send the reader after a typo.
        vm.expectRevert(abi.encodeWithSelector(NoDeployCandidates.selector));
        none.externalSuiteByName("address-registry-0-0-1");

        // And at the source of the refusal itself, which is what the
        // source-anchored check reads through — a loop over an empty list
        // passes, so that check cannot be the thing that catches this.
        vm.expectRevert(abi.encodeWithSelector(NoDeployCandidates.selector));
        none.externalCheckedCandidateSuites();

        // Including through the anchor itself, which the BROADCAST runs. An
        // empty declaration that reached it would be a deploy whose only
        // wrong-contract check ran over nothing and passed.
        vm.expectRevert(abi.encodeWithSelector(NoDeployCandidates.selector));
        none.externalCheckCandidatesAnchoredToSource();
    }

    /// The refusal MUST be discriminating: a declaration that DOES name a
    /// candidate answers every reader rather than reverting, so the test above
    /// is about emptiness and not about the fixture.
    function testCandidatesPresentAnswers() external view {
        assertEq(sSuites.externalCheckedCandidateSuites().length, 2);
        sSuites.externalCheckCandidatesAnchoredToSource();
    }
}
