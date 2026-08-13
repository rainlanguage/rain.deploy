// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ZoltuDerivationMismatch} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {DeployCandidate, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    CandidateSourceMismatch,
    FrozenSnapshotNotReleased,
    FrozenSnapshotUnreadable,
    RainDeployVerifySnapshot,
    StoredAddressMismatch,
    StoredCodeHashMismatch,
    StoredRuntimeCodeHashMismatch
} from "../../../src/abstract/RainDeployVerifySnapshot.sol";
import {LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {AddressRegistry} from "../../../src/concrete/AddressRegistry.sol";
import {ExampleDeploySuites} from "../../abstract/ExampleDeploySuites.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";
import {
    BYTECODE_HASH as ADDRESS_REGISTRY_BYTECODE_HASH,
    CREATION_CODE as ADDRESS_REGISTRY_CREATION_CODE,
    DEPLOYED_ADDRESS as ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as ADDRESS_REGISTRY_RUNTIME_CODE
} from "../../../src/generated/candidate/AddressRegistry.sol";

/// @title RainDeployVerifySnapshotTest
/// @notice `RainDeployVerifySnapshot` inherited by a exemplar repo, so the
/// inherited tests themselves are the passing case: `ExampleDeploySuites`
/// declares two frozen releases and a candidate, and
/// `testSnapshotInternallyConsistent` /
/// `testSnapshotMatchesSource` run over them here exactly as they
/// would in a consumer.
///
/// The rest is what each group CATCHES, and — for the internal group — what it
/// provably does not. Every case drives the same internal functions the
/// inherited tests do, through external wrappers so `vm.expectRevert` lands at
/// the right call depth, with the exemplar data deliberately broken one field at
/// a time.
contract RainDeployVerifySnapshotTest is ExampleDeploySuites, RainDeployVerifySnapshot {
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

    /// External wrapper for `checkFrozenSnapshotsReleased` so `vm.expectRevert`
    /// works at the correct call depth.
    /// @param paths The frozen record's files.
    /// @param released The declared released suites.
    function externalCheckFrozenSnapshotsReleased(string[] memory paths, DeploySuite[] memory released) external view {
        checkFrozenSnapshotsReleased(paths, released);
    }

    /// External wrapper for `recordedDeployedAddress` so `vm.expectRevert`
    /// works at the correct call depth.
    /// @param path The record file, for the error only.
    /// @param record The record file's contents.
    /// @return The address the record declares.
    function externalRecordedDeployedAddress(string memory path, string memory record) external pure returns (address) {
        return recordedDeployedAddress(path, record);
    }

    /// The real generated snapshot, standing in for a frozen record. It is the
    /// same file a freeze copies into `src/generated/<tag>/`, and the exemplar's
    /// first released suite is declared from it, so the pair below is a real
    /// record checked against a real declaration.
    /// @return paths The one-file record.
    function recordOfTheGeneratedSnapshot() internal pure returns (string[] memory paths) {
        paths = new string[](1);
        paths[0] = LibRainDeploySnapshot.pathForSnapshot(LibRainDeploySnapshot.CANDIDATE, "AddressRegistry");
    }

    /// A record declared by a released suite MUST pass, so the failing cases
    /// below are discriminating rather than a check that cannot succeed.
    function testFrozenSnapshotDeclaredPasses() external view {
        this.externalCheckFrozenSnapshotsReleased(recordOfTheGeneratedSnapshot(), releasedSuites());
    }

    /// A release in the record that the declaration does not name MUST fail,
    /// naming the file. This is the hole the check exists for: nothing else
    /// mentions that release, so without this it is simply never checked again
    /// and every other assertion stays green.
    function testFrozenSnapshotUndeclaredReverts() external {
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotNotReleased.selector, recordOfTheGeneratedSnapshot()[0]));
        this.externalCheckFrozenSnapshotsReleased(recordOfTheGeneratedSnapshot(), new DeploySuite[](0));
    }

    /// The match MUST be against what each suite's creation code derives, not
    /// merely against a declaration existing. A repo that declares SOME
    /// releases and misses one is the case that actually happens, and it is
    /// indistinguishable from a full declaration to anything that only counts.
    function testFrozenSnapshotDeclaredByAnotherSuiteReverts() external {
        DeploySuite[] memory wrongRelease = new DeploySuite[](1);
        wrongRelease[0] = releasedSuites()[1];
        assertEq(wrongRelease[0].suite, "second-address");

        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotNotReleased.selector, recordOfTheGeneratedSnapshot()[0]));
        this.externalCheckFrozenSnapshotsReleased(recordOfTheGeneratedSnapshot(), wrongRelease);
    }

    /// A record in the generated shape that DECLARES one address and merely
    /// mentions another — in a comment, and in a second address constant.
    /// @param declared The address the record declares as its deploy address.
    /// @param mentioned The address the record only mentions.
    /// @return The record's contents.
    function recordDeclaring(address declared, address mentioned) internal pure returns (string memory) {
        return string.concat(
            "// THIS FILE IS AUTOGENERATED BY THE BUILD SCRIPT. DO NOT EDIT BY HAND.\n\n",
            "/// @dev The deterministic deploy address of the contract, which is not\n/// ",
            vm.toString(mentioned),
            ".\n",
            "address constant DEPLOYED_ADDRESS = address(",
            vm.toString(declared),
            ");\n\n",
            "/// @dev Some other address this record carries.\n",
            "address constant OTHER_ADDRESS = address(",
            vm.toString(mentioned),
            ");\n"
        );
    }

    /// The address a record is matched on MUST be the one it DECLARES, never
    /// one that merely appears in its text. A record is two hex payloads
    /// thousands of digits long plus a comment or two, so "this address occurs
    /// somewhere in the file" is a question about characters rather than about
    /// what was deployed — and it answers yes for a release the declaration
    /// never named.
    ///
    /// Driven at the read rather than through a record on disk: a record whose
    /// text carries a released address it does not declare cannot be built out
    /// of this repo's real snapshots without grinding creation code for one,
    /// and a `.sol` fixture left behind by a failed run is a file the next
    /// build has to compile.
    function testFrozenSnapshotMatchesTheDeclarationNotTheText() external view {
        address released = LibRainDeploy.zoltuAddress(releasedSuites()[0].creationCode);
        assertEq(released, ADDRESS_REGISTRY_DEPLOYED_ADDRESS);

        string memory record = recordDeclaring(address(0xdead), released);
        // The released address really is in there.
        assertTrue(vm.contains(record, vm.toString(released)));

        assertEq(this.externalRecordedDeployedAddress("record.sol", record), address(0xdead));
    }

    /// A file in the record that declares no deploy address at all MUST fail as
    /// unreadable, naming itself. Reporting it as undeclared would send the
    /// reader to `releasedSuites()` to add an entry for something that is not a
    /// snapshot.
    function testFrozenSnapshotWithoutADeployedAddressReverts() external {
        string[] memory paths = new string[](1);
        paths[0] = "src/concrete/AddressRegistry.sol";

        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, paths[0]));
        this.externalCheckFrozenSnapshotsReleased(paths, releasedSuites());
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
                suite: "address-registry-candidate",
                creationCode: ADDRESS_REGISTRY_CREATION_CODE,
                storedDeployedAddress: ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
                storedBytecodeHash: ADDRESS_REGISTRY_BYTECODE_HASH,
                storedRuntimeCode: ADDRESS_REGISTRY_RUNTIME_CODE,
                artifactPath: "src/concrete/AddressRegistry.sol:AddressRegistry",
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
            suite: "address-registry-0-0-1",
            creationCode: ADDRESS_REGISTRY_CREATION_CODE,
            storedDeployedAddress: ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
            storedBytecodeHash: ADDRESS_REGISTRY_BYTECODE_HASH,
            storedRuntimeCode: ADDRESS_REGISTRY_RUNTIME_CODE,
            artifactPath: "src/concrete/AddressRegistry.sol:AddressRegistry",
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
                StoredAddressMismatch.selector,
                "address-registry-0-0-1",
                address(0xdead),
                ADDRESS_REGISTRY_DEPLOYED_ADDRESS
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
                StoredCodeHashMismatch.selector,
                "address-registry-0-0-1",
                bytes32(uint256(1)),
                ADDRESS_REGISTRY_BYTECODE_HASH
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
                "address-registry-0-0-1",
                ADDRESS_REGISTRY_BYTECODE_HASH,
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
        assertEq(keccak256(candidate.snapshot.creationCode), keccak256(type(AddressRegistry).creationCode));

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
                "address-registry-candidate",
                keccak256(ADDRESS_REGISTRY_CREATION_CODE),
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
    function testSuitesSharingCreationCodeAllDerive() external {
        DeploySuite[] memory suites = allSuites();
        assertEq(suites.length, 3);
        assertEq(suites[0].storedDeployedAddress, suites[2].storedDeployedAddress);
        assertEq(keccak256(suites[0].creationCode), keccak256(suites[2].creationCode));

        // Neither derivation is disturbed by the other.
        this.externalCheckInternallyConsistent(suites[0]);
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
            ADDRESS_REGISTRY_CREATION_CODE,
            abi.encodePacked(bytes20(LibRainDeploy.ZOLTU_FACTORY))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ZoltuDerivationMismatch.selector,
                "address-registry-0-0-1",
                ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
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
