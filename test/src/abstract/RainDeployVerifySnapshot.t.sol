// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ZoltuDerivationMismatch} from "../../../src/abstract/RainDeployVerifyBase.sol";
import {CandidateSourceMismatch, DeployCandidate, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    FrozenSnapshotNotReleased,
    FrozenSnapshotUnreadable,
    RainDeployVerifySnapshot,
    StoredAddressMismatch,
    StoredCodeHashMismatch,
    StoredRuntimeCodeHashMismatch
} from "../../../src/abstract/RainDeployVerifySnapshot.sol";
import {LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ExampleDeploySuites} from "../../abstract/ExampleDeploySuites.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";
import {SourceMismatchDeploy} from "../../concrete/SourceMismatchDeploy.sol";
import {
    BYTECODE_HASH as ADDRESS_REGISTRY_BYTECODE_HASH,
    CREATION_CODE as ADDRESS_REGISTRY_CREATION_CODE,
    DEPLOYED_ADDRESS as ADDRESS_REGISTRY_DEPLOYED_ADDRESS,
    RUNTIME_CODE as ADDRESS_REGISTRY_RUNTIME_CODE
} from "../../../src/generated/candidate/AddressRegistry.sol";

/// @title RainDeployVerifySnapshotTest
/// @notice `RainDeployVerifySnapshot` inherited by a exemplar repo, so the
/// inherited tests themselves are the passing case: `ExampleDeploySuites`
/// declares two frozen releases and two candidates, and
/// `testSnapshotInternallyConsistent` /
/// `testSnapshotMatchesSource` run over them here exactly as they
/// would in a consumer.
///
/// The rest is what each group CATCHES, and — for the internal group — what it
/// provably does not. Every case drives the same internal functions the
/// inherited tests do, at a call depth `vm.expectRevert` lands at.
///
/// The groups that take their subject as an argument are driven with the
/// exemplar data deliberately broken one field at a time. The source anchor
/// takes none: it reads the declaration, because `RainDeployBroadcast` runs it
/// with nothing to hand it. Its negative case is therefore a whole broken
/// DECLARATION — `SourceMismatchDeploy` — which is also the shape a repo holding
/// a stale generated file is actually in.
contract RainDeployVerifySnapshotTest is ExampleDeploySuites, RainDeployVerifySnapshot {
    /// A declaration whose second candidate is a consistent snapshot of the
    /// wrong contract.
    ///
    /// A whole declaration rather than a candidate built here, because the
    /// source anchor reads the declaration itself — it has to, so that the
    /// broadcast can run the same definition without being handed anything.
    /// A set passed in as an argument would be a set only a test can supply.
    SourceMismatchDeploy internal sMismatch;

    /// The broken declaration, as a repo holding a stale generated file has it.
    function setUp() external {
        sMismatch = new SourceMismatchDeploy();
    }

    /// External wrapper for `checkInternallyConsistent` so `vm.expectRevert`
    /// works at the correct call depth.
    /// @param suite The suite to check.
    function externalCheckInternallyConsistent(DeploySuite memory suite) external {
        checkInternallyConsistent(suite);
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

    /// A record of BOTH committed snapshots. `AddressRegistry` is what the
    /// exemplar's first released suite derives; `MigrationRegistry` is declared
    /// by no released suite here, so it is a real record file that really is
    /// undeclared, and the undeclared one is the LAST.
    /// @return paths The two-file record.
    function recordOfBothGeneratedSnapshots() internal pure returns (string[] memory paths) {
        paths = new string[](2);
        paths[0] = LibRainDeploySnapshot.pathForSnapshot(LibRainDeploySnapshot.CANDIDATE, "AddressRegistry");
        paths[1] = LibRainDeploySnapshot.pathForSnapshot(LibRainDeploySnapshot.CANDIDATE, "MigrationRegistry");
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

    /// A record in the generated shape whose real declaration is preceded by a
    /// COMMENTED OUT one. The commented line is the declaration text verbatim,
    /// which is what separates this from a prose mention of an address.
    /// @param declared The address the record's real declaration carries.
    /// @param commented The address the commented-out declaration carries.
    /// @return The record's contents.
    function recordCommentingOutADeclaration(address declared, address commented)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "// THIS FILE IS AUTOGENERATED BY THE BUILD SCRIPT. DO NOT EDIT BY HAND.\n\n",
            "/// @dev The deterministic deploy address of the contract.\n",
            "// address constant DEPLOYED_ADDRESS = address(",
            vm.toString(commented),
            ");\n",
            "address constant DEPLOYED_ADDRESS = address(",
            vm.toString(declared),
            ");\n"
        );
    }

    /// The declaration a record is read from MUST be the one the COMPILER
    /// would read. A commented-out declaration is text, and taking it would let
    /// a hand edit park a released address above a real declaration carrying
    /// something else — the file would then match a released suite while
    /// declaring an address no suite derives, which is precisely the hand edit
    /// this group exists to catch. The parser cannot be the thing that swallows
    /// it.
    function testFrozenSnapshotIgnoresACommentedOutDeclaration() external view {
        address released = LibRainDeploy.zoltuAddress(releasedSuites()[0].creationCode);
        assertEq(released, ADDRESS_REGISTRY_DEPLOYED_ADDRESS);

        string memory record = recordCommentingOutADeclaration(address(0xdead), released);
        // The commented-out line really is the declaration text, carrying the
        // released address: only its position makes it a comment.
        assertTrue(vm.contains(record, string.concat("// ", DEPLOYED_ADDRESS_DECLARATION)));
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

    /// EVERY file in the record MUST be checked, not just the first. The
    /// undeclared file here is the LAST one, behind a declared one, so a loop
    /// that stopped after the first path would pass — and a release that
    /// dropped out of the declaration is exactly what this check exists to
    /// catch, on a record that grows one file per release.
    function testFrozenSnapshotCheckReachesEveryRecordFile() external {
        // The first really is declared, so nothing fails before the loop has to
        // advance.
        string[] memory first = new string[](1);
        first[0] = recordOfBothGeneratedSnapshots()[0];
        this.externalCheckFrozenSnapshotsReleased(first, releasedSuites());

        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotNotReleased.selector, recordOfBothGeneratedSnapshots()[1]));
        this.externalCheckFrozenSnapshotsReleased(recordOfBothGeneratedSnapshots(), releasedSuites());
    }

    /// An unreadable file MUST be named as the file the loop is ON. Its path is
    /// carried into the read for that error alone, so a loop that advanced but
    /// kept handing the read `paths[0]` would send the reader to a file that
    /// reads perfectly well — and every position after the first is where a
    /// record spends its life from the second release onward.
    function testFrozenSnapshotUnreadableFileIsNamedAtEveryRecordPosition() external {
        string[] memory paths = new string[](2);
        // Declared and readable, so nothing fails before the loop has to
        // advance.
        paths[0] = recordOfTheGeneratedSnapshot()[0];
        paths[1] = "src/concrete/AddressRegistry.sol";

        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, paths[1]));
        this.externalCheckFrozenSnapshotsReleased(paths, releasedSuites());
    }

    /// The inner search MUST reach every released suite, not just the first.
    /// The suite that declares the record here is the LAST one, so a match that
    /// only ever looked at `released[0]` would report a declared release as
    /// undeclared and make the check unusable the moment a repo releases twice.
    function testFrozenSnapshotCheckReachesEveryReleasedSuite() external view {
        DeploySuite[] memory released = releasedSuites();
        // `second-address` first, `address-registry-0-0-1` second.
        DeploySuite[] memory reordered = new DeploySuite[](2);
        reordered[0] = released[1];
        reordered[1] = released[0];
        assertEq(reordered[1].suite, "address-registry-0-0-1");

        this.externalCheckFrozenSnapshotsReleased(recordOfTheGeneratedSnapshot(), reordered);
    }

    /// An empty declaration against a record with several files fails on the
    /// FIRST file, naming it: a repo that declared nothing is not a repo with
    /// nothing frozen, and the file it names is the one it is on rather than
    /// the last one in the record.
    function testFrozenSnapshotEmptyDeclarationFailsOnTheFirstRecordFile() external {
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotNotReleased.selector, recordOfBothGeneratedSnapshots()[0]));
        this.externalCheckFrozenSnapshotsReleased(recordOfBothGeneratedSnapshots(), new DeploySuite[](0));
    }

    /// A record with no files at all is a repo that has released nothing —
    /// which is this repo's own state — and MUST pass rather than fail on a
    /// declaration it has nothing to check against. This is the deliberate
    /// opposite of the source anchor, which refuses an empty candidate list:
    /// there, an empty list is a repo whose snapshots nothing anchors; here, it
    /// is a repo that has frozen nothing yet.
    function testFrozenSnapshotEmptyRecordPasses() external view {
        this.externalCheckFrozenSnapshotsReleased(new string[](0), releasedSuites());
        this.externalCheckFrozenSnapshotsReleased(new string[](0), new DeploySuite[](0));
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
        DeployCandidate memory candidate = sMismatch.externalCheckedCandidateSuites()[1];

        // It really is the wrong contract: the snapshot records `MockDeployableV2`
        // while the source it claims to be is `MockDeployable`.
        assertEq(keccak256(candidate.snapshot.creationCode), keccak256(type(MockDeployableV2).creationCode));
        assertEq(keccak256(candidate.sourceCreationCode), keccak256(type(MockDeployable).creationCode));
        assertNotEq(keccak256(candidate.snapshot.creationCode), keccak256(candidate.sourceCreationCode));

        // Every internal check passes anyway.
        this.externalCheckInternallyConsistent(candidate.snapshot);
    }

    /// The source-anchored group MUST catch exactly the snapshot the internal
    /// group just let through, MUST reach every candidate to do it, and MUST
    /// name the one that failed. This is the only check in the whole suite that
    /// can catch any of it.
    ///
    /// The broken candidate is the LAST one, behind a genuinely anchored one. A
    /// loop that stops early is invisible while a repo declares one candidate
    /// and silently stops anchoring the moment it declares two — and a repo with
    /// several contracts is precisely where a snapshot generated from the wrong
    /// one comes from. The failure naming the SECOND key is what separates a
    /// loop that reached it from one that reported a fixed entry or the first.
    ///
    /// The inherited `testSnapshotMatchesSource` is the passing case: it runs
    /// this same function over `ExampleDeploySuites`, whose candidates are their
    /// own source.
    function testWrongContractSnapshotCaughtBySource() external {
        DeployCandidate[] memory candidates = sMismatch.externalCheckedCandidateSuites();
        assertEq(candidates.length, 2);

        // The first is genuinely anchored, so nothing fails before the loop has
        // to advance, and it is a different contract at a different address
        // rather than the same entry under two keys.
        assertEq(candidates[0].snapshot.suite, "anchored-candidate");
        assertEq(keccak256(candidates[0].snapshot.creationCode), keccak256(candidates[0].sourceCreationCode));
        assertNotEq(candidates[0].snapshot.storedDeployedAddress, candidates[1].snapshot.storedDeployedAddress);

        vm.expectRevert(
            abi.encodeWithSelector(
                CandidateSourceMismatch.selector,
                "mismatched-candidate",
                keccak256(type(MockDeployableV2).creationCode),
                keccak256(type(MockDeployable).creationCode)
            )
        );
        sMismatch.externalCheckCandidatesAnchoredToSource();
    }

    /// Two suites that record the SAME creation code MUST both derive, which
    /// is the ordinary state of a repo between a release and the next source
    /// change. `address-registry-0-0-1` and `address-registry-candidate` are
    /// the same bytes and therefore the same address, and the whole set still
    /// passes.
    function testSuitesSharingCreationCodeAllDerive() external {
        DeploySuite[] memory suites = allSuites();
        assertEq(suites.length, 4);
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

    /// The record is matched on the address a released suite's creation code
    /// DERIVES, never on the address that suite RECORDS.
    ///
    /// The two are the same in a consistent set, which is what makes this worth
    /// stating: a suite whose recorded address has gone stale still deployed
    /// what its creation code deploys, so it still declares that release — and
    /// the stale field is `checkInternallyConsistent`'s to catch, with an error
    /// that names it. Matching on the recorded field instead reports a declared
    /// release as one nobody declared, and sends the reader to
    /// `releasedSuites()` to add an entry that is already there.
    ///
    /// The suite here is the record's own release with that one field broken,
    /// so the derivation is the only thing left that can match it.
    function testFrozenSnapshotMatchesTheDerivationNotTheRecordedAddress() external view {
        DeploySuite[] memory released = new DeploySuite[](1);
        released[0] = consistentSuite();
        released[0].storedDeployedAddress = address(0xdead);

        // It really is the record's release, and it really does record
        // something else.
        assertEq(LibRainDeploy.zoltuAddress(released[0].creationCode), ADDRESS_REGISTRY_DEPLOYED_ADDRESS);
        assertNotEq(released[0].storedDeployedAddress, ADDRESS_REGISTRY_DEPLOYED_ADDRESS);

        this.externalCheckFrozenSnapshotsReleased(recordOfTheGeneratedSnapshot(), released);
    }

    /// The inherited internal-consistency check MUST reach EVERY declared
    /// suite.
    ///
    /// Every negative case above drives `checkInternallyConsistent` with one
    /// suite handed to it, so all of them pass on a check that only ever looked
    /// at the first — and a repo declares one suite until the day it declares
    /// several, which is the day a snapshot regenerated for one contract and
    /// not the other appears. The suite broken here is not the first, so a loop
    /// that stopped there would find nothing to fail on.
    ///
    /// Broken through the factory rather than by editing a field, because the
    /// declaration this contract inherits is the passing case for the inherited
    /// tests and cannot be broken in place. The mock is
    /// `testZoltuDerivationMismatchReverts`'s, keyed on the creation code of the
    /// suite being reached rather than of the first one.
    function testSnapshotInternallyConsistentReachesEverySuite() external {
        DeploySuite[] memory suites = allSuites();
        assertEq(suites[1].suite, "second-address");
        assertNotEq(keccak256(suites[0].creationCode), keccak256(suites[1].creationCode));

        vm.mockCall(
            LibRainDeploy.ZOLTU_FACTORY, suites[1].creationCode, abi.encodePacked(bytes20(LibRainDeploy.ZOLTU_FACTORY))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ZoltuDerivationMismatch.selector,
                "second-address",
                suites[1].storedDeployedAddress,
                LibRainDeploy.ZOLTU_FACTORY
            )
        );
        this.testSnapshotInternallyConsistent();
    }

    /// The derivation MUST clear the derived address's NONCE, not only its
    /// code.
    ///
    /// `CREATE2` collides on a non-zero nonce exactly as it does on non-empty
    /// code, and the nonce is the half that leaves nothing to see: an account
    /// with a nonce and no code reads as empty everywhere else, so a derivation
    /// that cleared only the code would report a deployment failure for a
    /// creation code that deploys perfectly well. The Zoltu factory is
    /// permissionless, so whether anything has ever transacted from the address
    /// a suite derives is nobody's to control.
    function testDerivationClearsTheDerivedNonce() external {
        DeploySuite memory suite = consistentSuite();
        vm.setNonce(suite.storedDeployedAddress, 1);
        assertEq(vm.getNonce(suite.storedDeployedAddress), 1);
        assertEq(suite.storedDeployedAddress.code.length, 0);

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
