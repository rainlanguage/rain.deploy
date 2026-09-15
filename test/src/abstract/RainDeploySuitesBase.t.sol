// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {
    DeploySuite,
    DuplicateDeploySuite,
    InvalidDeploySuiteKey,
    NoDeployCandidates,
    UnknownDeploymentSuite
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {ExampleDeploy} from "../../concrete/ExampleDeploy.sol";
import {CollidingCandidateDeploySuites} from "../../concrete/CollidingCandidateDeploySuites.sol";
import {DuplicateDeploySuites} from "../../concrete/DuplicateDeploySuites.sol";
import {EmptyKeyDeploySuites} from "../../concrete/EmptyKeyDeploySuites.sol";
import {NoCandidateDeploySuites} from "../../concrete/NoCandidateDeploySuites.sol";
import {SameLengthKeyDeploySuites} from "../../concrete/SameLengthKeyDeploySuites.sol";
import {SeparatorKeyDeploySuites} from "../../concrete/SeparatorKeyDeploySuites.sol";
import {ShortestKeyDeploySuites} from "../../concrete/ShortestKeyDeploySuites.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";

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
        assertEq(suites[0].suite, "address-registry@0_0_1");
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

    function testSuitesSharingCreationCodeSelectApart() external view {
        DeploySuite memory released = sSuites.externalSuiteByName("address-registry@0_0_1");
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
                "address-registry@0_0_1, second-address, address-registry-candidate, second-address-candidate"
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
                "address-registry@0_0_1, second-address, address-registry-candidate, second-address-candidate"
            )
        );
        sSuites.externalSuiteByName("");
    }

    /// A declaration that KEYS a suite on the empty string MUST be refused, on
    /// every reader.
    ///
    /// `testEmptySuiteIsUnknown` above says the empty key is unknown to the
    /// fixture registry. It says nothing about a registry that declares it, and
    /// the empty string is not an ordinary key: it is the value
    /// `RainDeployBroadcast.run()` substitutes for an absent
    /// `DEPLOYMENT_SUITE`, so a declaration allowed to answer it is a dispatch
    /// with the suite input left blank selecting a real contract and putting it
    /// at its permanent `CREATE2` address on every chain that dispatch reached.
    ///
    /// Refused where the key rules already are rather than at the substitution,
    /// so the guarantee holds for every `suiteByName` caller and not only for
    /// `run()` — the argument `NoDeployCandidates` is already made of.
    ///
    /// The reported index is asserted, not just the refusal. It is 1, the
    /// CANDIDATE, behind a released suite that is keyed properly: a check that
    /// looked only at the head of the registry would answer this declaration as
    /// if nothing were wrong, and with the key empty the position is the only
    /// thing that can name which entry is at fault.
    function testEmptySuiteKeyReverts() external {
        EmptyKeyDeploySuites empty = new EmptyKeyDeploySuites();

        vm.expectRevert(abi.encodeWithSelector(InvalidDeploySuiteKey.selector, 1, ""));
        empty.externalAllSuites();

        vm.expectRevert(abi.encodeWithSelector(InvalidDeploySuiteKey.selector, 1, ""));
        empty.externalSuiteNames();

        // The selection an unset `DEPLOYMENT_SUITE` makes. Without the refusal
        // this returns the candidate — `MockDeployableV2`, a real deployable
        // entry — rather than reporting the valid set.
        vm.expectRevert(abi.encodeWithSelector(InvalidDeploySuiteKey.selector, 1, ""));
        empty.externalSuiteByName("");

        // And for a key that IS spelled: one bad entry makes the whole registry
        // unreadable, exactly as a duplicate does, rather than leaving the
        // sibling entries quietly selectable out of a declaration nobody can
        // safely dispatch from.
        vm.expectRevert(abi.encodeWithSelector(InvalidDeploySuiteKey.selector, 1, ""));
        empty.externalSuiteByName("address-registry@0_0_1");
    }

    /// A ONE BYTE key MUST be an ordinary key.
    function testShortestKeysSelectApart() external {
        ShortestKeyDeploySuites shortest = new ShortestKeyDeploySuites();

        DeploySuite[] memory suites = shortest.externalAllSuites();
        assertEq(suites.length, 2);
        assertEq(suites[0].suite, "a");
        assertEq(suites[1].suite, "z");
        assertEq(shortest.externalSuiteNames(), "a, z");

        DeploySuite memory released = shortest.externalSuiteByName("a");
        assertEq(released.artifactPath, "src/concrete/AddressRegistry.sol:AddressRegistry");

        DeploySuite memory candidate = shortest.externalSuiteByName("z");
        assertEq(candidate.artifactPath, "test/concrete/MockDeployableV2.sol:MockDeployableV2");
        assertEq(candidate.storedDeployedAddress, LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode));
    }

    /// The reported key list MUST be exactly the registry, in order.
    function testSuiteNamesIsTheRegistry() external view {
        assertEq(
            sSuites.externalSuiteNames(),
            "address-registry@0_0_1, second-address, address-registry-candidate, second-address-candidate"
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
        none.externalSuiteByName("address-registry@0_0_1");

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

    /// A key is the whole string, not its length. Two DIFFERENT keys of the
    /// SAME length MUST be two suites: both declared, each selecting its own
    /// record, and a third key of that length still unknown.
    ///
    /// A registry that compared how long a key is would call these two a
    /// duplicate and refuse the declaration, hand the first record back for the
    /// second key, and answer a key nobody declared with a real suite — which
    /// on the deploy side is the wrong contract broadcast under a key that
    /// looks right. Every other declaration here happens to spell its keys at
    /// differing lengths, so nothing else can tell the two rules apart.
    function testSameLengthKeysSelectApart() external {
        SameLengthKeyDeploySuites sameLength = new SameLengthKeyDeploySuites();

        DeploySuite[] memory suites = sameLength.externalAllSuites();
        assertEq(suites.length, 2);
        assertEq(suites[0].suite, "same-length-aaa");
        assertEq(suites[1].suite, "same-length-zzz");
        assertEq(bytes(suites[0].suite).length, bytes(suites[1].suite).length);

        DeploySuite memory first = sameLength.externalSuiteByName("same-length-aaa");
        assertEq(first.suite, "same-length-aaa");
        assertEq(first.storedDeployedAddress, suites[0].storedDeployedAddress);
        assertEq(keccak256(first.creationCode), keccak256(suites[0].creationCode));

        DeploySuite memory second = sameLength.externalSuiteByName("same-length-zzz");
        assertEq(second.suite, "same-length-zzz");
        assertEq(second.storedDeployedAddress, suites[1].storedDeployedAddress);
        assertEq(keccak256(second.creationCode), keccak256(suites[1].creationCode));

        assertNotEq(first.storedDeployedAddress, second.storedDeployedAddress);

        vm.expectRevert(
            abi.encodeWithSelector(
                UnknownDeploymentSuite.selector, "same-length-qqq", "same-length-aaa, same-length-zzz"
            )
        );
        sameLength.externalSuiteByName("same-length-qqq");
    }

    function testSeparatorKeyIsRefused() external {
        SeparatorKeyDeploySuites separated = new SeparatorKeyDeploySuites();

        vm.expectRevert(abi.encodeWithSelector(InvalidDeploySuiteKey.selector, 0, "a,b"));
        separated.externalAllSuites();

        vm.expectRevert(abi.encodeWithSelector(InvalidDeploySuiteKey.selector, 0, "a,b"));
        separated.externalSuiteNames();

        vm.expectRevert(abi.encodeWithSelector(InvalidDeploySuiteKey.selector, 0, "a,b"));
        separated.externalSuiteByName("c");

        vm.expectRevert(abi.encodeWithSelector(InvalidDeploySuiteKey.selector, 0, "a,b"));
        separated.externalSuiteByName("b");
    }

    function testSuiteKeyAlphabetAccepts() external view {
        string[7] memory accepted =
            ["address-registry", "a", "a-b-c", "address-registry@0_1_10", "tofu-token-decimals@0_1_0", "a@z", "a@-_9"];

        for (uint256 i = 0; i < accepted.length; i++) {
            sSuites.externalCheckSuiteKey(i, accepted[i]);
        }
    }

    function testSuiteKeyAlphabetRefuses() external {
        string[14] memory refused = [
            "",
            "@",
            "@0_1_10",
            "address-registry@",
            "address-registry@0_1_10@0_1_11",
            "Address-Registry",
            "address registry",
            "address,registry",
            "address_registry",
            "address-registry-0-0-1",
            "address-registry@0_1_7-RC",
            "address.registry",
            "address/registry",
            unicode"addréss-registry"
        ];

        for (uint256 i = 0; i < refused.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(InvalidDeploySuiteKey.selector, i, refused[i]));
            sSuites.externalCheckSuiteKey(i, refused[i]);
        }
    }
}
