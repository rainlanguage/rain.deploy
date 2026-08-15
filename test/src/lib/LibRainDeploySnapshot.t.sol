// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    EmptyRelease,
    LibRainDeploySnapshot,
    NothingToFreeze,
    UnreleasableVersion
} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {LibStringSet} from "../../lib/LibStringSet.sol";

/// @title LibRainDeploySnapshotTest
/// @notice The guards on the release machinery every deploy repo inherits.
///
/// These are the paths that only run when something has already gone wrong, so
/// nothing else exercises them — and a guard nobody has seen fire is a guard
/// nobody knows works. Each is driven here directly.
contract LibRainDeploySnapshotTest is Test {
    /// External wrapper so `vm.expectRevert` lands at the right call depth.
    /// @param version The version to convert.
    /// @return The tag.
    function externalTagForVersion(string memory version) external pure returns (string memory) {
        return LibRainDeploySnapshot.tagForVersion(version);
    }

    /// A regeneration that does nothing, for driving `freeze`'s guards. Every
    /// one of them either fires before this runs or is about what it left
    /// behind, so a no-op is what makes "the guard fired" and "the guard fired
    /// FIRST" the same observation.
    function noRegeneration() internal {}

    /// External wrapper so `vm.expectRevert` lands at the right call depth.
    /// @param contractNames The contracts to freeze.
    function externalFreeze(string[] memory contractNames) external {
        LibRainDeploySnapshot.freeze(vm, noRegeneration, contractNames);
    }

    /// Where the record fixture is built. NOT `src/generated`: the inherited
    /// record check reads that root, in other contracts, which forge runs in
    /// parallel with this one — a fixture release there would be a release
    /// those contracts have to fail on, for as long as it exists.
    string constant FIXTURE_ROOT = "test/generated";

    /// Writes one file into the fixture record.
    ///
    /// Carries a licence header because a run that fails midway leaves it
    /// behind, and an unlicensed file in the tree is a second failure on top of
    /// the first.
    /// @param path The file to write, under `FIXTURE_ROOT`.
    function writeFixture(string memory path) internal {
        string[] memory components = vm.split(path, "/");
        string memory dir = components[0];
        for (uint256 i = 1; i < components.length - 1; i++) {
            dir = string.concat(dir, "/", components[i]);
        }
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(dir, true);
        // Split so `reuse lint` reads this as a fixture rather than as this
        // file's own license declaration -- an SPDX identifier in a string
        // literal is indistinguishable from a real one to a line scanner.
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(path, string.concat("// SPDX-License", "-Identifier: LicenseRef-DCL-1.0\n"));
    }

    /// A release tag is what `tagForVersion` produces and nothing else, so
    /// exactly the directories a freeze can write are the ones the record
    /// counts. The rolling `candidate/` is excluded by that same rule rather
    /// than by name.
    function testIsTagAcceptsWhatAFreezeCanWrite() external pure {
        assertTrue(LibRainDeploySnapshot.isTag(LibRainDeploySnapshot.tagForVersion("0.1.7")));
        assertTrue(LibRainDeploySnapshot.isTag("0_0_0"));
        assertTrue(LibRainDeploySnapshot.isTag("10_20_30"));

        assertFalse(LibRainDeploySnapshot.isTag(LibRainDeploySnapshot.CANDIDATE));
        assertFalse(LibRainDeploySnapshot.isTag("0_1"));
        assertFalse(LibRainDeploySnapshot.isTag("0_1_7-rc1"));
        assertFalse(LibRainDeploySnapshot.isTag("0.1.7"));
        assertFalse(LibRainDeploySnapshot.isTag("_1_7"));
        assertFalse(LibRainDeploySnapshot.isTag("0_1_"));
        assertFalse(LibRainDeploySnapshot.isTag(""));
        assertFalse(LibRainDeploySnapshot.isTag("collision-guard"));
    }

    /// EVERY version a freeze accepts MUST produce a directory the record
    /// recognises as a release. A version that could be frozen to a directory
    /// the record then ignores is exactly the orphan snapshot
    /// `UnreleasableVersion` exists to prevent, and it is what two spellings of
    /// the version rule would eventually produce.
    function testEveryFreezableVersionIsATagTheRecordFinds(uint8 major, uint8 minor, uint8 patch) external pure {
        string memory version = string.concat(
            vm.toString(uint256(major)), ".", vm.toString(uint256(minor)), ".", vm.toString(uint256(patch))
        );

        assertTrue(LibRainDeploySnapshot.isStrictTriple(version, "."));
        assertTrue(LibRainDeploySnapshot.isTag(LibRainDeploySnapshot.tagForVersion(version)));
    }

    /// The record is every file inside a release-tag directory, and only those.
    ///
    /// The whole point of reading the tree is that it is the one description of
    /// what a repo has released that cannot fall behind, so a walk that quietly
    /// found nothing would leave exactly the hole it is here to close. Driven
    /// against a directory that really has releases in it.
    ///
    /// Asserted as membership plus a count rather than as a sequence: the walk's
    /// order is the filesystem's, so an assertion about position would be an
    /// assertion about the machine that ran it.
    function testFrozenSnapshotPathsFindsEveryReleaseAndNothingElse() external {
        writeFixture(string.concat(FIXTURE_ROOT, "/0_0_1/MockDeployable.sol"));
        writeFixture(string.concat(FIXTURE_ROOT, "/0_0_2/MockDeployableV2.sol"));
        writeFixture(string.concat(FIXTURE_ROOT, "/0_0_2/Second.sol"));
        // Not releases: the rolling snapshot, a version no freeze could have
        // written, a file loose in the root, and a file too deep to be a record.
        writeFixture(string.concat(FIXTURE_ROOT, "/", LibRainDeploySnapshot.CANDIDATE, "/MockDeployable.sol"));
        writeFixture(string.concat(FIXTURE_ROOT, "/0_0_3-rc1/MockDeployable.sol"));
        writeFixture(string.concat(FIXTURE_ROOT, "/Loose.sol"));
        writeFixture(string.concat(FIXTURE_ROOT, "/0_0_1/nested/TooDeep.sol"));

        string[] memory paths = LibRainDeploySnapshot.frozenSnapshotPaths(vm, FIXTURE_ROOT);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(FIXTURE_ROOT, true);

        assertTrue(LibStringSet.holds(paths, string.concat(FIXTURE_ROOT, "/0_0_1/MockDeployable.sol")));
        assertTrue(LibStringSet.holds(paths, string.concat(FIXTURE_ROOT, "/0_0_2/MockDeployableV2.sol")));
        assertTrue(LibStringSet.holds(paths, string.concat(FIXTURE_ROOT, "/0_0_2/Second.sol")));
        assertEq(paths.length, 3);
    }

    /// Where the missing-root case reads. Its own tree, for the same reason
    /// `RELEASED_FIXTURE_ROOT` is not `FIXTURE_ROOT`: a root another test in
    /// this contract builds and tears down is not a root this one can assert is
    /// absent, and nothing writes here at all.
    string constant MISSING_FIXTURE_ROOT = "test/generated-missing";

    /// A root that is not there at all MUST read as a repo that has released
    /// nothing, not as a failure. That is the state of every deploy repo before
    /// its first release, including this one.
    function testFrozenSnapshotPathsOnAMissingRoot() external view {
        assertFalse(vm.exists(MISSING_FIXTURE_ROOT));
        assertEq(LibRainDeploySnapshot.frozenSnapshotPaths(vm, MISSING_FIXTURE_ROOT).length, 0);
    }

    /// The rolling snapshot MUST NOT be in this repo's own record. It is the
    /// only directory in `src/generated/` today, and a walk that returned it
    /// would make the candidate a release that has to be declared and deployed.
    function testFrozenSnapshotPathsExcludesTheRollingSnapshot() external view {
        assertTrue(vm.exists(LibRainDeploySnapshot.pathForSnapshot(LibRainDeploySnapshot.CANDIDATE, "AddressRegistry")));
        assertFalse(
            LibStringSet.holds(
                LibRainDeploySnapshot.frozenSnapshotPaths(vm, LibRainDeploySnapshot.LIB_FS_ROOT),
                LibRainDeploySnapshot.pathForSnapshot(LibRainDeploySnapshot.CANDIDATE, "AddressRegistry")
            )
        );
    }

    /// A strict `X.Y.Z` version MUST become its directory form.
    function testTagForVersionConvertsDots() external pure {
        assertEq(LibRainDeploySnapshot.tagForVersion("0.1.7"), "0_1_7");
        assertEq(LibRainDeploySnapshot.tagForVersion("10.20.30"), "10_20_30");
        assertEq(LibRainDeploySnapshot.tagForVersion("0.0.0"), "0_0_0");
    }

    /// Anything that is not strict `X.Y.Z` MUST be refused rather than mapped
    /// to a directory the append-only gate ignores forever.
    function testTagForVersionRefusesNonStrict() external {
        string[9] memory bad = ["0.1.7-rc1", "0.1", "0.1.7.1", "", "a.b.c", ".1.7", "0..7", "0.1.", "0.1.7 "];
        for (uint256 i = 0; i < bad.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(UnreleasableVersion.selector, bad[i]));
            this.externalTagForVersion(bad[i]);
        }
    }

    /// The tag read from `foundry.toml` MUST go through the same guard, so a
    /// repo cannot reach a release path with a version the guard would refuse.
    function testDeployTagUsesTheGuardedConversion() external view {
        assertEq(
            LibRainDeploySnapshot.deployTag(vm),
            LibRainDeploySnapshot.tagForVersion(vm.parseTomlString(vm.readFile("foundry.toml"), ".package.version"))
        );
    }

    /// Snapshot paths MUST agree with `LibFs`, which is what writes them.
    function testSnapshotPathsAgreeWithTheWriter() external pure {
        assertEq(LibRainDeploySnapshot.dirForSnapshot("0_1_7"), "src/generated/0_1_7");
        assertEq(LibRainDeploySnapshot.snapshotName("0_1_7", "Foo"), "0_1_7/Foo");
        assertEq(LibRainDeploySnapshot.pathForSnapshot("0_1_7", "Foo"), "src/generated/0_1_7/Foo.sol");
    }

    /// A snapshot MUST land at the path this library says it does, and writing
    /// one over a directory that is already there is the ORDINARY case: the
    /// rolling snapshot is regenerated into the same `candidate/` on every
    /// build.
    ///
    /// Written into a directory that is not tag shaped on purpose. The record
    /// root is the real `src/generated/`, which the inherited record check
    /// walks from other contracts that forge runs in parallel with this one, so
    /// a tag-shaped name here would be a release those contracts have to fail
    /// on for as long as it exists.
    function testWriteSnapshotWritesTheSnapshotAtItsPath() external {
        string memory dir = "write-snapshot-not-a-tag";
        assertFalse(LibRainDeploySnapshot.isTag(dir));
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(LibRainDeploySnapshot.dirForSnapshot(dir), true);

        string memory written =
            LibRainDeploySnapshot.writeSnapshot(vm, dir, "MockDeployable", type(MockDeployable).creationCode);
        // Read while the snapshot is still there, asserted once it is gone.
        bool exists = vm.exists(written);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(LibRainDeploySnapshot.dirForSnapshot(dir), true);

        assertEq(written, LibRainDeploySnapshot.pathForSnapshot(dir, "MockDeployable"));
        assertTrue(exists);
    }

    /// Where the released-lib record fixture is built. Its own tree rather
    /// than `FIXTURE_ROOT`: forge runs the tests in a contract concurrently,
    /// and two of them writing one record root see each other's releases.
    string constant RELEASED_FIXTURE_ROOT = "test/generated-released";

    /// Where the selection fixture's record is built, for the same reason
    /// `RELEASED_FIXTURE_ROOT` is not `FIXTURE_ROOT`.
    string constant SELECTED_FIXTURE_ROOT = "test/generated-selected";

    /// The contract the fixture record freezes, and the one the writer is
    /// pointed at there. NOT this repo's own `AddressRegistry`: the writer
    /// derives the file it writes from the contract name, and the committed
    /// declaration is not a file a fixture gets to overwrite.
    string constant FIXTURE_CONTRACT = "MockDeployable";

    /// A second contract frozen under one of the fixture record's tags, as a
    /// release naming two contracts writes it. Its name starts with
    /// `FIXTURE_CONTRACT`, so a selection that matched on a prefix would take
    /// it too.
    string constant FIXTURE_CONTRACT_SECOND = "MockDeployableV2";

    /// The contract every emitter test emits a released lib for.
    string constant EMITTED_CONTRACT = "AddressRegistry";

    /// The library every emitter test emits, derived from `EMITTED_CONTRACT`
    /// exactly as `writeReleasedSuitesLib` derives it.
    string constant EMITTED_LIBRARY = "LibAddressRegistryReleased";

    /// The candidate declaration the emitted metadata comes from.
    ///
    /// Every CONSENSUS field is zero, so an emitter that took one of the four
    /// frozen fields from the template rather than from the record would emit a
    /// zero and be seen doing it. Only the key, the artifact path and the
    /// dependencies are meant to come from here.
    /// @return The template.
    function emitterTemplate() internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: "address-registry",
            creationCode: "",
            storedDeployedAddress: address(0),
            storedBytecodeHash: bytes32(0),
            storedRuntimeCode: "",
            artifactPath: "src/concrete/AddressRegistry.sol:AddressRegistry",
            dependencies: new address[](0)
        });
    }

    /// A record of `count` releases, `0_0_1` upwards, as
    /// `frozenSnapshotPaths` spells them.
    /// @param count How many releases.
    /// @return paths The record's files.
    function recordOf(uint256 count) internal pure returns (string[] memory paths) {
        paths = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            paths[i] = string.concat(
                LibRainDeploySnapshot.LIB_FS_ROOT, "/0_0_", vm.toString(i + 1), "/", EMITTED_CONTRACT, ".sol"
            );
        }
    }

    /// The aliased import one release contributes.
    /// @param tag The release tag.
    /// @return The import statement, and the blank line after it.
    function expectedImport(string memory tag) internal pure returns (string memory) {
        return string.concat(
            "import {\n    DEPLOYED_ADDRESS as AddressRegistry_",
            tag,
            "_DEPLOYED_ADDRESS,\n    BYTECODE_HASH as AddressRegistry_",
            tag,
            "_BYTECODE_HASH,\n    CREATION_CODE as AddressRegistry_",
            tag,
            "_CREATION_CODE,\n    RUNTIME_CODE as AddressRegistry_",
            tag,
            "_RUNTIME_CODE\n} from \"../generated/",
            tag,
            "/AddressRegistry.sol\";\n\n"
        );
    }

    /// The generated library's text from its title down to the line that opens
    /// `releasedSuites`. The same for every record, so the per-record
    /// assertions below are about the entries.
    string constant EXPECTED_LIBRARY_HEADER = "/// @title LibAddressRegistryReleased\n"
        "/// @notice Every frozen release of `AddressRegistry`: one entry per file in\n"
        "/// the append-only `src/generated/<tag>/` record, in tag order.\n" "///\n"
        "/// The deploy address, code hash, creation code and runtime code of each\n"
        "/// entry are aliased from that release's own frozen snapshot, so the\n"
        "/// consensus record is read from the immutable file and from nowhere else.\n" "///\n"
        "/// The key, the artifact path and the dependencies are explorer and ordering\n"
        "/// metadata regenerated from the CURRENT declaration, and are not part of\n"
        "/// that record. A moved source path retroactively updates every entry's\n"
        "/// artifact path, which is intended: the alternative is parsing this\n"
        "/// generated file back in to preserve what it last said.\n" "library LibAddressRegistryReleased {\n"
        "    /// Every frozen release, in tag order.\n" "    /// @return suites The released suites.\n"
        "    function releasedSuites() internal pure returns (DeploySuite[] memory suites) {\n";

    /// The entry one release contributes, with no dependencies.
    /// @param index The entry's index.
    /// @param tag The release tag.
    /// @return The entry's statements.
    function expectedEntry(string memory index, string memory tag) internal pure returns (string memory) {
        return string.concat(
            "        address[] memory dependencies",
            index,
            " = new address[](0);\n        suites[",
            index,
            "] = DeploySuite({\n            suite: \"address-registry@",
            tag,
            "\",\n            creationCode: AddressRegistry_",
            tag,
            "_CREATION_CODE,\n            storedDeployedAddress: AddressRegistry_",
            tag,
            "_DEPLOYED_ADDRESS,\n            storedBytecodeHash: AddressRegistry_",
            tag,
            "_BYTECODE_HASH,\n            storedRuntimeCode: AddressRegistry_",
            tag,
            "_RUNTIME_CODE,\n            artifactPath: \"src/concrete/AddressRegistry.sol:AddressRegistry\",\n",
            "            dependencies: dependencies",
            index,
            "\n        });\n"
        );
    }

    /// The import block MUST carry all four consensus constants of every record
    /// file and nothing else, aliased so that two releases of one contract, and
    /// two contracts in one release, are all distinct names.
    ///
    /// The four aliased fields are the whole of what a released entry says
    /// about consensus, so an import that goes missing is a field that silently
    /// falls back to whatever else is in scope.
    function testReleasedImportBlockAliasesEveryRecord() external pure {
        assertEq(
            LibRainDeploySnapshot.releasedImportBlock(vm, recordOf(0)),
            "import {DeploySuite} from \"../abstract/RainDeploySuitesBase.sol\";\n\n"
        );

        assertEq(
            LibRainDeploySnapshot.releasedImportBlock(vm, recordOf(1)),
            string.concat(
                "import {DeploySuite} from \"../abstract/RainDeploySuitesBase.sol\";\n\n", expectedImport("0_0_1")
            )
        );

        assertEq(
            LibRainDeploySnapshot.releasedImportBlock(vm, recordOf(2)),
            string.concat(
                "import {DeploySuite} from \"../abstract/RainDeploySuitesBase.sol\";\n\n",
                expectedImport("0_0_1"),
                expectedImport("0_0_2")
            )
        );
    }

    /// The library block MUST declare one suite per record file, taking the
    /// four consensus fields from that file's aliased constants and the other
    /// three from the template.
    ///
    /// A record with nothing in it is the state of every deploy repo before its
    /// first release, including this one, and it MUST still emit a compiling
    /// library: the declaration is imported by ordinary source, so a repo that
    /// could not emit one before its first release could not build.
    function testReleasedLibraryBlockDeclaresEveryRecord() external pure {
        assertEq(
            LibRainDeploySnapshot.releasedLibraryBlock(
                vm, EMITTED_LIBRARY, EMITTED_CONTRACT, recordOf(0), emitterTemplate()
            ),
            string.concat(EXPECTED_LIBRARY_HEADER, "        suites = new DeploySuite[](0);\n", "    }\n}\n")
        );

        assertEq(
            LibRainDeploySnapshot.releasedLibraryBlock(
                vm, EMITTED_LIBRARY, EMITTED_CONTRACT, recordOf(1), emitterTemplate()
            ),
            string.concat(
                EXPECTED_LIBRARY_HEADER,
                "        suites = new DeploySuite[](1);\n",
                expectedEntry("0", "0_0_1"),
                "    }\n}\n"
            )
        );

        assertEq(
            LibRainDeploySnapshot.releasedLibraryBlock(
                vm, EMITTED_LIBRARY, EMITTED_CONTRACT, recordOf(2), emitterTemplate()
            ),
            string.concat(
                EXPECTED_LIBRARY_HEADER,
                "        suites = new DeploySuite[](2);\n",
                expectedEntry("0", "0_0_1"),
                expectedEntry("1", "0_0_2"),
                "    }\n}\n"
            )
        );
    }

    /// The key MUST be the template's with the tag appended, so a repo with
    /// several releases of one contract declares several DISTINCT suites.
    /// `allSuites` refuses a duplicate key, so a key that did not carry the tag
    /// would make the second release unreachable and the whole declaration
    /// revert.
    function testReleasedLibraryBlockKeysAreUniquePerRelease() external pure {
        string memory emitted = LibRainDeploySnapshot.releasedLibraryBlock(
            vm, EMITTED_LIBRARY, EMITTED_CONTRACT, recordOf(2), emitterTemplate()
        );

        assertTrue(vm.contains(emitted, "suite: \"address-registry@0_0_1\""));
        assertTrue(vm.contains(emitted, "suite: \"address-registry@0_0_2\""));
    }

    /// The dependencies MUST be the template's, element for element. They are
    /// what a broadcast checks is already on chain before it deploys anything,
    /// so an entry that dropped them would deploy a suite whose constructor
    /// reads an address with no code.
    function testReleasedLibraryBlockCarriesTheTemplateDependencies() external pure {
        DeploySuite memory template = emitterTemplate();
        template.dependencies = new address[](2);
        template.dependencies[0] = address(0xdead);
        template.dependencies[1] = address(0xbeef);

        assertEq(
            LibRainDeploySnapshot.releasedLibraryBlock(vm, EMITTED_LIBRARY, EMITTED_CONTRACT, recordOf(1), template),
            string.concat(
                EXPECTED_LIBRARY_HEADER,
                "        suites = new DeploySuite[](1);\n",
                "        address[] memory dependencies0 = new address[](2);\n",
                "        dependencies0[0] = address(",
                vm.toString(address(0xdead)),
                ");\n        dependencies0[1] = address(",
                vm.toString(address(0xbeef)),
                ");\n        suites[0] = DeploySuite({\n            suite: \"address-registry@0_0_1\",\n",
                "            creationCode: AddressRegistry_0_0_1_CREATION_CODE,\n",
                "            storedDeployedAddress: AddressRegistry_0_0_1_DEPLOYED_ADDRESS,\n",
                "            storedBytecodeHash: AddressRegistry_0_0_1_BYTECODE_HASH,\n",
                "            storedRuntimeCode: AddressRegistry_0_0_1_RUNTIME_CODE,\n",
                "            artifactPath: \"src/concrete/AddressRegistry.sol:AddressRegistry\",\n",
                "            dependencies: dependencies0\n        });\n",
                "    }\n}\n"
            )
        );
    }

    /// Releases MUST be emitted in the order they were cut, comparing tags as
    /// VERSIONS. `0_10_0` follows `0_9_0` as a release and precedes it as text,
    /// so a sort on the raw string misorders every record that outlives a
    /// single-digit component.
    ///
    /// Files frozen under one tag are ordered by path, so the emitted file does
    /// not change with whatever order the filesystem happened to hand the walk
    /// — a generated file that moves on its own is a diff on every build. A
    /// record directory holds every file in it and there is no extension to
    /// filter on, so one name being the whole start of another is a state the
    /// order has to settle too.
    function testSortedRecordPathsOrdersTagsAsVersions() external pure {
        string[] memory paths = new string[](5);
        paths[0] = "src/generated/1_0_0/AddressRegistry.sol";
        paths[1] = "src/generated/0_9_0/AddressRegistry.sol.orig";
        paths[2] = "src/generated/0_9_0/Second.sol";
        paths[3] = "src/generated/0_10_0/AddressRegistry.sol";
        paths[4] = "src/generated/0_9_0/AddressRegistry.sol";

        string[] memory sorted = LibRainDeploySnapshot.sortedRecordPaths(vm, paths);

        assertEq(sorted.length, 5);
        assertEq(sorted[0], "src/generated/0_9_0/AddressRegistry.sol");
        assertEq(sorted[1], "src/generated/0_9_0/AddressRegistry.sol.orig");
        assertEq(sorted[2], "src/generated/0_9_0/Second.sol");
        assertEq(sorted[3], "src/generated/0_10_0/AddressRegistry.sol");
        assertEq(sorted[4], "src/generated/1_0_0/AddressRegistry.sol");
    }

    /// A record holds every contract a repo has ever frozen, and a released lib
    /// describes ONE of them. The selection MUST be by whole contract name,
    /// over releases only, in tag order.
    ///
    /// Two contracts under one tag is what a release naming two of them writes.
    /// Emitting the other one's snapshot into this contract's lib would give it
    /// this contract's suite key, colliding with this contract's own entry for
    /// that tag and reverting `allSuites()` for everything downstream.
    ///
    /// The fixture record is written newest tag first, so the order returned is
    /// the sort's and not whatever order the walk came back in.
    function testRecordPathsForContractSelectsOneContractInTagOrder() external {
        writeFixture(string.concat(SELECTED_FIXTURE_ROOT, "/0_10_0/", FIXTURE_CONTRACT, ".sol"));
        writeFixture(string.concat(SELECTED_FIXTURE_ROOT, "/0_9_0/", FIXTURE_CONTRACT, ".sol"));
        writeFixture(string.concat(SELECTED_FIXTURE_ROOT, "/0_9_0/", FIXTURE_CONTRACT_SECOND, ".sol"));
        // Not releases: the rolling snapshot, and a scratch directory a test or
        // a human left behind.
        writeFixture(
            string.concat(SELECTED_FIXTURE_ROOT, "/", LibRainDeploySnapshot.CANDIDATE, "/", FIXTURE_CONTRACT, ".sol")
        );
        writeFixture(string.concat(SELECTED_FIXTURE_ROOT, "/collision-guard/", FIXTURE_CONTRACT, ".sol"));

        string[] memory selected =
            LibRainDeploySnapshot.recordPathsForContract(vm, SELECTED_FIXTURE_ROOT, FIXTURE_CONTRACT);

        // The contract asked for is the contract selected, and the one frozen
        // beside it has its own single release rather than none.
        string[] memory second =
            LibRainDeploySnapshot.recordPathsForContract(vm, SELECTED_FIXTURE_ROOT, FIXTURE_CONTRACT_SECOND);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(SELECTED_FIXTURE_ROOT, true);

        assertEq(selected.length, 2);
        assertEq(selected[0], string.concat(SELECTED_FIXTURE_ROOT, "/0_9_0/", FIXTURE_CONTRACT, ".sol"));
        assertEq(selected[1], string.concat(SELECTED_FIXTURE_ROOT, "/0_10_0/", FIXTURE_CONTRACT, ".sol"));

        assertEq(second.length, 1);
        assertEq(second[0], string.concat(SELECTED_FIXTURE_ROOT, "/0_9_0/", FIXTURE_CONTRACT_SECOND, ".sol"));
    }

    /// The writer MUST emit the record root it is HANDED, selected down to the
    /// contract it names, and nothing else in that tree.
    ///
    /// The record root is a parameter, so a fixture record goes straight into
    /// the writer: pointed at a root it was not given, or handed the record
    /// whole, the file it writes says so. The fixture record is written newest
    /// tag first, so the emitted order is the sort's and not the walk's.
    ///
    /// A fixture contract name, so the file written is the fixture's own and
    /// not this repo's committed declaration. Removed BEFORE the assertions,
    /// because an emitted lib importing a record that only a test wrote does
    /// not compile, and forge-std assertions revert — undoing afterwards is
    /// undoing in every case except the one this test exists to report.
    function testWriteReleasedSuitesLibReadsTheRecordItIsHanded() external {
        writeFixture(string.concat(RELEASED_FIXTURE_ROOT, "/0_10_0/", FIXTURE_CONTRACT, ".sol"));
        writeFixture(string.concat(RELEASED_FIXTURE_ROOT, "/0_9_0/", FIXTURE_CONTRACT, ".sol"));
        writeFixture(string.concat(RELEASED_FIXTURE_ROOT, "/0_9_0/", FIXTURE_CONTRACT_SECOND, ".sol"));
        // Not releases: the rolling snapshot, and a scratch directory a test or
        // a human left behind.
        writeFixture(
            string.concat(RELEASED_FIXTURE_ROOT, "/", LibRainDeploySnapshot.CANDIDATE, "/", FIXTURE_CONTRACT, ".sol")
        );
        writeFixture(string.concat(RELEASED_FIXTURE_ROOT, "/collision-guard/", FIXTURE_CONTRACT, ".sol"));

        string[] memory paths = new string[](2);
        paths[0] = string.concat(RELEASED_FIXTURE_ROOT, "/0_9_0/", FIXTURE_CONTRACT, ".sol");
        paths[1] = string.concat(RELEASED_FIXTURE_ROOT, "/0_10_0/", FIXTURE_CONTRACT, ".sol");

        string memory libraryName = string.concat("Lib", FIXTURE_CONTRACT, "Released");
        string memory path = string.concat("src/lib/", libraryName, ".sol");

        string memory written = LibRainDeploySnapshot.writeReleasedSuitesLib(
            vm, RELEASED_FIXTURE_ROOT, FIXTURE_CONTRACT, emitterTemplate()
        );

        string memory emitted = vm.readFile(path);
        // Built while the fixture record is still there: both emitters read it.
        string memory expected = string.concat(
            "// SPDX-License",
            "-Identifier: LicenseRef-DCL-1.0\n",
            "// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd\n",
            "pragma solidity ^0.8.25;\n\n",
            "// THIS FILE IS AUTOGENERATED BY THE BUILD SCRIPT. DO NOT EDIT BY HAND.\n\n",
            LibRainDeploySnapshot.releasedImportBlock(vm, paths),
            LibRainDeploySnapshot.releasedLibraryBlock(vm, libraryName, FIXTURE_CONTRACT, paths, emitterTemplate())
        );

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeFile(path);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(RELEASED_FIXTURE_ROOT, true);

        assertEq(written, path);
        assertEq(emitted, expected);
        assertFalse(vm.contains(emitted, FIXTURE_CONTRACT_SECOND));
        assertFalse(vm.contains(emitted, LibRainDeploySnapshot.CANDIDATE));
        assertFalse(vm.contains(emitted, "collision-guard"));
    }

    /// The released lib MUST land beside the alias lib, under the name derived
    /// from the contract, holding exactly the prefix, imports and library the
    /// emitters produce.
    ///
    /// Run against this repo's REAL record and its real contract, so what it
    /// writes is the committed generated file — that is the whole of what makes
    /// a stale generated file a test failure rather than a silent one. Restored
    /// BEFORE the assertions run, because forge-std assertions revert: restoring
    /// afterwards restores in every case except a failure, which is the only
    /// case where the tree is dirty and the one this test exists to report.
    function testWriteReleasedSuitesLibWritesTheLibAtItsPath() external {
        string memory path = "src/lib/LibAddressRegistryReleased.sol";
        string memory before = vm.readFile(path);

        string memory written = LibRainDeploySnapshot.writeReleasedSuitesLib(
            vm, LibRainDeploySnapshot.LIB_FS_ROOT, EMITTED_CONTRACT, emitterTemplate()
        );
        string memory emitted = vm.readFile(path);

        string[] memory paths =
            LibRainDeploySnapshot.recordPathsForContract(vm, LibRainDeploySnapshot.LIB_FS_ROOT, EMITTED_CONTRACT);
        string memory expected = string.concat(
            "// SPDX-License",
            "-Identifier: LicenseRef-DCL-1.0\n",
            "// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd\n",
            "pragma solidity ^0.8.25;\n\n",
            "// THIS FILE IS AUTOGENERATED BY THE BUILD SCRIPT. DO NOT EDIT BY HAND.\n\n",
            LibRainDeploySnapshot.releasedImportBlock(vm, paths),
            LibRainDeploySnapshot.releasedLibraryBlock(vm, EMITTED_LIBRARY, EMITTED_CONTRACT, paths, emitterTemplate())
        );

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(path, before);

        assertEq(written, path);
        assertEq(emitted, expected);
    }

    /// A freeze that names no contracts MUST be refused. It would write
    /// nothing, report success, and leave `<tag>/` there — and an empty
    /// `<tag>/` is a frozen tag, so the real cut of that release could never
    /// happen afterwards.
    function testFreezeRefusesAnEmptyRelease() external {
        string memory tag = LibRainDeploySnapshot.deployTag(vm);

        vm.expectRevert(abi.encodeWithSelector(EmptyRelease.selector, tag));
        this.externalFreeze(new string[](0));

        assertFalse(vm.exists(LibRainDeploySnapshot.dirForSnapshot(tag)));
    }

    /// A freeze that throws MUST leave NOTHING behind. Filesystem cheatcodes
    /// survive a revert, so a `<tag>/` created before the last thing that can
    /// fail is a partial record that outlives the failure — and it is a frozen
    /// tag, which the immutability check then refuses the retry of, forever.
    /// The exit from that state is deleting a directory this design calls
    /// append-only, so the ordering here is what keeps a failed release
    /// retryable at all.
    function testFreezeLeavesNothingBehindWhenThereIsNothingToFreeze() external {
        string memory tag = LibRainDeploySnapshot.deployTag(vm);
        string[] memory contractNames = new string[](1);
        contractNames[0] = "NoSuchContract";

        vm.expectRevert(
            abi.encodeWithSelector(
                NothingToFreeze.selector,
                LibRainDeploySnapshot.pathForSnapshot(LibRainDeploySnapshot.CANDIDATE, contractNames[0])
            )
        );
        this.externalFreeze(contractNames);

        assertFalse(vm.exists(LibRainDeploySnapshot.dirForSnapshot(tag)));
    }
}
