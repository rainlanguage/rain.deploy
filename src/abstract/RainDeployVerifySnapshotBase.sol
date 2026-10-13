// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DerivedDeploy, RainDeployVerifyBase} from "./RainDeployVerifyBase.sol";
import {DeploySuite} from "./RainDeploySuitesBase.sol";
import {LibRainDeployMechanism} from "../lib/LibRainDeployMechanism.sol";

/// Thrown when the deploy address recorded for a version is not the address its
/// own mechanism derives.
/// @param suite The suite that failed.
/// @param storedAddress The address the suite records.
/// @param derivedAddress The address its mechanism derives.
error StoredAddressMismatch(string suite, address storedAddress, address derivedAddress);

/// Thrown when the deployed code hash recorded for a version is not the hash
/// its own mechanism produces.
/// @param suite The suite that failed.
/// @param storedCodeHash The code hash the suite records.
/// @param derivedCodeHash The code hash its mechanism produces.
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

/// Thrown when the frozen record holds more files recording one deploy address
/// list than the declaration holds released suites deriving it.
/// @param path The record file the record ran out of declarations at.
/// @param deployedAddresses The addresses that file declares, in file order.
/// @param records The record files declaring them, up to and including `path`.
/// @param released The released suites whose mechanism derives them.
error FrozenSnapshotsOutnumberReleases(string path, address[] deployedAddresses, uint256 records, uint256 released);

/// Thrown when a file in the frozen record declares no deployed address. The
/// record holds generated snapshots and nothing else, and `DEPLOYED_ADDRESS` is
/// what makes one the record of a deployment rather than a file that happens to
/// be in a release directory. Distinct from `FrozenSnapshotNotReleased`, which
/// is a declaration that is missing something — this is a record that cannot be
/// read at all, and reporting it as undeclared would send the reader after the
/// wrong thing.
/// @param path The record file with no `DEPLOYED_ADDRESS` or
/// `DEPLOYED_ADDRESS_<chainId>` declaration.
error FrozenSnapshotUnreadable(string path);

/// Thrown when a file in the frozen record declares its deployed address more
/// than once: `DEPLOYED_ADDRESS` twice, one `DEPLOYED_ADDRESS_<chainId>` twice,
/// or `DEPLOYED_ADDRESS` beside any `DEPLOYED_ADDRESS_<chainId>`. Solidity
/// rejects a second file-scope constant of one name, so no compiler reads the
/// first two at all, and the third is two answers to where the release is.
/// Every rule for choosing between them — first, last, either — reads a value
/// the generator never wrote. A hand edit is what this group exists to catch and a position rule is what it
/// would aim at, so the reader refuses rather than choosing.
/// @param path The record file declaring its deployed address more than once.
error FrozenSnapshotAmbiguous(string path);

