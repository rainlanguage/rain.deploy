// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DerivedDeploy, RainDeployVerifyBase} from "./RainDeployVerifyBase.sol";
import {DeploySuite} from "./RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../lib/LibRainDeploy.sol";
import {LibRainDeploySnapshot} from "../lib/LibRainDeploySnapshot.sol";

/// Thrown when the deploy address recorded for a version is not the address its
/// own creation code derives.
/// @param suite The suite that failed.
/// @param storedAddress The address the suite records.
/// @param derivedAddress The address its creation code derives.
error StoredAddressMismatch(string suite, address storedAddress, address derivedAddress);

/// Thrown when the deployed code hash recorded for a version is not the hash
/// its own creation code produces.
/// @param suite The suite that failed.
/// @param storedCodeHash The code hash the suite records.
/// @param derivedCodeHash The code hash its creation code produces.
error StoredCodeHashMismatch(string suite, bytes32 storedCodeHash, bytes32 derivedCodeHash);

/// Thrown when the runtime code recorded for a version does not hash to the
/// code hash recorded beside it.
/// @param suite The suite that failed.
/// @param storedBytecodeHash The code hash the suite records.
/// @param runtimeCodeHash The hash of the runtime code the suite records.
error StoredRuntimeCodeHashMismatch(string suite, bytes32 storedBytecodeHash, bytes32 runtimeCodeHash);

/// Thrown when a file in the frozen record is declared by no released suite.
/// The record is append-only, so this never goes away by itself: a release the
/// declaration missed is a release the chain group never asks about, and the
/// chain group passing means nothing for it.
/// @param path The frozen record file no released suite declares.
error FrozenSnapshotNotReleased(string path);

/// Thrown when a file in the frozen record declares no deployed address. The
/// record holds generated snapshots and nothing else, and `DEPLOYED_ADDRESS` is
/// what makes one the record of a deployment rather than a file that happens to
/// be in a release directory. Distinct from `FrozenSnapshotNotReleased`, which
/// is a declaration that is missing something — this is a record that cannot be
/// read at all, and reporting it as undeclared would send the reader after the
/// wrong thing.
/// @param path The record file with no `DEPLOYED_ADDRESS` declaration.
error FrozenSnapshotUnreadable(string path);

