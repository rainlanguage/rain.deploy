// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {GeneratedContract} from "../../script/Build.sol";
import {DeployCandidate} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {LibReleasedSuitesAggregate} from "../lib/LibReleasedSuitesAggregate.sol";
import {BuildHarness} from "../concrete/BuildHarness.sol";
import {LibStringSet} from "../../src/lib/LibStringSet.sol";
import {
    LibCodeGen,
    RAIN_COPYRIGHT_TEXT,
    RAIN_SPDX_LICENSE_IDENTIFIER
} from "rain-sol-codegen-0.1.37/src/lib/LibCodeGen.sol";

/// @title BuildTest
/// @notice `script/Build.sol`'s own declaration.
///
/// `Build`'s NatSpec argues that "one list, three readers" makes a contract
/// silently absent from a release impossible. That is true of the readers
/// INSIDE `Build` — the regeneration, both lib writers and the freeze all read
/// `generatedContracts()` — and false of the boundary: what this repo deploys
/// is declared in `RegistryDeploySuites.candidateSuites()`, and the generator's
/// list is a second hard-coded array in a second file.
///
/// A candidate dropped from `generatedContracts()` by a refactor or a merge
/// still compiles, because its committed snapshot is still there and still
/// imported. `cutRelease()` then freezes only the contracts the generator
/// names, `regenerateLibs()` writes a released-suites lib only for those, and
/// the release permanently omits that contract. Nothing downstream can see it:
/// `testEveryFrozenSnapshotIsReleased` walks record -> declaration, so a record
/// entry never written is invisible to it; `RegistryDeployVerifyTest` is never
/// handed the omitted suite; and `testEveryCandidateHasASnapshot` compares the
/// candidate DIRECTORY against the declaration, where the stale committed file
/// keeps both sides equal. `SnapshotAlreadyFrozen` then makes the hole
/// unrepairable, because the tag has been cut.
///
/// So the agreement of the two lists is asserted here, along with the three
/// properties of the generator's own entries that decide which file each
/// contract's pins are written into.
///
/// Deliberately nothing here calls `run()` or `cutRelease()`. Both rewrite the
/// committed `src/generated/` snapshots and `src/lib/` libs that other test
/// contracts read, and forge runs test contracts in parallel — a contract
/// rewriting what another one is reading is a race, not a check. Nothing below
/// writes anything.
contract BuildTest is Test {
    /// The harness the two declarations are read through.
    BuildHarness internal sBuild;

    function setUp() external {
        sBuild = new BuildHarness();
    }

    /// PROPERTY: the generator's list and the deploy declaration are the SAME
    /// SET of contracts, matched both ways. A candidate the generator does not
    /// name is a contract silently absent from every release cut from here, and
    /// neither the frozen-record check nor the chain check can see it, because
    /// both are only ever handed what was written.
    ///
    /// Matched by the suite key rather than by index, because `Build` reaches
    /// candidates by name for exactly this reason and a positional pass would
    /// go green on a reordered list that had silently swapped two contracts.
    function testGeneratedContractsAreExactlyTheDeclaredCandidates() external view {
        GeneratedContract[] memory generated = sBuild.externalGeneratedContracts();
        DeployCandidate[] memory candidates = sBuild.externalCandidateSuites();

        assertEq(
            generated.length, candidates.length, "a candidate is not generated, or a generated contract is not declared"
        );

        for (uint256 i = 0; i < generated.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < candidates.length; j++) {
                if (
                    keccak256(bytes(generated[i].candidate.snapshot.suite))
                        == keccak256(bytes(candidates[j].snapshot.suite))
                ) {
                    assertEq(
                        keccak256(generated[i].candidate.snapshot.creationCode),
                        keccak256(candidates[j].snapshot.creationCode),
                        "generated entry carries another contract's creation code"
                    );
                    found = true;
                    break;
                }
            }
            assertTrue(
                found, string.concat("generated contract is not a declared candidate: ", generated[i].contractName)
            );
        }

        for (uint256 j = 0; j < candidates.length; j++) {
            bool found = false;
            for (uint256 i = 0; i < generated.length; i++) {
                if (
                    keccak256(bytes(generated[i].candidate.snapshot.suite))
                        == keccak256(bytes(candidates[j].snapshot.suite))
                ) {
                    found = true;
                    break;
                }
            }
            assertTrue(found, string.concat("declared candidate is not generated: ", candidates[j].snapshot.suite));
        }
    }

    /// PROPERTY: the names a release freezes are EXACTLY the generator's
    /// contracts.
    ///
    /// `snapshotContractNames()` is the list `cutRelease()` hands `freeze`, and
    /// it is the only thing that decides what a release records. A generated
    /// contract missing from it is regenerated on every push and then absent
    /// from the frozen tag, which `SnapshotAlreadyFrozen` makes unrepairable.
    function testSnapshotContractNamesAreTheGeneratedContracts() external view {
        GeneratedContract[] memory generated = sBuild.externalGeneratedContracts();
        string[] memory names = sBuild.externalSnapshotContractNames();

        assertEq(
            names.length, generated.length, "a generated contract is not frozen, or a frozen name is not generated"
        );
        for (uint256 i = 0; i < generated.length; i++) {
            assertTrue(
                LibStringSet.holds(names, generated[i].contractName),
                string.concat("generated contract is not frozen by a release: ", generated[i].contractName)
            );
        }
    }

    /// PROPERTY: `contractName` is the name the snapshot path and both
    /// generated libs are built from, and it MUST be the contract the
    /// candidate's artifact path names. A disagreement writes one contract's
    /// pins into another contract's file, which every downstream check then
    /// reads as self-consistent.
    function testGeneratedContractNameMatchesTheArtifactPath() external view {
        GeneratedContract[] memory generated = sBuild.externalGeneratedContracts();
        for (uint256 i = 0; i < generated.length; i++) {
            string[] memory components = vm.split(generated[i].candidate.snapshot.artifactPath, ":");
            assertEq(
                components[components.length - 1],
                generated[i].contractName,
                "generated name is not the artifact's contract"
            );
        }
    }

    /// PROPERTY: no two entries name one contract. Two entries sharing a
    /// `contractName` write one snapshot file twice and freeze one file for two
    /// declarations, so the second silently replaces the first.
    function testGeneratedContractNamesAreUnique() external view {
        GeneratedContract[] memory generated = sBuild.externalGeneratedContracts();
        for (uint256 i = 0; i < generated.length; i++) {
            for (uint256 j = i + 1; j < generated.length; j++) {
                assertNotEq(
                    generated[i].contractName, generated[j].contractName, "two generated entries name one contract"
                );
            }
        }
    }

    /// PROPERTY: the constant prefix is non-empty and distinct per contract. It
    /// names every constant both generated libs export, so a shared prefix is
    /// two libs exporting colliding names.
    function testConstantPrefixesAreNonEmptyAndUnique() external view {
        GeneratedContract[] memory generated = sBuild.externalGeneratedContracts();
        for (uint256 i = 0; i < generated.length; i++) {
            assertGt(bytes(generated[i].constantPrefix).length, 0, "empty constant prefix");
            for (uint256 j = i + 1; j < generated.length; j++) {
                assertNotEq(
                    generated[i].constantPrefix, generated[j].constantPrefix, "two entries share a constant prefix"
                );
            }
        }
    }

    /// PROPERTY: the committed aggregate imports the generated contracts in
    /// `generatedContracts()`'s ORDER, not merely as a set.
    ///
    /// Declaration order is claimed twice — the emitted library documents its
    /// entries as being "in declaration order" and `snapshotContractNames()`
    /// documents itself as giving "the order the aggregate emits its entries
    /// in" — and nothing else pins it.
    /// `testTheCommittedAggregateIsWhatTheGeneratorEmits` takes the contract
    /// list from the committed file itself, so it holds for any permutation of
    /// it, and `testEverySnapshotIsInTheReleasedAggregate` matches sets. So the
    /// two imports and the two `released<N>` locals can be swapped in the
    /// committed file — byte-exactly what the generator emits for the reversed
    /// list — and the whole suite stays green while the aggregate returns the
    /// releases in an order the declaration does not give, which is the order
    /// `suiteNames()` reports them in.
    ///
    /// Positional, because the SET is already matched by the two tests this
    /// names and the order is the whole of what is left.
    function testTheCommittedAggregateIsInDeclarationOrder() external view {
        GeneratedContract[] memory generated = sBuild.externalGeneratedContracts();
        string[] memory imported = LibReleasedSuitesAggregate.declaredContractNames(
            vm, vm.readFile(LibRainDeploySnapshot.pathForLib(LibRainDeploySnapshot.RELEASED_SUITES_LIBRARY))
        );

        assertEq(
            imported.length,
            generated.length,
            "the committed aggregate imports a different number of contracts than the generator names"
        );

        for (uint256 i = 0; i < generated.length; i++) {
            assertEq(
                imported[i],
                generated[i].contractName,
                "the committed aggregate is not in the generator's declaration order"
            );
        }
    }

    /// PROPERTY: `snapshotContractNames()` is every `generatedContracts()`
    /// entry's `contractName`, positionally.
    ///
    /// It is the list `cutRelease` freezes and the list the aggregate is
    /// emitted from, and both reach it only through `forge script`. A name
    /// list shorter than the declaration freezes one contract fewer and emits
    /// an aggregate that declares that contract's releases as nothing at all,
    /// and every other assertion here is still green: the tests above read
    /// `generatedContracts()` and the committed file, neither of which this
    /// list passes through.
    function testSnapshotContractNamesAreTheDeclarationInOrder() external view {
        GeneratedContract[] memory generated = sBuild.externalGeneratedContracts();
        string[] memory names = sBuild.externalSnapshotContractNames();

        assertEq(names.length, generated.length, "a different number of names than generated contracts");

        for (uint256 i = 0; i < generated.length; i++) {
            assertEq(names[i], generated[i].contractName, "the names are not the declaration in order");
        }
    }

    /// PROPERTY: for EVERY generated contract, the committed alias lib is
    /// byte-exactly what the generator emits from THAT ENTRY — its
    /// `contractName`, its `constantPrefix` and the candidate directory.
    ///
    /// `constantPrefix` is otherwise only ever asserted to be non-empty and
    /// distinct, and neither says what it must be. It names every constant the
    /// alias lib exports, so a prefix that is merely unique — `ADDRESS_REG` for
    /// `ADDRESS_REGISTRY` — is a rename of the whole public surface
    /// `LibAddressRegistry` and every consumer pins, and the next regeneration
    /// is what performs it. Nothing else in the suite reads the declared prefix
    /// at all: the emitter checks hard-code their own, so they agree with a
    /// declaration they never read.
    ///
    /// Per entry rather than for one contract, because the emitter checks are
    /// written for `AddressRegistry` alone and the second contract's alias lib
    /// is therefore pinned by nothing — a generator that stopped emitting for
    /// it, or emitted it under another prefix, is silent until a consumer fails
    /// to compile.
    ///
    /// Reads only. The file this compares against is committed source other
    /// suites compile, and regenerating it first would pass on a stale one by
    /// overwriting it.
    function testTheCommittedAliasLibsAreWhatTheDeclarationEmits() external view {
        GeneratedContract[] memory generated = sBuild.externalGeneratedContracts();

        for (uint256 i = 0; i < generated.length; i++) {
            string memory libraryName = string.concat("Lib", generated[i].contractName, "Deploy");
            assertEq(
                vm.readFile(LibRainDeploySnapshot.pathForLib(libraryName)),
                string.concat(
                    LibCodeGen.filePrefix(RAIN_SPDX_LICENSE_IDENTIFIER, RAIN_COPYRIGHT_TEXT),
                    "\n",
                    LibRainDeploySnapshot.aliasImportBlock(
                        generated[i].contractName, generated[i].constantPrefix, LibRainDeploySnapshot.CANDIDATE
                    ),
                    LibRainDeploySnapshot.aliasLibraryBlock(
                        generated[i].contractName, generated[i].constantPrefix, libraryName
                    )
                ),
                string.concat("the committed alias lib is not what this entry emits: ", libraryName)
            );
        }
    }
}
