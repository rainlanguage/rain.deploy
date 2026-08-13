// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DeployCandidate, DeployVersion, ZoltuDerivationMismatch} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {
    CandidateSourceMismatch,
    RainDeployVerifyOffline,
    StoredAddressMismatch,
    StoredCodeHashMismatch,
    StoredRuntimeCodeHashMismatch
} from "../../../src/abstract/RainDeployVerifyOffline.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {MockDeployVersions} from "../../abstract/MockDeployVersions.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";
import {
    BYTECODE_HASH as MOCK_DEPLOYABLE_BYTECODE_HASH_0_0_1,
    CREATION_CODE as MOCK_DEPLOYABLE_CREATION_CODE_0_0_1,
    DEPLOYED_ADDRESS as MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1,
    RUNTIME_CODE as MOCK_DEPLOYABLE_RUNTIME_CODE_0_0_1
} from "../../fixtures/0_0_1/MockDeployable.pointers.sol";

/// @title RainDeployVerifyOfflineTest
/// @notice `RainDeployVerifyOffline` inherited by a fixture repo, so the
/// inherited tests themselves are the passing case: `MockDeployVersions`
/// declares two frozen releases and a candidate, and
/// `testDeployPinsInternallyConsistent` /
/// `testDeployPinsCandidateAnchoredToSource` run over them here exactly as they
/// would in a consumer.
///
/// The rest is what each group CATCHES, and — for the internal group — what it
/// provably does not. Every case drives the same internal functions the
/// inherited tests do, through external wrappers so `vm.expectRevert` lands at
/// the right call depth, with the fixture data deliberately broken one field at
/// a time.
contract RainDeployVerifyOfflineTest is MockDeployVersions, RainDeployVerifyOffline {
    /// External wrapper for `checkInternallyConsistent` so `vm.expectRevert`
    /// works at the correct call depth.
    /// @param version The version to check.
    function externalCheckInternallyConsistent(DeployVersion memory version) external {
        checkInternallyConsistent(version);
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
            snapshot: DeployVersion({
                version: "candidate",
                creationCode: MOCK_DEPLOYABLE_CREATION_CODE_0_0_1,
                storedDeployedAddress: MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1,
                storedBytecodeHash: MOCK_DEPLOYABLE_BYTECODE_HASH_0_0_1,
                storedRuntimeCode: MOCK_DEPLOYABLE_RUNTIME_CODE_0_0_1
            }),
            sourceCreationCode: type(MockDeployableV2).creationCode
        });
    }

    /// The frozen `0_0_1` release, which every negative case below breaks one
    /// field of.
    /// @return The consistent `0_0_1` version.
    function consistentVersion() internal pure returns (DeployVersion memory) {
        return DeployVersion({
            version: "0_0_1",
            creationCode: MOCK_DEPLOYABLE_CREATION_CODE_0_0_1,
            storedDeployedAddress: MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1,
            storedBytecodeHash: MOCK_DEPLOYABLE_BYTECODE_HASH_0_0_1,
            storedRuntimeCode: MOCK_DEPLOYABLE_RUNTIME_CODE_0_0_1
        });
    }

    /// A recorded address that is not the one the recorded creation code
    /// derives MUST fail, naming the version and both addresses. This is the
    /// hand-edited constant, and the address copied from the wrong tag.
    function testStoredAddressMismatchReverts() external {
        DeployVersion memory version = consistentVersion();
        version.storedDeployedAddress = address(0xdead);

        vm.expectRevert(
            abi.encodeWithSelector(
                StoredAddressMismatch.selector, "0_0_1", address(0xdead), MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1
            )
        );
        this.externalCheckInternallyConsistent(version);
    }

    /// A recorded code hash that is not the one the recorded creation code
    /// produces MUST fail, naming the version and both hashes. This is a
    /// snapshot regenerated for one field and not the others.
    function testStoredCodeHashMismatchReverts() external {
        DeployVersion memory version = consistentVersion();
        version.storedBytecodeHash = bytes32(uint256(1));

        vm.expectRevert(
            abi.encodeWithSelector(
                StoredCodeHashMismatch.selector, "0_0_1", bytes32(uint256(1)), MOCK_DEPLOYABLE_BYTECODE_HASH_0_0_1
            )
        );
        this.externalCheckInternallyConsistent(version);
    }

    /// Recorded runtime code that does not hash to the code hash recorded
    /// beside it MUST fail, naming the version and both hashes. The address and
    /// the code hash still agree with the creation code here, so this is the
    /// only check standing between a corrupted `RUNTIME_CODE` and a green
    /// suite.
    function testStoredRuntimeCodeHashMismatchReverts() external {
        DeployVersion memory version = consistentVersion();
        version.storedRuntimeCode = hex"00";

        vm.expectRevert(
            abi.encodeWithSelector(
                StoredRuntimeCodeHashMismatch.selector, "0_0_1", MOCK_DEPLOYABLE_BYTECODE_HASH_0_0_1, keccak256(hex"00")
            )
        );
        this.externalCheckInternallyConsistent(version);
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
                "candidate",
                keccak256(MOCK_DEPLOYABLE_CREATION_CODE_0_0_1),
                keccak256(type(MockDeployableV2).creationCode)
            )
        );
        this.externalCheckAnchoredToSource(candidate);
    }

    /// A candidate whose recorded creation code IS the source's MUST pass, so
    /// the previous test is discriminating rather than a check that always
    /// fails.
    function testCandidateAnchoredToSourcePasses() external view {
        this.externalCheckAnchoredToSource(candidateVersion());
    }

    /// Two versions that record the SAME creation code MUST both derive, which
    /// is the ordinary state of a repo between a release and the next source
    /// change. `0_0_2` and the candidate are the same bytes and therefore the
    /// same address, and the whole set still passes.
    function testVersionsSharingCreationCodeAllDerive() external {
        DeployVersion[] memory versions = allVersions();
        assertEq(versions.length, 3);
        assertEq(versions[1].storedDeployedAddress, versions[2].storedDeployedAddress);
        assertEq(keccak256(versions[1].creationCode), keccak256(versions[2].creationCode));

        // Neither derivation is disturbed by the other.
        this.externalCheckInternallyConsistent(versions[1]);
        this.externalCheckInternallyConsistent(versions[2]);
    }

    /// The pure address formula and the factory bytecode the derivation etches
    /// MUST agree, and a disagreement MUST be named rather than left to surface
    /// as a code hash read from an address nothing was deployed to. Forced here
    /// by making the factory report an address it did not deploy to, which is
    /// otherwise unreachable — the derivation etches the factory bytecode
    /// itself, so only a `LibRainDeploy` whose constant and formula had drifted
    /// apart could produce it.
    function testZoltuDerivationMismatchReverts() external {
        DeployVersion memory version = consistentVersion();

        // The factory answers with an address that does have code, but is not
        // the one the creation code derives.
        vm.mockCall(
            LibRainDeploy.ZOLTU_FACTORY,
            MOCK_DEPLOYABLE_CREATION_CODE_0_0_1,
            abi.encodePacked(bytes20(LibRainDeploy.ZOLTU_FACTORY))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ZoltuDerivationMismatch.selector,
                "0_0_1",
                MOCK_DEPLOYABLE_DEPLOYED_ADDRESS_0_0_1,
                LibRainDeploy.ZOLTU_FACTORY
            )
        );
        this.externalCheckInternallyConsistent(version);
    }

    /// The derivation MUST leave nothing behind. A local deploy that survived
    /// would be compared against itself by the chain-anchored group, and every
    /// network would pass whether or not anything is deployed there.
    function testDerivationLeavesNoCodeBehind() external {
        DeployVersion[] memory versions = allVersions();
        for (uint256 i = 0; i < versions.length; i++) {
            assertEq(versions[i].storedDeployedAddress.code.length, 0);
        }

        this.externalCheckInternallyConsistent(versions[0]);

        for (uint256 i = 0; i < versions.length; i++) {
            assertEq(versions[i].storedDeployedAddress.code.length, 0);
        }
    }
}
