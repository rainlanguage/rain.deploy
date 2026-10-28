// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {GeneratedContract, RetiredContract} from "../../src/abstract/BuildScript.sol";
import {LibCodeGen} from "rain-sol-codegen-0.1.39/src/lib/LibCodeGen.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {BuildHarness, BuildHarnessWouldWriteTheCommittedLibs} from "../concrete/BuildHarness.sol";

/// @title BuildTest
/// @notice `script/Build.sol`'s committed libs against what its declaration
/// generates. The declaration's own consistency is `BuildScript`'s, enforced
/// by the build.
///
/// Deliberately nothing here calls `run()` or `cutRelease()`. Both rewrite the
/// committed `src/generated/` snapshots that other test contracts read, and
/// forge runs test contracts in parallel — a contract rewriting what another
/// one is reading is a race, not a check. `regenerateLibs()` is run, and only
/// into a fixture directory nothing compiles; the one write below is that.
contract BuildTest is Test {
    BuildHarness internal sBuild;

    function setUp() external {
        sBuild = new BuildHarness("");
    }

    /// PROPERTY: EVERY generated contract's committed alias lib is byte-exactly
    /// what the generator emits for it today.
    ///
    /// `LibRainDeploySnapshotTest.testTheCommittedAliasLibIsWhatTheGeneratorEmits`
    /// asserts this of `ConfigRegistry` by name, so every other contract's
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
                    sBuild.externalReleasedImportBlock(paths),
                    sBuild.externalReleasedLibraryBlock(
                        libraryName, generated[i].contractName, paths, generated[i].candidate.snapshot
                    )
                ),
                string.concat("committed released lib is not what the generator emits: ", generated[i].contractName)
            );
        }
    }

    /// PROPERTY: EVERY retired contract's committed released lib is
    /// byte-exactly what the generator emits for it today, so the build that
    /// regenerates it is a no-op.
    function testEveryCommittedRetiredLibIsWhatTheGeneratorEmits() external view {
        RetiredContract[] memory retired = sBuild.externalRetiredContracts();
        assertGt(retired.length, 0, "no retired contracts");

        for (uint256 i = 0; i < retired.length; i++) {
            string memory libraryName = LibRainDeploySnapshot.releasedLibraryName(retired[i].contractName);
            string[] memory paths = LibRainDeploySnapshot.recordPathsForContract(
                vm, LibRainDeploySnapshot.LIB_FS_ROOT, retired[i].contractName
            );
            assertGt(paths.length, 0, string.concat("retired contract has no frozen record: ", retired[i].contractName));

            assertEq(
                vm.readFile(LibRainDeploySnapshot.pathForLib(libraryName)),
                string.concat(
                    LibCodeGen.filePrefix(),
                    "\n",
                    sBuild.externalReleasedImportBlock(paths),
                    sBuild.externalReleasedLibraryBlock(
                        libraryName, retired[i].contractName, paths, retired[i].template
                    )
                ),
                string.concat("committed retired lib is not what the generator emits: ", retired[i].contractName)
            );
        }
    }

    /// PROPERTY: a build with nothing overridden writes its libs into the
    /// directory the committed ones are in.
    ///
    /// Asserted against the path as text rather than against
    /// `LibRainDeploySnapshot.LIB_DIR`, which is the constant the default
    /// returns: a default pointed at a directory nothing compiles leaves every
    /// committed lib stale forever while the regeneration reports success, and
    /// the test below cannot see it, because that test overrides this.
    function testTheDefaultLibDirIsWhereTheCommittedLibsAre() external view {
        assertEq(sBuild.externalLibDir(), "src/lib");
    }

    /// Where `regenerateLibs()` is driven.
    ///
    /// Outside `src/` and `test/`, which is everything `fs_permissions`
    /// otherwise grants and both of which are compiled: a generated lib imports
    /// `../generated/`, `../abstract/` and `./Lib<Contract>Released.sol`, which
    /// resolve from `src/lib` and nowhere else, so a copy under either root
    /// fails the build for every suite — including the copy a failing test
    /// leaves behind. `foundry.toml` grants this root for exactly that, and
    /// nothing compiles it.
    string constant LIBS_FIXTURE_DIR = "fixture-lib/build-regenerate-libs";

    /// PROPERTY: `regenerateLibs()` RUN emits exactly the committed libs — one
    /// alias lib and one released lib per generated contract, one aggregate,
    /// and nothing else.
    ///
    /// Every assertion above this one is output-anchored: it compares a
    /// committed file against the emitters, so it sees drift only AFTER
    /// somebody re-runs the generator and commits what came out. The hook that
    /// decides which emitter is called, with which arguments, how many times,
    /// was executed by nothing at all — a loop bound that stopped one contract
    /// short, or a `constantPrefix` taken from `contracts[0]` on every pass,
    /// was invisible until the next release cut it into the record. Both hooks
    /// took a `revert()` as their first statement with the whole suite still
    /// green.
    ///
    /// So this runs it, and the oracle is the committed tree rather than the
    /// emitters: a regeneration of a clean checkout is a no-op, so every file
    /// it writes MUST be byte-identical to the file already there. That is
    /// independent of the emitters in the way the pins above are not — they say
    /// the committed files are what the emitters produce, and this says the
    /// hook asks the emitters for those files.
    ///
    /// The count is asserted as well as the contents, because a loop that
    /// stopped short writes nothing wrong — it writes nothing at all — and a
    /// file the hook wrote that the repo does not commit is a generated file
    /// nothing regenerates.
    ///
    /// `regenerateSnapshots()` has no counterpart here and can have none:
    /// `LibFs` confines every snapshot write to `src/generated/<tag>/`, the
    /// record `frozenSnapshotPaths` walks, so there is no directory to drive it
    /// into that is not read by the suites running beside this one.
    ///
    /// Read, then removed, then asserted: forge-std assertions revert, so a
    /// removal after them removes in every case except a failure, which is the
    /// only case that leaves a directory behind. `vm.isFile` before each read
    /// for the same reason — a missing file is what the loop-bound failure
    /// looks like, and a cheatcode revert there would strand the fixture.
    function testRegenerateLibsEmitsExactlyTheCommittedLibs() external {
        GeneratedContract[] memory generated = sBuild.externalGeneratedContracts();
        BuildHarness harness = new BuildHarness(LIBS_FIXTURE_DIR);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(LIBS_FIXTURE_DIR, true);
        harness.externalRegenerateLibs();

        RetiredContract[] memory retired = sBuild.externalRetiredContracts();
        string[] memory names = new string[](retired.length + generated.length * 2 + 1);
        for (uint256 i = 0; i < retired.length; i++) {
            names[i] = string.concat(LibRainDeploySnapshot.releasedLibraryName(retired[i].contractName), ".sol");
        }
        for (uint256 i = 0; i < generated.length; i++) {
            names[retired.length + i * 2] = string.concat("Lib", generated[i].contractName, "Deploy.sol");
            names[retired.length + i * 2 + 1] =
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

    /// A harness left pointed at `Build`'s own lib directory MUST refuse to run
    /// the lib half of a build.
    ///
    /// `setUp` builds one, because the default is what
    /// `testTheDefaultLibDirIsWhereTheCommittedLibsAre` reads, and it is shared
    /// with every other test in this contract. A call that went through would
    /// rewrite `src/lib/` while the suites that compile and read those files
    /// are running.
    function testRegenerateLibsRefusesToWriteTheCommittedLibs() external {
        vm.expectRevert(BuildHarnessWouldWriteTheCommittedLibs.selector);
        sBuild.externalRegenerateLibs();
    }

    /// PROPERTY: `run()` declares exactly these lines, and each names a committed file.
    function testRunDeclaresTheCommittedGeneratedFiles() external view {
        string[] memory paths = sBuild.externalGeneratedPaths();
        string[] memory lines = LibRainDeploySnapshot.codegenDeclaration(paths);

        string[11] memory expected = [
            "rainix-codegen owns src/generated/candidate/ConfigRegistry.sol",
            "rainix-codegen owns src/generated/candidate/MigrationRegistry.sol",
            "rainix-codegen owns src/generated/candidate/TimelockController.sol",
            "rainix-codegen owns src/lib/LibAddressRegistryReleased.sol",
            "rainix-codegen owns src/lib/LibConfigRegistryReleased.sol",
            "rainix-codegen owns src/lib/LibMigrationRegistryReleased.sol",
            "rainix-codegen owns src/lib/LibReleasedSuites.sol",
            "rainix-codegen owns src/lib/LibConfigRegistryDeploy.sol",
            "rainix-codegen owns src/lib/LibMigrationRegistryDeploy.sol",
            "rainix-codegen owns foundry.toml",
            "rainix-codegen owns .env.example"
        ];
        assertEq(lines.length, expected.length);
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(lines[i], expected[i]);
            assertTrue(vm.exists(paths[i]), paths[i]);
        }
    }

    /// PROPERTY: every lib `run()` declares is under `libDir()`, the directory `regenerateLibs` writes into.
    function testRunDeclaresTheLibsUnderLibDir() external {
        string[] memory paths = new BuildHarness(LIBS_FIXTURE_DIR).externalGeneratedPaths();

        assertEq(paths.length, 11);
        assertEq(paths[3], string.concat(LIBS_FIXTURE_DIR, "/LibAddressRegistryReleased.sol"));
        assertEq(paths[4], string.concat(LIBS_FIXTURE_DIR, "/LibConfigRegistryReleased.sol"));
        assertEq(paths[5], string.concat(LIBS_FIXTURE_DIR, "/LibMigrationRegistryReleased.sol"));
        assertEq(paths[6], string.concat(LIBS_FIXTURE_DIR, "/LibReleasedSuites.sol"));
        assertEq(paths[7], string.concat(LIBS_FIXTURE_DIR, "/LibConfigRegistryDeploy.sol"));
        assertEq(paths[8], string.concat(LIBS_FIXTURE_DIR, "/LibMigrationRegistryDeploy.sol"));
    }
}
