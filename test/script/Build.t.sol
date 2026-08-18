// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {GeneratedContract} from "../../script/Build.sol";
import {DeployCandidate} from "../../src/abstract/RainDeploySuitesBase.sol";
import {BuildHarness} from "../concrete/BuildHarness.sol";
import {LibStringSet} from "../lib/LibStringSet.sol";

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
/// entry never written is invisible to it; `RegistryDeployChainTest` is never
/// handed the omitted suite; and `testEveryCandidateHasASnapshot` compares the
/// candidate DIRECTORY against the declaration, where the stale committed file
/// keeps both sides equal. `SnapshotAlreadyFrozen` then makes the hole
/// unrepairable, because the tag has been cut.
///
/// So the agreement of the two lists is asserted here, along with the three
/// properties of the generator's own entries that decide which file each
/// contract's pins are written into.
///
/// Deliberately nothing here calls `run()` or `cutRelease()`. Both write
/// `src/lib/Lib*Released.sol`, which `LibRainDeploySnapshotTest` also writes,
/// and forge runs test contracts in parallel — two contracts writing one file
/// is a race, not a check. Everything below is pure.
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
}
