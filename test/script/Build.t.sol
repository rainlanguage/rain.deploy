// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {GeneratedContract} from "../../script/Build.sol";
import {DeployCandidate} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibCodeGen} from "rain-sol-codegen-0.1.37/src/lib/LibCodeGen.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {LibReleasedSuitesAggregate} from "../lib/LibReleasedSuitesAggregate.sol";
import {BuildHarness, BuildHarnessWouldWriteTheCommittedLibs} from "../concrete/BuildHarness.sol";
import {LibMemoryKV, MemoryKV, MemoryKVKey, MemoryKVVal} from "rain-lib-memkv-0.1.5/src/lib/LibMemoryKV.sol";

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
/// committed `src/generated/` snapshots other test contracts read, and forge
/// runs test contracts in parallel.
contract BuildTest is Test {
    using LibMemoryKV for MemoryKV;

    /// The harness the two declarations are read through.
    BuildHarness internal sBuild;

    function setUp() external {
        sBuild = new BuildHarness("");
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

        MemoryKV nameSet = MemoryKV.wrap(0);
        for (uint256 i = 0; i < names.length; i++) {
            nameSet = nameSet.set(MemoryKVKey.wrap(keccak256(bytes(names[i]))), MemoryKVVal.wrap(0));
        }

        for (uint256 i = 0; i < generated.length; i++) {
            assertTrue(
                nameSet.has(MemoryKVKey.wrap(keccak256(bytes(generated[i].contractName)))),
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

    /// PROPERTY: EVERY generated contract's committed alias lib is byte-exactly
    /// what the generator emits for it today.
    ///
    /// `LibRainDeploySnapshotTest.testTheCommittedAliasLibIsWhatTheGeneratorEmits`
    /// asserts this of `AddressRegistry` by name, so every other contract's
    /// alias lib is pinned by nothing at all: its two constants are the deploy
    /// address and code hash every consumer resolves against, and a hand edit
    /// to either, or a generator nobody re-ran after the snapshot moved, is a
    /// lib that compiles and lies while the whole suite stays green.
    ///
    /// Driven from `generatedContracts()` rather than from a list here, so a
    /// contract is covered by having been declared.
    function testEveryCommittedAliasLibIsWhatTheGeneratorEmits() external view {
        GeneratedContract[] memory generated = sBuild.externalGeneratedContracts();

        for (uint256 i = 0; i < generated.length; i++) {
            string memory libraryName = string.concat("Lib", generated[i].contractName, "Deploy");

            assertEq(
                vm.readFile(LibRainDeploySnapshot.pathForLib(libraryName)),
                string.concat(
                    LibCodeGen.filePrefix(),
                    "\n",
                    LibRainDeploySnapshot.aliasImportBlock(
                        generated[i].contractName, generated[i].constantPrefix, LibRainDeploySnapshot.CANDIDATE
                    ),
                    LibRainDeploySnapshot.aliasLibraryBlock(
                        generated[i].contractName, generated[i].constantPrefix, libraryName
                    )
                ),
                string.concat("committed alias lib is not what the generator emits: ", generated[i].contractName)
            );
        }
    }

    /// PROPERTY: EVERY generated contract's committed released-suites lib is
    /// byte-exactly what the generator emits from this repo's real record
    /// today.
    ///
    /// `LibRainDeploySnapshotTest.testTheCommittedReleasedLibIsWhatTheGeneratorEmits`
    /// asserts this of `AddressRegistry` by name, so every other contract's
    /// released lib is pinned only by what the record check can reach through
    /// it. That check walks record -> declaration by DERIVED ADDRESS, so it
    /// sees a release dropped from the declaration and nothing else: the order
    /// the entries are declared in, the suite key and artifact path emitted
    /// beside them, the `abi.decode` of the frozen dependency list, and the
    /// generated-file header are all outside it, and a hand edit to any of them
    /// is a diff nobody looks at.
    ///
    /// Driven from `generatedContracts()` for the reason the alias half is.
    function testEveryCommittedReleasedLibIsWhatTheGeneratorEmits() external view {
        GeneratedContract[] memory generated = sBuild.externalGeneratedContracts();

        for (uint256 i = 0; i < generated.length; i++) {
            string memory libraryName = LibRainDeploySnapshot.releasedLibraryName(generated[i].contractName);
            string[] memory paths = LibRainDeploySnapshot.recordPathsForContract(
                vm, LibRainDeploySnapshot.LIB_FS_ROOT, generated[i].contractName
            );

            assertEq(
                vm.readFile(LibRainDeploySnapshot.pathForLib(libraryName)),
                string.concat(
                    LibCodeGen.filePrefix(),
                    "\n",
                    LibRainDeploySnapshot.releasedImportBlock(vm, paths),
                    LibRainDeploySnapshot.releasedLibraryBlock(
                        vm, libraryName, generated[i].contractName, paths, generated[i].candidate.snapshot
                    )
                ),
                string.concat("committed released lib is not what the generator emits: ", generated[i].contractName)
            );
        }
    }

    function testTheDefaultLibDirIsWhereTheCommittedLibsAre() external view {
        assertEq(sBuild.externalLibDir(), "src/lib");
    }

    string constant LIBS_FIXTURE_DIR = "fixture-lib/build-regenerate-libs";

    /// Assertions revert, so the fixture is removed before any of them run.
    function testRegenerateLibsEmitsExactlyTheCommittedLibs() external {
        GeneratedContract[] memory generated = sBuild.externalGeneratedContracts();
        BuildHarness harness = new BuildHarness(LIBS_FIXTURE_DIR);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(LIBS_FIXTURE_DIR, true);
        harness.externalRegenerateLibs();

        string[] memory names = new string[](generated.length * 2 + 1);
        for (uint256 i = 0; i < generated.length; i++) {
            names[i * 2] = string.concat("Lib", generated[i].contractName, "Deploy.sol");
            names[i * 2 + 1] =
                string.concat(LibRainDeploySnapshot.releasedLibraryName(generated[i].contractName), ".sol");
        }
        names[names.length - 1] = string.concat(LibRainDeploySnapshot.RELEASED_SUITES_LIBRARY, ".sol");

        uint256 written = vm.readDir(LIBS_FIXTURE_DIR).length;
        bool[] memory emitted = new bool[](names.length);
        string[] memory bodies = new string[](names.length);
        for (uint256 i = 0; i < names.length; i++) {
            string memory path = string.concat(LIBS_FIXTURE_DIR, "/", names[i]);
            emitted[i] = vm.isFile(path);
            bodies[i] = emitted[i] ? vm.readFile(path) : "";
        }

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(LIBS_FIXTURE_DIR, true);

        assertEq(written, names.length, "regenerateLibs emitted a different number of files than the repo commits");
        for (uint256 i = 0; i < names.length; i++) {
            assertTrue(emitted[i], string.concat("regenerateLibs emitted no ", names[i]));
            assertEq(
                bodies[i],
                vm.readFile(string.concat("src/lib/", names[i])),
                string.concat("regenerateLibs emitted something other than the committed ", names[i])
            );
        }
    }

    function testRegenerateLibsRefusesToWriteTheCommittedLibs() external {
        vm.expectRevert(BuildHarnessWouldWriteTheCommittedLibs.selector);
        sBuild.externalRegenerateLibs();
    }
}