/// @title RainDeployVerifySnapshotBase
/// @notice Every deploy-pin assertion that needs no network, for every suite
/// a repo declares. Three groups, which catch different things and are
/// documented as such because it is easy to read the first as covering the
/// second.
///
/// **Internal to the recorded set.** The address a suite's mechanism
/// derives is the address it records, the code hash that mechanism produces
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
/// suite OF ITS OWN, one for one. This is the one check that is about the
/// DECLARATION rather than about what a declared suite records, and it exists
/// because everything anchored to a chain reads `releasedSuites()`, which is a
/// separate file from the record it describes. A release missing from it is not
/// caught anywhere else, by anything: it simply stops being checked, and every
/// check there is stays green.
///
/// None of the three can catch a suite that was never deployed, or that is no
/// longer deployed. Only `RainDeployVerifyChain` can, and nothing here is a
/// substitute for it — but the record check is what makes its scope complete,
/// because a release it is never handed is a release it cannot fail on.
///
/// ## What this contract is, and what a deploy repo inherits instead
///
/// This holds the third group's CHECK and not its BINDING. Everything defined
/// here takes its subject as an argument or from the inheriting contract's own
/// declaration, so a contract whose declaration is a fixture is a contract this
/// says true things about. `RainDeployVerifySnapshot` is this plus the one test
/// that binds the third group to the repo's real record on disk, and it is
/// what a deploy repo inherits — the whole of the split is which contract
/// carries that one test.
///
/// The split exists because that test's subject is `LibRainDeploySnapshot`'s
/// single spelling of the record root and never the inheriting contract's
/// declaration, which makes it the one assertion here that is FALSE of a
/// fixture: a harness declaring exemplar suites, inheriting it, would be
/// asserting that this repo's real releases are declared by that exemplar. It
/// passes while the repo has released nothing and fails on the first real
/// release, having said nothing about the abstracts in between.
///
/// A `virtual` root, or a `virtual` test to override, would be the same split
/// spelled as an opt-out, and an opt-out is what the record check cannot have:
/// see the essay on `testEveryFrozenSnapshotIsReleased` for why the root has
/// one spelling. Inheriting a narrower contract is a choice a reader sees in
/// the inheritance list; overriding a test to nothing is one they do not.
abstract contract RainDeployVerifySnapshotBase is RainDeployVerifyBase {
    /// Checks one suite against itself: derive through its mechanism, then
    /// require everything it records to agree with the derivation.
    /// @param suite The suite to check.
    function checkInternallyConsistent(DeploySuite memory suite) internal {
        DerivedDeploy memory derived = deriveDeployment(suite);

        // Both lists are in the suite's address order, from the same decode of
        // the same suite, so they pair by position.
        address[] memory recorded = LibRainDeployMechanism.recordedAddresses(suite);
        for (uint256 i = 0; i < recorded.length; i++) {
            if (recorded[i] != derived.deployedAddresses[i]) {
                revert StoredAddressMismatch(suite.suite, recorded[i], derived.deployedAddresses[i]);
            }
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
    ///
    /// The start of a line is what makes a `//` copy unreachable, because `//`
    /// has to sit in front of the text it comments out. It does nothing to a
    /// `/* ... */` copy, whose delimiters are on their own lines and whose
    /// contents therefore start their lines exactly as the real declaration
    /// does. Block comments come out of the record before this rule runs, so
    /// that what it runs on is what the compiler would see.
    string constant DEPLOYED_ADDRESS_DECLARATION = "address constant DEPLOYED_ADDRESS =";

    /// @dev The start of the declaration a per-network snapshot records one
    /// network's deploy address in: `DEPLOYED_ADDRESS_<chainId> =`. Matched
    /// from the start of its line for the reasons `DEPLOYED_ADDRESS_DECLARATION`
    /// is.
    string constant DEPLOYED_ADDRESS_CHAIN_DECLARATION_PREFIX = "address constant DEPLOYED_ADDRESS_";

    /// The addresses a frozen record declares as its deploy addresses, and the
    /// chain id each is for.
    ///
    /// A record declares either ONE `DEPLOYED_ADDRESS`, the address on every
    /// network, or one `DEPLOYED_ADDRESS_<chainId>` per network, which is what
    /// a per-network clone records. The first reads as one address and no
    /// chain ids; the second as each declaration's chain id and address, in
    /// file order — the order the writer emits them, which is the suite's
    /// address order.
    ///
    /// `LibCodeGen` emits an address constant on ONE line — wrapping needs 120
    /// characters, `DEPLOYED_ADDRESS` occupies 88 and `DEPLOYED_ADDRESS_<chainId>`
    /// would need a chain id of more than 31 digits — so a declaration is a
    /// line, and its value is that line's last token with the
    /// type wrapper and the terminator stripped. `address(0x...);` and a bare
    /// `0x...;` read the same, so which wrapper the generator chose is not
    /// something this has to know.
    ///
    /// That every generated snapshot HAS this declaration, second, of type
    /// `address`, is pinned by `GeneratedSnapshotShapeTest` against the
    /// compiler's own AST. Read from the text here rather than from that AST
    /// because a record is reached by its PATH, which is what the walk returns,
    /// while its artifact path is not something a caller can name — foundry
    /// disambiguates those by whatever else happens to share the basename.
    ///
    /// The whole record is scanned before a match is read, so a record
    /// carrying `DEPLOYED_ADDRESS` twice, one chain id twice, or both forms is
    /// refused rather than resolved by position.
    /// @param path The record file, for the error only.
    /// @param record The record file's contents.
    /// @return chainIds The chain id each address is for: empty for a record
    /// declaring `DEPLOYED_ADDRESS`.
    /// @return addresses The addresses the record declares, in file order.
    function recordedDeployedAddresses(string memory path, string memory record)
        internal
        pure
        returns (uint256[] memory chainIds, address[] memory addresses)
    {
        string[] memory lines = vm.split(withoutBlockComments(record), "\n");
        chainIds = new uint256[](lines.length);
        addresses = new address[](lines.length);
        uint256 perNetwork = 0;
        bool everyNetwork = false;
        for (uint256 i = 0; i < lines.length; i++) {
            bool isEveryNetwork = vm.indexOf(lines[i], DEPLOYED_ADDRESS_DECLARATION) == 0;
            if (!isEveryNetwork && vm.indexOf(lines[i], DEPLOYED_ADDRESS_CHAIN_DECLARATION_PREFIX) != 0) {
                continue;
            }
            if (everyNetwork || (isEveryNetwork && perNetwork != 0)) {
                revert FrozenSnapshotAmbiguous(path);
            }
            string[] memory tokens = vm.split(lines[i], " ");
            address declared = vm.parseAddress(
                vm.replace(vm.replace(vm.replace(tokens[tokens.length - 1], "address(", ""), ")", ""), ";", "")
            );
            if (isEveryNetwork) {
                everyNetwork = true;
                addresses[0] = declared;
                continue;
            }
            uint256 chainId = vm.parseUint(vm.replace(tokens[2], "DEPLOYED_ADDRESS_", ""));
            for (uint256 j = 0; j < perNetwork; j++) {
                if (chainIds[j] == chainId) {
                    revert FrozenSnapshotAmbiguous(path);
                }
            }
            chainIds[perNetwork] = chainId;
            addresses[perNetwork] = declared;
            perNetwork++;
        }
        if (!everyNetwork && perNetwork == 0) {
            revert FrozenSnapshotUnreadable(path);
        }
        uint256 chainIdsLength = perNetwork;
        uint256 addressesLength = everyNetwork ? 1 : perNetwork;
        assembly ("memory-safe") {
            mstore(chainIds, chainIdsLength)
            mstore(addresses, addressesLength)
        }
    }

    /// A record's text with every block comment removed, so that a declaration
    /// found in it is one the compiler would read.
    ///
    /// `/*` opens a comment that the first following `*/` closes, and Solidity
    /// does not nest them, so what survives is the text before the first `/*`
    /// plus, for each one after it, the text after its `*/`. An unclosed `/*`
    /// is comment to the end of the file, so nothing after it survives.
    ///
    /// A comment is removed rather than blanked, which joins the text either
    /// side of it into one line exactly as the compiler joins it. A declaration
    /// the compiler reads on the tail of a `*/` is therefore still found, and
    /// one interrupted mid-line by a comment is not — that leaves the record
    /// unreadable, never read as some other address.
    /// @param record The record file's contents.
    /// @return The contents with every block comment removed.
    function withoutBlockComments(string memory record) internal pure returns (string memory) {
        string[] memory opened = vm.split(record, "/*");
        string memory stripped = opened[0];
        for (uint256 i = 1; i < opened.length; i++) {
            string[] memory closed = vm.split(opened[i], "*/");
            if (closed.length == 1) {
                break;
            }
            stripped = string.concat(stripped, closed[1]);
            for (uint256 j = 2; j < closed.length; j++) {
                stripped = string.concat(stripped, "*/", closed[j]);
            }
        }
        return stripped;
    }

    /// Checks the frozen record against the released declaration: every file in
    /// the record is declared by a released suite OF ITS OWN.
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
    /// The match is by address: the addresses a file DECLARES, with the chain
    /// id each is declared for, against the addresses a suite's mechanism
    /// DERIVES, through `LibRainDeployMechanism` — the creation code for a
    /// Zoltu suite, the `CloneTarget` for a clone, each network's entry for a
    /// per-network clone — with the chain id each is for. The whole ordered
    /// list is the identity, so a per-network record matches only a suite
    /// deriving every one of its addresses for the chain id it labels it with.
    /// The derived side is a pure function of the suite, so a suite that
    /// derives the addresses a file records IS a release of what that file
    /// records.
    ///
    /// Nothing is matched by name, which would assert only that a convention
    /// was followed. Nothing is matched by searching the file's text either: a
    /// record is mostly two hex payloads thousands of digits long, and an
    /// address that merely OCCURS somewhere in one of them says nothing about
    /// what the file records.
    ///
    /// A RENAMED entry is not caught: the counts are unchanged.
    /// @param paths The frozen record's files.
    /// @param released The declared released suites.
    function checkFrozenSnapshotsReleased(string[] memory paths, DeploySuite[] memory released) internal view {
        bytes32[] memory releasedIdentities = new bytes32[](released.length);
        for (uint256 j = 0; j < released.length; j++) {
            releasedIdentities[j] = keccak256(
                abi.encode(
                    LibRainDeployMechanism.addressChainIds(released[j]),
                    LibRainDeployMechanism.deployedAddresses(released[j])
                )
            );
        }

        bytes32[] memory recorded = new bytes32[](paths.length);
        for (uint256 i = 0; i < paths.length; i++) {
            (uint256[] memory chainIds, address[] memory addresses) =
                recordedDeployedAddresses(paths[i], vm.readFile(paths[i]));
            recorded[i] = keccak256(abi.encode(chainIds, addresses));

            uint256 declarations = 0;
            for (uint256 j = 0; j < released.length; j++) {
                if (recorded[i] == releasedIdentities[j]) {
                    declarations++;
                }
            }

            if (declarations == 0) {
                revert FrozenSnapshotNotReleased(paths[i]);
            }

            uint256 records = 1;
            for (uint256 k = 0; k < i; k++) {
                if (recorded[k] == recorded[i]) {
                    records++;
                }
            }

            if (records > declarations) {
                revert FrozenSnapshotsOutnumberReleases(paths[i], addresses, records, declarations);
            }
        }
    }

    /// Every declared suite MUST be internally consistent: what it records is
    /// what its own mechanism derives.
    function testSnapshotInternallyConsistent() external {
        DeploySuite[] memory suites = allSuites();
        for (uint256 i = 0; i < suites.length; i++) {
            checkInternallyConsistent(suites[i]);
        }
    }

    /// EVERY candidate MUST be a snapshot of the contract it NAMES, as this
    /// repo currently compiles it, not of some other contract that happens to
    /// be internally consistent.
    ///
    /// The check itself is `RainDeploySuitesBase.checkCandidatesAnchoredToSource`
    /// rather than anything here, because `RainDeployBroadcast` runs the same
    /// definition before it broadcasts. A second spelling on this side is a
    /// spelling the deploy does not run, which is exactly the state this test
    /// would otherwise be reporting green about.
    function testSnapshotMatchesSource() external view {
        checkCandidatesAnchoredToSource();
    }
}
