// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ZoltuDerivationMismatch} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {DeployCandidate, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    CandidateSourceMismatch,
    RainDeployVerifyOffline,
    StoredAddressMismatch,
    StoredCodeHashMismatch,
    StoredRuntimeCodeHashMismatch
} from "../../../src/abstract/RainDeployVerifyOffline.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {MockDeploySuites} from "../../abstract/MockDeploySuites.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";
import {
    BYTECODE_HASH as MOCK_BYTECODE_HASH_0_0_1,
    CREATION_CODE as MOCK_CREATION_CODE_0_0_1,
    DEPLOYED_ADDRESS as MOCK_DEPLOYED_ADDRESS_0_0_1,
    RUNTIME_CODE as MOCK_RUNTIME_CODE_0_0_1
} from "../../generated/0_0_1/MockDeployable.sol";

/// @title RainDeployVerifyOfflineTest
/// @notice `RainDeployVerifyOffline` inherited by a exemplar repo, so the
/// inherited tests themselves are the passing case: `MockDeploySuites`
/// declares two frozen releases and a candidate, and
/// `testDeployPinsInternallyConsistent` /
/// `testDeployPinsCandidateAnchoredToSource` run over them here exactly as they
/// would in a consumer.
///
/// The rest is what each group CATCHES, and — for the internal group — what it
/// provably does not. Every case drives the same internal functions the
/// inherited tests do, through external wrappers so `vm.expectRevert` lands at
/// the right call depth, with the exemplar data deliberately broken one field at
/// a time.
contract RainDeployVerifyOfflineTest is MockDeploySuites, RainDeployVerifyOffline {
    /// External wrapper for `checkInternallyConsistent` so `vm.expectRevert`
    /// works at the correct call depth.
    /// @param suite The suite to check.
    function externalCheckInternallyConsistent(DeploySuite memory suite) external {
        checkInternallyConsistent(suite);
    }

    /// External wrapper for `checkAnchoredToSource` so `vm.expectRevert` works
    /// at the correct call depth.
    /// @param candidate The candidate to check.
    function externalCheckAnchoredToSource(DeployCandidate memory candidate) external pure {
        checkAnchoredToSource(candidate);
    }

    /// A consistent snapshot of the WRONG contract: every recorded field is
    /// `MockDeployable`'s and they all agree with each other, but it is
    /// presented as the candidate for a repo whose source is
    /// `MockDeployableV2`. This is the shape of a snapshot generated from a
    /// stale build, or from the wrong contract in a repo with several.
    /// @return The wrong-contract candidate.
    function wrongContractCandidate() internal pure returns (DeployCandidate memory) {
        return DeployCandidate({
            snapshot: DeploySuite({
                suite: "mock-deployable-v2-candidate",
                creationCode: MOCK_CREATION_CODE_0_0_1,
                storedDeployedAddress: MOCK_DEPLOYED_ADDRESS_0_0_1,
                storedBytecodeHash: MOCK_BYTECODE_HASH_0_0_1,
                storedRuntimeCode: MOCK_RUNTIME_CODE_0_0_1,
                artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
                dependencies: new address[](0)
            }),
            sourceCreationCode: type(MockDeployableV2).creationCode
        });
    }

    /// The frozen `0_0_1` release, which every negative case below breaks one
    /// field of.
    /// @return The consistent `0_0_1` suite.
    function consistentSuite() internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: "mock-deployable-0-0-1",
            creationCode: MOCK_CREATION_CODE_0_0_1,
            storedDeployedAddress: MOCK_DEPLOYED_ADDRESS_0_0_1,
            storedBytecodeHash: MOCK_BYTECODE_HASH_0_0_1,
            storedRuntimeCode: MOCK_RUNTIME_CODE_0_0_1,
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new address[](0)
        });
    }

    /// A recorded address that is not the one the recorded creation code
    /// derives MUST fail, naming the version and both addresses. This is the
    /// hand-edited constant, and the address copied from the wrong tag.
    function testStoredAddressMismatchReverts() external {
        DeploySuite memory suite = consistentSuite();
        suite.storedDeployedAddress = address(0xdead);

        vm.expectRevert(
            abi.encodeWithSelector(
                StoredAddressMismatch.selector, "mock-deployable-0-0-1", address(0xdead), MOCK_DEPLOYED_ADDRESS_0_0_1
            )
        );
        this.externalCheckInternallyConsistent(suite);
    }

    /// A recorded code hash that is not the one the recorded creation code
    /// produces MUST fail, naming the version and both hashes. This is a
    /// snapshot regenerated for one field and not the others.
    function testStoredCodeHashMismatchReverts() external {
        DeploySuite memory suite = consistentSuite();
        suite.storedBytecodeHash = bytes32(uint256(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                StoredCodeHashMismatch.selector, "mock-deployable-0-0-1", bytes32(uint256(1)), MOCK_BYTECODE_HASH_0_0_1
            )
        );
        this.externalCheckInternallyConsistent(suite);
    }

    /// Recorded runtime code that does not hash to the code hash recorded
    /// beside it MUST fail, naming the version and both hashes. The address and
    /// the code hash still agree with the creation code here, so this is the
    /// only check standing between a corrupted `RUNTIME_CODE` and a green
    /// suite.
    function testStoredRuntimeCodeHashMismatchReverts() external {
        DeploySuite memory suite = consistentSuite();
        suite.storedRuntimeCode = hex"00";

        vm.expectRevert(
            abi.encodeWithSelector(
                StoredRuntimeCodeHashMismatch.selector,
                "mock-deployable-0-0-1",
                MOCK_BYTECODE_HASH_0_0_1,
                keccak256(hex"00")
            )
        );
        this.externalCheckInternallyConsistent(suite);
    }

    /// The internal group MUST NOT catch a consistent snapshot of the wrong
    /// contract, and this pins that it does not. It is not a gap to be closed
    /// there: every internal check asks the recorded bytes to agree with each
    /// other, and the wrong contract's bytes agree with each other perfectly.
    ///
    /// Pinning the miss is what stops the internal group from being read as
    /// covering the source-anchored one, and what makes the next test the only
    /// thing standing between a stale snapshot and a green suite.
    function testWrongContractSnapshotPassesInternalConsistency() external {
        DeployCandidate memory candidate = wrongContractCandidate();

        // It really is the wrong contract: the recorded creation code is not
        // the creation code this repo compiles for the candidate.
        assertNotEq(keccak256(candidate.snapshot.creationCode), keccak256(type(MockDeployableV2).creationCode));
        assertEq(keccak256(candidate.snapshot.creationCode), keccak256(type(MockDeployable).creationCode));

        // Every internal check passes anyway.
        this.externalCheckInternallyConsistent(candidate.snapshot);
    }

    /// The source-anchored group MUST catch exactly the snapshot the internal
    /// group just let through, naming the candidate and both creation code
    /// hashes. This is the only check in the whole suite that can.
    function testWrongContractSnapshotCaughtBySource() external {
        DeployCandidate memory candidate = wrongContractCandidate();

        vm.expectRevert(
            abi.encodeWithSelector(
                CandidateSourceMismatch.selector,
                "mock-deployable-v2-candidate",
                keccak256(MOCK_CREATION_CODE_0_0_1),
                keccak256(type(MockDeployableV2).creationCode)
            )
        );
        this.externalCheckAnchoredToSource(candidate);
    }

    /// A candidate whose recorded creation code IS the source's MUST pass, so
    /// the previous test is discriminating rather than a check that always
    /// fails.
    function testCandidateAnchoredToSourcePasses() external view {
        this.externalCheckAnchoredToSource(candidateSuite());
    }

    /// Two suites that record the SAME creation code MUST both derive, which
    /// is the ordinary state of a repo between a release and the next source
    /// change. `0_0_2` and the candidate are the same bytes and therefore the
    /// same address, and the whole set still passes.
    function testVersionsSharingCreationCodeAllDerive() external {
        DeploySuite[] memory suites = allSuites();
        assertEq(suites.length, 3);
        assertEq(suites[1].storedDeployedAddress, suites[2].storedDeployedAddress);
        assertEq(keccak256(suites[1].creationCode), keccak256(suites[2].creationCode));

        // Neither derivation is disturbed by the other.
        this.externalCheckInternallyConsistent(suites[1]);
        this.externalCheckInternallyConsistent(suites[2]);
    }

    /// The pure address formula and the factory bytecode the derivation etches
    /// MUST agree, and a disagreement MUST be named rather than left to surface
    /// as a code hash read from an address nothing was deployed to. Forced here
    /// by making the factory report an address it did not deploy to, which is
    /// otherwise unreachable — the derivation etches the factory bytecode
    /// itself, so only a `LibRainDeploy` whose constant and formula had drifted
    /// apart could produce it.
    function testZoltuDerivationMismatchReverts() external {
        DeploySuite memory suite = consistentSuite();

        // The factory answers with an address that does have code, but is not
        // the one the creation code derives.
        vm.mockCall(
            LibRainDeploy.ZOLTU_FACTORY,
            MOCK_CREATION_CODE_0_0_1,
            abi.encodePacked(bytes20(LibRainDeploy.ZOLTU_FACTORY))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ZoltuDerivationMismatch.selector,
                "mock-deployable-0-0-1",
                MOCK_DEPLOYED_ADDRESS_0_0_1,
                LibRainDeploy.ZOLTU_FACTORY
            )
        );
        this.externalCheckInternallyConsistent(suite);
    }

    /// The derivation MUST leave nothing behind. A local deploy that survived
    /// would be compared against itself by the chain-anchored group, and every
    /// network would pass whether or not anything is deployed there.
    function testDerivationLeavesNoCodeBehind() external {
        DeploySuite[] memory suites = allSuites();
        for (uint256 i = 0; i < suites.length; i++) {
            assertEq(suites[i].storedDeployedAddress.code.length, 0);
        }

        this.externalCheckInternallyConsistent(suites[0]);

        for (uint256 i = 0; i < suites.length; i++) {
            assertEq(suites[i].storedDeployedAddress.code.length, 0);
        }
    }
}
