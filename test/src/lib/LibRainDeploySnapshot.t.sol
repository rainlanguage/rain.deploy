// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    EmptyRelease,
    LibRainDeploySnapshot,
    NothingToFreeze,
    SnapshotAlreadyFrozen,
    UnreleasableVersion
} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";

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
    /// FIRST" the same observation — which is why the ordering itself is
    /// driven by `regenerateFreezeFixture` instead.
    function noRegeneration() internal {}

    /// External wrapper so `vm.expectRevert` lands at the right call depth, for
    /// the guards that are about this repo's REAL record.
    /// @param contractNames The contracts to freeze.
    function externalFreeze(string[] memory contractNames) external {
        LibRainDeploySnapshot.freeze(vm, LibRainDeploySnapshot.LIB_FS_ROOT, noRegeneration, contractNames);
    }

    /// External wrapper so `vm.expectRevert` lands at the right call depth, for
    /// the guards driven against a fixture record.
    /// @param root The record root to freeze into.
    /// @param contractNames The contracts to freeze.
    function externalFreezeAt(string memory root, string[] memory contractNames) external {
        LibRainDeploySnapshot.freeze(vm, root, noRegeneration, contractNames);
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

    /// Whether `paths` holds `path`. The walk's order is the filesystem's, so
    /// membership is the only thing worth asserting about it.
    /// @param paths The paths returned by the walk.
    /// @param path The path to look for.
    /// @return Whether it is there.
    function holdsPath(string[] memory paths, string memory path) internal pure returns (bool) {
        for (uint256 i = 0; i < paths.length; i++) {
            if (keccak256(bytes(paths[i])) == keccak256(bytes(path))) {
                return true;
            }
        }
        return false;
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

        assertTrue(holdsPath(paths, string.concat(FIXTURE_ROOT, "/0_0_1/MockDeployable.sol")));
        assertTrue(holdsPath(paths, string.concat(FIXTURE_ROOT, "/0_0_2/MockDeployableV2.sol")));
        assertTrue(holdsPath(paths, string.concat(FIXTURE_ROOT, "/0_0_2/Second.sol")));
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
            holdsPath(
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

        // The same two paths under a record root that is not the real one, so
        // the shape a fixture record is built and read at is pinned rather than
        // only implied by the real root's.
        assertEq(LibRainDeploySnapshot.dirForSnapshot("test/generated-x", "0_1_7"), "test/generated-x/0_1_7");
        assertEq(
            LibRainDeploySnapshot.pathForSnapshot("test/generated-x", "0_1_7", "Foo"), "test/generated-x/0_1_7/Foo.sol"
        );
    }

    /// The root-aware snapshot path and the one `LibFs` writes MUST be ONE path
    /// wherever both can spell it.
    ///
    /// `LibFs` takes no root, so a fixture record is the one thing it cannot
    /// spell — and `freeze` reads and writes through the root-aware spelling
    /// for the REAL record too, so this is the whole of what keeps the path a
    /// release is frozen to the path the regeneration wrote it at. Two
    /// spellings of one path is how a freeze silently reads nothing, and this
    /// is where they are held to being one.
    ///
    /// Fuzzed over the name rather than pinned to a literal because the
    /// property is about every path either could produce, not about a chosen
    /// one: a divergence that only appears for some names is exactly the
    /// silence this is here to remove.
    /// @param dir The snapshot directory name.
    /// @param contractName The name of the contract.
    function testRootAwareSnapshotPathIsTheWritersAtTheRealRoot(string memory dir, string memory contractName)
        external
        pure
    {
        assertEq(
            LibRainDeploySnapshot.pathForSnapshot(LibRainDeploySnapshot.LIB_FS_ROOT, dir, contractName),
            LibRainDeploySnapshot.pathForSnapshot(dir, contractName)
        );
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

    /// Where the freeze fixture's record is built. Its own tree, for the same
    /// reason `RELEASED_FIXTURE_ROOT` is not `FIXTURE_ROOT`, and NOT
    /// `src/generated`: every freeze here cuts a release under THIS repo's
    /// tag, and a transient `<tag>/` in the real record is a release the
    /// inherited record check has to fail on, from contracts forge runs in
    /// parallel with this one.
    string constant FREEZE_FIXTURE_ROOT = "test/generated-freeze";

    /// Where the multi-contract freeze fixture's record is built. Its own tree
    /// again, and for a sharper reason than the others: every freeze test cuts
    /// the SAME tag, so two of them sharing a root would have whichever ran
    /// second refused as a re-cut.
    string constant FREEZE_MULTI_FIXTURE_ROOT = "test/generated-freeze-multi";

    /// Where the re-cut fixture's record is built. Its own tree: this one is
    /// deliberately left frozen between the two calls, so no other test may
    /// share it.
    string constant RECUT_FIXTURE_ROOT = "test/generated-recut";

    /// Where the empty-tag-directory fixture's record is built. Its own tree,
    /// for the same reason: it is a frozen tag from the moment it is created.
    string constant RECUT_EMPTY_FIXTURE_ROOT = "test/generated-recut-empty";

    /// What the freeze fixture's regeneration writes, and what a freeze that
    /// ran the regeneration first therefore copies.
    ///
    /// The SPDX identifier is split for the reason `writeFixture` splits it: a
    /// run that fails midway leaves this content on disk, and an unlicensed
    /// file in the tree is a second failure on top of the first.
    /// @return The regenerated rolling snapshot.
    function freshRolling() internal pure returns (string memory) {
        return string.concat(
            "// SPDX-License",
            "-Identifier: LicenseRef-DCL-1.0\n",
            "address constant DEPLOYED_ADDRESS = address(0xFEED000000000000000000000000000000000000);\n"
        );
    }

    /// What is on disk before the call, and what a freeze that read the rolling
    /// snapshot before regenerating it would copy instead.
    /// @return The stale rolling snapshot.
    function staleRolling() internal pure returns (string memory) {
        return string.concat(
            "// SPDX-License",
            "-Identifier: LicenseRef-DCL-1.0\n",
            "address constant DEPLOYED_ADDRESS = address(0x57A1E00000000000000000000000000000000000);\n"
        );
    }

    /// A regeneration that really regenerates, so "the guard fired FIRST" is no
    /// longer the only thing a freeze test can observe.
    function regenerateFreezeFixture() internal {
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(
            LibRainDeploySnapshot.pathForSnapshot(
                FREEZE_FIXTURE_ROOT, LibRainDeploySnapshot.CANDIDATE, FIXTURE_CONTRACT
            ),
            freshRolling()
        );
    }

    /// A freeze MUST copy the bytes the regeneration wrote, not the bytes that
    /// were on disk when it was called, and the copy MUST land where the record
    /// walk finds it.
    ///
    /// Freezing a stale candidate is silent: the immutability check only fires
    /// on a re-cut, which is too late, so nothing downstream ever learns that a
    /// release records bytes its own deploy did not produce. The ordering is
    /// therefore the whole of what makes a release describe itself, and with a
    /// no-op regeneration it is unobservable — a `freeze` that read before it
    /// regenerated would pass every other test in this file.
    function testFreezeCopiesTheRegeneratedRollingSnapshot() external {
        string memory tag = LibRainDeploySnapshot.deployTag(vm);
        string memory rollingPath = LibRainDeploySnapshot.pathForSnapshot(
            FREEZE_FIXTURE_ROOT, LibRainDeploySnapshot.CANDIDATE, FIXTURE_CONTRACT
        );
        string memory frozenPath = LibRainDeploySnapshot.pathForSnapshot(FREEZE_FIXTURE_ROOT, tag, FIXTURE_CONTRACT);

        writeFixture(rollingPath);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(rollingPath, staleRolling());

        string[] memory contractNames = new string[](1);
        contractNames[0] = FIXTURE_CONTRACT;
        LibRainDeploySnapshot.freeze(vm, FREEZE_FIXTURE_ROOT, regenerateFreezeFixture, contractNames);

        // Read while the fixture is still there, asserted once it is gone.
        bool frozenExists = vm.exists(frozenPath);
        string memory frozen = frozenExists ? vm.readFile(frozenPath) : "";
        // The cut is a release the record walk finds, under the tag the version
        // maps to and nowhere else.
        string[] memory record = LibRainDeploySnapshot.frozenSnapshotPaths(vm, FREEZE_FIXTURE_ROOT);
        // And the rolling snapshot is the regenerated one, still in place: a
        // freeze MOVES nothing, it copies.
        string memory rolling = vm.readFile(rollingPath);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(FREEZE_FIXTURE_ROOT, true);

        assertTrue(frozenExists);
        assertEq(frozen, freshRolling());
        assertNotEq(frozen, staleRolling());
        assertEq(rolling, freshRolling());
        assertEq(record.length, 1);
        assertEq(record[0], frozenPath);
    }

    /// A release naming SEVERAL contracts MUST freeze every one of them.
    ///
    /// A contract regenerated but absent from the record is a contract silently
    /// missing from the release, and a tag that never held it has nothing
    /// missing from it for anything downstream to notice.
    function testFreezeCutsEveryNamedContract() external {
        string memory tag = LibRainDeploySnapshot.deployTag(vm);
        string[] memory contractNames = new string[](2);
        contractNames[0] = FIXTURE_CONTRACT;
        contractNames[1] = FIXTURE_CONTRACT_SECOND;
        for (uint256 i = 0; i < contractNames.length; i++) {
            writeFixture(
                LibRainDeploySnapshot.pathForSnapshot(
                    FREEZE_MULTI_FIXTURE_ROOT, LibRainDeploySnapshot.CANDIDATE, contractNames[i]
                )
            );
        }

        LibRainDeploySnapshot.freeze(vm, FREEZE_MULTI_FIXTURE_ROOT, noRegeneration, contractNames);

        string[] memory record = LibRainDeploySnapshot.frozenSnapshotPaths(vm, FREEZE_MULTI_FIXTURE_ROOT);
        bool first =
            holdsPath(record, LibRainDeploySnapshot.pathForSnapshot(FREEZE_MULTI_FIXTURE_ROOT, tag, contractNames[0]));
        bool second =
            holdsPath(record, LibRainDeploySnapshot.pathForSnapshot(FREEZE_MULTI_FIXTURE_ROOT, tag, contractNames[1]));

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(FREEZE_MULTI_FIXTURE_ROOT, true);

        assertTrue(first);
        assertTrue(second);
        assertEq(record.length, 2);
    }

    /// A release is cut ONCE. Re-cutting a tag that already has a record MUST
    /// be refused, naming the tag and the directory, and MUST leave the
    /// original record exactly as it was.
    ///
    /// That record is what consumers of that release pin their bytecode
    /// against, and a second cut would replace it with whatever the candidate
    /// currently is — which, between releases, is ordinarily something else.
    /// This is the only protection there is on the immutability of
    /// `src/generated/<tag>/`.
    function testFreezeRefusesARecutRelease() external {
        string memory tag = LibRainDeploySnapshot.deployTag(vm);
        string memory frozenDir = LibRainDeploySnapshot.dirForSnapshot(RECUT_FIXTURE_ROOT, tag);
        string memory frozenPath = LibRainDeploySnapshot.pathForSnapshot(RECUT_FIXTURE_ROOT, tag, FIXTURE_CONTRACT);
        string memory rollingPath = LibRainDeploySnapshot.pathForSnapshot(
            RECUT_FIXTURE_ROOT, LibRainDeploySnapshot.CANDIDATE, FIXTURE_CONTRACT
        );

        writeFixture(rollingPath);
        string[] memory contractNames = new string[](1);
        contractNames[0] = FIXTURE_CONTRACT;

        LibRainDeploySnapshot.freeze(vm, RECUT_FIXTURE_ROOT, noRegeneration, contractNames);
        string memory firstCut = vm.readFile(frozenPath);

        // The candidate moves on, exactly as source does between releases, so
        // an accepted re-cut would be seen writing something else.
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(rollingPath, freshRolling());

        vm.expectRevert(abi.encodeWithSelector(SnapshotAlreadyFrozen.selector, tag, frozenDir));
        this.externalFreezeAt(RECUT_FIXTURE_ROOT, contractNames);

        // Read while the fixture is still there, asserted once it is gone.
        string memory afterRefusal = vm.readFile(frozenPath);
        string[] memory record = LibRainDeploySnapshot.frozenSnapshotPaths(vm, RECUT_FIXTURE_ROOT);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(RECUT_FIXTURE_ROOT, true);

        assertEq(afterRefusal, firstCut);
        assertNotEq(afterRefusal, freshRolling());
        assertEq(record.length, 1);
    }

    /// The refusal is about the DIRECTORY existing, not about what is in it, so
    /// an empty `<tag>/` left behind by anything refuses the real cut too.
    ///
    /// That is not a wrinkle, it is why `EmptyRelease` and the write ordering
    /// exist: the exit from a wedged tag is deleting a directory this design
    /// calls append-only, so everything that could leave one behind is refused
    /// up front instead.
    function testFreezeRefusesATagDirectoryThatIsEmpty() external {
        string memory tag = LibRainDeploySnapshot.deployTag(vm);
        string memory frozenDir = LibRainDeploySnapshot.dirForSnapshot(RECUT_EMPTY_FIXTURE_ROOT, tag);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(frozenDir, true);
        // Everything else a cut needs is ready, so the refusal can only be
        // about the directory.
        writeFixture(
            LibRainDeploySnapshot.pathForSnapshot(
                RECUT_EMPTY_FIXTURE_ROOT, LibRainDeploySnapshot.CANDIDATE, FIXTURE_CONTRACT
            )
        );

        string[] memory contractNames = new string[](1);
        contractNames[0] = FIXTURE_CONTRACT;

        vm.expectRevert(abi.encodeWithSelector(SnapshotAlreadyFrozen.selector, tag, frozenDir));
        this.externalFreezeAt(RECUT_EMPTY_FIXTURE_ROOT, contractNames);

        // Read while the fixture is still there, asserted once it is gone: the
        // tag holds no record at all and the cut is refused anyway.
        string[] memory record = LibRainDeploySnapshot.frozenSnapshotPaths(vm, RECUT_EMPTY_FIXTURE_ROOT);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(RECUT_EMPTY_FIXTURE_ROOT, true);

        assertEq(record.length, 0);
    }
}