/// @title RainDeployVerifySnapshot
/// @notice Every deploy-pin assertion that needs no network, for every suite
/// a repo declares. Three groups, which catch different things and are
/// documented as such because it is easy to read the first as covering the
/// second.
///
/// **Internal to the recorded set.** The address a suite's creation code
/// derives is the address it records, the code hash that creation code produces
/// is the code hash it records, and the runtime code it records hashes to that
/// same code hash. These are real derivations and they catch a set generated
/// inconsistently — a hand-edited constant, a snapshot regenerated for one
/// field and not the others, an address copied from the wrong tag.
///
/// They CANNOT catch a snapshot of the wrong contract. A consistent snapshot of
/// the wrong thing satisfies all three, because all three only ask the recorded
/// bytes to agree with each other, and the wrong contract's bytes agree with
/// each other perfectly.
///
/// **Anchored to source.** The candidate's recorded creation code is the
/// creation code this repo compiles. This is the only check in the whole suite
/// that catches a snapshot of the wrong contract, and it applies to the
/// candidate alone: a released tag is meant to have diverged from current
/// source, so anchoring one to source asserts something that is false by
/// design.
///
/// That one is not defined here. It lives on `RainDeploySuitesBase`, because
/// `RainDeployBroadcast` runs it before it broadcasts and cannot reach anything
/// on this side — this inherits `Test`. Here it is a test; there it is the last
/// thing standing between a stale generated file and a permanent `CREATE2`
/// address on every chain a dispatch reaches.
///
/// **Anchored to the record.** Every file in the frozen record — the
/// append-only `src/generated/<tag>/` directories — is declared by a released
/// suite. This is the one check that is about the DECLARATION rather than about
/// what a declared suite records, and it exists because everything anchored to
/// a chain reads `releasedSuites()`, which is a separate file from the record
/// it describes. A release missing from it is not caught anywhere else, by
/// anything: it simply stops being checked, and every check there is stays
/// green.
///
/// None of the three can catch a suite that was never deployed, or that is no
/// longer deployed. Only `RainDeployVerifyChain` can, and nothing here is a
/// substitute for it — but the record check is what makes its scope complete,
/// because a release it is never handed is a release it cannot fail on.
abstract contract RainDeployVerifySnapshot is RainDeployVerifyBase {
    /// Checks one suite against itself: derive from its creation code, then
    /// require everything it records to agree with the derivation.
    /// @param suite The suite to check.
    function checkInternallyConsistent(DeploySuite memory suite) internal {
        DerivedDeploy memory derived = deriveDeployment(suite);

        if (suite.storedDeployedAddress != derived.deployedAddress) {
            revert StoredAddressMismatch(suite.suite, suite.storedDeployedAddress, derived.deployedAddress);
        }

        if (suite.storedBytecodeHash != derived.bytecodeHash) {
            revert StoredCodeHashMismatch(suite.suite, suite.storedBytecodeHash, derived.bytecodeHash);
        }

        bytes32 runtimeCodeHash = keccak256(suite.storedRuntimeCode);
        if (suite.storedBytecodeHash != runtimeCodeHash) {
            revert StoredRuntimeCodeHashMismatch(suite.suite, suite.storedBytecodeHash, runtimeCodeHash);
        }
    }

    /// @dev The declaration a generated snapshot records its deploy address in.
    /// Matched whole and from the START of its line, so what is being looked
    /// for is the DECLARATION: it cannot be satisfied by characters that happen
    /// to occur inside a hex payload, nor by a line that merely CONTAINS the
    /// declaration text — a commented-out copy carrying some other address is
    /// exactly the hand edit this whole group exists to catch, and it is at
    /// file scope in every generated snapshot, so there is no indentation to
    /// allow for.
    string constant DEPLOYED_ADDRESS_DECLARATION = "address constant DEPLOYED_ADDRESS =";

    /// The address a frozen record declares as its deploy address.
    ///
    /// `LibCodeGen` emits an address constant on ONE line — wrapping needs 120
    /// characters and this declaration occupies 88 — so the declaration is a
    /// line, and its value is that line's last token with the type wrapper and
    /// the terminator stripped. `address(0x...);` and a bare `0x...;` read the
    /// same, so which wrapper the generator chose is not something this has to
    /// know.
    ///
    /// That every generated snapshot HAS this declaration, second, of type
    /// `address`, is pinned by `GeneratedSnapshotShapeTest` against the
    /// compiler's own AST. Read from the text here rather than from that AST
    /// because a record is reached by its PATH, which is what the walk returns,
    /// while its artifact path is not something a caller can name — foundry
    /// disambiguates those by whatever else happens to share the basename.
    /// @param path The record file, for the error only.
    /// @param record The record file's contents.
    /// @return The address the record declares.
    function recordedDeployedAddress(string memory path, string memory record) internal pure returns (address) {
        string[] memory lines = vm.split(record, "\n");
        for (uint256 i = 0; i < lines.length; i++) {
            if (vm.indexOf(lines[i], DEPLOYED_ADDRESS_DECLARATION) != 0) {
                continue;
            }
            string[] memory tokens = vm.split(lines[i], " ");
            string memory literal = tokens[tokens.length - 1];
            return vm.parseAddress(vm.replace(vm.replace(vm.replace(literal, "address(", ""), ")", ""), ";", ""));
        }
        revert FrozenSnapshotUnreadable(path);
    }

    /// Checks the frozen record against the released declaration: every file in
    /// the record is declared by a released suite.
    ///
    /// `releasedSuites()` is a generated file, and everything anchored to a
    /// chain reads it. A frozen tag it does not name is therefore not a missing
    /// entry that shows up as a failure somewhere — it is a release that drops
    /// out of every check there is, silently and permanently, while the whole
    /// suite stays green. The record is the only thing that can say it
    /// happened, so the declaration is checked against the record.
    ///
    /// Emitting the declaration from the record is what makes the two agree in
    /// the first place. This is what catches the ways they still come apart: a
    /// hand edit to the generated file, a record directory that arrived out of
    /// band, and a generated file nobody regenerated after the record moved.
    /// Nothing in CI regenerates anything, so a stale generated file is caught
    /// here or not at all.
    ///
    /// Matched against the RELEASED suites alone, deliberately. A release and
    /// the rolling candidate are byte-identical from the moment the release is
    /// cut until source next moves, so a match against every declared suite
    /// would let the candidate declare a frozen release — and the candidate is
    /// exactly what the chain group does not check.
    ///
    /// The match is by address: the address a file DECLARES against the address
    /// a suite's creation code DERIVES. The derived side is a pure function of
    /// the creation code, so a suite whose creation code derives the address a
    /// file records IS that file's release.
    ///
    /// Nothing is matched by name, which would assert only that a convention
    /// was followed. Nothing is matched by searching the file's text either: a
    /// record is mostly two hex payloads thousands of digits long, and an
    /// address that merely OCCURS somewhere in one of them says nothing about
    /// what the file records.
    /// @param paths The frozen record's files.
    /// @param released The declared released suites.
    function checkFrozenSnapshotsReleased(string[] memory paths, DeploySuite[] memory released) internal view {
        for (uint256 i = 0; i < paths.length; i++) {
            address recorded = recordedDeployedAddress(paths[i], vm.readFile(paths[i]));

            bool declared = false;
            for (uint256 j = 0; j < released.length; j++) {
                if (recorded == LibRainDeploy.zoltuAddress(released[j].creationCode)) {
                    declared = true;
                    break;
                }
            }

            if (!declared) {
                revert FrozenSnapshotNotReleased(paths[i]);
            }
        }
    }

    /// Every declared suite MUST be internally consistent: what it records is
    /// what its own creation code derives.
    function testSnapshotInternallyConsistent() external {
        DeploySuite[] memory suites = allSuites();
        for (uint256 i = 0; i < suites.length; i++) {
            checkInternallyConsistent(suites[i]);
        }
    }

    /// EVERY candidate MUST be a snapshot of the contract this repo compiles,
    /// not of some other contract that happens to be internally consistent.
    ///
    /// The check itself is `RainDeploySuitesBase.checkCandidatesAnchoredToSource`
    /// rather than anything here, because `RainDeployBroadcast` runs the same
    /// definition before it broadcasts. A second spelling on this side is a
    /// spelling the deploy does not run, which is exactly the state this test
    /// would otherwise be reporting green about.
    function testSnapshotMatchesSource() external pure {
        checkCandidatesAnchoredToSource();
    }

    /// Every release in the frozen record MUST be declared, so that the set the
    /// chain group checks is every release this repo has ever cut rather than
    /// the ones somebody remembered to list.
    ///
    /// An empty walk passes, and is meant to: that is the state of every deploy
    /// repo before its first release. What makes it safe is that the root is
    /// the one a snapshot is WRITTEN to — `LIB_FS_ROOT` is the only spelling of
    /// it in `LibRainDeploySnapshot` and `testRecordRootIsTheRootTheWriterWritesTo`
    /// pins it against `LibFs`'s. Under the writer's own root, finding nothing
    /// means there is nothing; under any other, the walk returns an empty list
    /// forever, this passes with no subject, and the one check standing between
    /// a release dropping out of everything and a green suite is inert.
    ///
    /// Deliberately NOT also guarded by comparing the record's size against the
    /// declaration's. The two are emitted one-for-one by `writeReleasedSuitesLib`
    /// for a repo that generates its declaration from its record, but this is
    /// inherited by any repo that overrides `releasedSuites`, and a declaration
    /// with no record behind it is a state such a repo is legitimately in: a
    /// release deployed before it adopted this machinery has no frozen record
    /// and never will. A size check would red-line that permanently with no way
    /// to spell the exemption, while the release it names goes on being checked
    /// by everything anchored to a chain.
    function testEveryFrozenSnapshotIsReleased() external view {
        checkFrozenSnapshotsReleased(
            LibRainDeploySnapshot.frozenSnapshotPaths(vm, LibRainDeploySnapshot.LIB_FS_ROOT), releasedSuites()
        );
    }
}
