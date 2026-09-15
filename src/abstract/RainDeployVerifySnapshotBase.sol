// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {DerivedDeploy, RainDeployVerifyBase} from "./RainDeployVerifyBase.sol";
import {DeploySuite} from "./RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../lib/LibRainDeploy.sol";
import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "rain-lib-memkv-0.1.4/src/lib/LibMemoryKV.sol";

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

/// Thrown when a config section that MUST name the supported networks is not in
/// the config at all. Distinct from one that is present and empty, which fails
/// per network as `NetworkNotConfigured`: a section that is absent has no keys
/// to read rather than none to find.
/// @param section The absent section.
error ConfigSectionMissing(string section);

/// Thrown when a supported network has no entry in a config section.
/// @param section The section the network is missing from.
/// @param network The supported network with no entry.
error NetworkNotConfigured(string section, string network);

/// Thrown when a config section carries an entry that no supported network
/// names.
/// @param section The section carrying the entry.
/// @param entry The entry no supported network names.
error ConfigEntryNotSupported(string section, string entry);

/// @title RainDeployVerifySnapshotBase
/// @notice Every deploy-pin assertion that needs no network, for every suite
/// a repo declares. Three groups, which catch different things and are
/// documented as such because it is easy to read the first as covering the
/// second. The config group's check is here too, and for the same reason the
/// record group's is: see below.
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
///
/// ## What this contract is, and what a deploy repo inherits instead
///
/// This holds the CHECK and not the BINDING, for both groups whose subject is
/// the repo's own state on disk rather than anything it declares: the record,
/// and `foundry.toml`. Everything defined here takes its subject as an argument
/// or from the inheriting contract's own declaration, so a contract whose
/// declaration is a fixture is a contract this says true things about — and a
/// check handed its subject is a check a fixture can drive to failure, which is
/// the only way any of this is known to be capable of failing at all.
/// `RainDeployVerifySnapshot` is this plus the two tests that bind those checks
/// to the real record and the real config, and it is what a deploy repo
/// inherits — the whole of the split is which contract carries those tests.
///
/// The split exists because the record test's subject is `LibRainDeploySnapshot`'s
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
    using LibMemoryKV for MemoryKV;

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

    /// Checks one config section against the supported networks: the section's
    /// keys are EXACTLY the networks.
    ///
    /// Both directions, because containment one way alone passes for a section
    /// carrying an entry nothing deploys to, and the other way alone passes for
    /// a network with no config at all. Membership rather than position,
    /// because a config section is keyed rather than ordered and there is no
    /// order in it to assert.
    ///
    /// The section's keys are PARSED and each network looked up among them,
    /// rather than each network being probed as a `.<section>.<network>` key
    /// path. A key path is read as a PATH: a network whose name carries a dot
    /// is answered by a nested table under the part before it — which is no
    /// alias foundry resolves — and is NOT answered by the quoted flat key that
    /// is that alias. Both of those are backwards, and the keys of the section
    /// are what the claim is about.
    ///
    /// Reading the keys is also what keeps an empty section from going quiet.
    /// The reverse direction over a section with no keys walks nothing and
    /// asserts nothing; the forward direction over the same keys fails once per
    /// network, so there is no shape of section that this passes without a
    /// subject.
    /// @param config The config file's contents.
    /// @param section The top-level section to check.
    /// @param networks The supported networks the section MUST name.
    function checkConfigSectionNamesNetworks(string memory config, string memory section, string[] memory networks)
        internal
        view
    {
        string memory path = string.concat(".", section);
        if (!vm.keyExistsToml(config, path)) {
            revert ConfigSectionMissing(section);
        }
        string[] memory entries = vm.parseTomlKeys(config, path);

        MemoryKV entrySet = MemoryKV.wrap(0);
        for (uint256 i = 0; i < entries.length; i++) {
            entrySet = entrySet.set(MemoryKVKey.wrap(keccak256(bytes(entries[i]))), MemoryKVVal.wrap(0));
        }

        MemoryKV networkSet = MemoryKV.wrap(0);
        for (uint256 i = 0; i < networks.length; i++) {
            networkSet = networkSet.set(MemoryKVKey.wrap(keccak256(bytes(networks[i]))), MemoryKVVal.wrap(0));
        }

        for (uint256 i = 0; i < networks.length; i++) {
            if (!entrySet.has(MemoryKVKey.wrap(keccak256(bytes(networks[i]))))) {
                revert NetworkNotConfigured(section, networks[i]);
            }
        }

        for (uint256 i = 0; i < entries.length; i++) {
            if (!networkSet.has(MemoryKVKey.wrap(keccak256(bytes(entries[i]))))) {
                revert ConfigEntryNotSupported(section, entries[i]);
            }
        }
    }

    /// Checks both config sections a deploy resolves against the supported
    /// networks: `[rpc_endpoints]`, which the fork and the broadcast read, and
    /// `[etherscan]`, which `--verify` reads.
    ///
    /// Which two sections those are is stated here rather than taken from the
    /// caller. A binder able to name a section is a binder able to name one of
    /// them and leave the other unchecked, and the `[etherscan]` half has
    /// nothing else in the suite standing behind it.
    /// @param config The config file's contents.
    /// @param networks The supported networks both sections MUST name.
    function checkNetworksFullyConfigured(string memory config, string[] memory networks) internal view {
        checkConfigSectionNamesNetworks(config, "rpc_endpoints", networks);
        checkConfigSectionNamesNetworks(config, "etherscan", networks);
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
}
