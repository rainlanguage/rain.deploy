// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    EmptyRelease,
    LibRainDeploySnapshot,
    NonMonotonicRelease,
    NothingToFreeze,
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
    /// FIRST" the same observation.
    function noRegeneration() internal {}

    /// External wrapper so `vm.expectRevert` lands at the right call depth.
    /// @param contractNames The contracts to freeze.
    function externalFreeze(string[] memory contractNames) external {
        LibRainDeploySnapshot.freeze(vm, noRegeneration, contractNames);
    }

    /// External wrapper so `vm.expectRevert` lands at the right call depth. The
    /// accepting cases go through it too, so both answers are the same call.
    /// @param recordRoot The record root to check against.
    /// @param tag The release tag being cut.
    function externalCheckReleaseFollowsRecord(string memory recordRoot, string memory tag) external view {
        LibRainDeploySnapshot.checkReleaseFollowsRecord(vm, recordRoot, tag);
    }

    /// A release tag from its components, as `tagForVersion` spells one.
    /// @param major The major component.
    /// @param minor The minor component.
    /// @param patch The patch component.
    /// @return The tag, e.g. `0_1_7`.
    function tagOf(uint8 major, uint8 minor, uint8 patch) internal pure returns (string memory) {
        return
            string.concat(
                vm.toString(uint256(major)), "_", vm.toString(uint256(minor)), "_", vm.toString(uint256(patch))
            );
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

    /// A component has ONE spelling. A padded component is the same release as
    /// its unpadded form: it freezes to a second directory the immutability
    /// check does not recognise as the first, and the two compare equal as
    /// versions so nothing can order them either.
    function testIsStrictTripleRefusesLeadingZeros() external pure {
        assertFalse(LibRainDeploySnapshot.isStrictTriple("0.01.5", "."));
        assertFalse(LibRainDeploySnapshot.isStrictTriple("01.1.5", "."));
        assertFalse(LibRainDeploySnapshot.isStrictTriple("0.1.05", "."));
        assertFalse(LibRainDeploySnapshot.isStrictTriple("00.0.0", "."));
        assertFalse(LibRainDeploySnapshot.isTag("0_01_5"));

        // The boundary: a single zero IS the number zero, and `0.0.0` is a real
        // version.
        assertTrue(LibRainDeploySnapshot.isStrictTriple("0.0.0", "."));
        assertTrue(LibRainDeploySnapshot.isStrictTriple("0.10.0", "."));
        assertTrue(LibRainDeploySnapshot.isStrictTriple("10.0.100", "."));
        assertTrue(LibRainDeploySnapshot.isTag("0_0_0"));
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

    /// The refusal MUST be reachable through the release path, naming the
    /// version, rather than only through the predicate.
    function testTagForVersionRefusesLeadingZeros() external {
        string[3] memory bad = ["0.01.5", "01.1.5", "0.1.05"];
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

    /// The root the record is WALKED from MUST be the root the writer WRITES
    /// to. They are two constants — `LIB_FS_ROOT` here, and the one
    /// `LibFs.pathForContract` hardcodes in a package this repo does not own —
    /// and a walk of a root nothing writes to returns nothing, which every
    /// record-anchored assertion then passes on. Silence is the failure mode,
    /// so it is asserted rather than observed.
    ///
    /// Compared through `pathForSnapshot`, which is what a snapshot is written
    /// through, so the right hand side is the writer's own root rather than a
    /// third restatement of it. The contract name is arbitrary — the path is
    /// built by concatenation and names no artifact.
    function testRecordRootIsTheRootTheWriterWritesTo() external pure {
        assertEq(
            LibRainDeploySnapshot.pathForSnapshot("0_1_7", "Foo"),
            string.concat(LibRainDeploySnapshot.LIB_FS_ROOT, "/0_1_7/Foo.sol")
        );
        assertEq(
            LibRainDeploySnapshot.dirForSnapshot(LibRainDeploySnapshot.CANDIDATE),
            string.concat(LibRainDeploySnapshot.LIB_FS_ROOT, "/", LibRainDeploySnapshot.CANDIDATE)
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

        string memory written = LibRainDeploySnapshot.writeSnapshot(
            vm, dir, "MockDeployable", type(MockDeployable).creationCode, new address[](0)
        );
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
    /// zero and be seen doing it. Only the key and the artifact path are meant
    /// to come from here — the dependency list is frozen into the record and
    /// aliased back out of it, which
    /// `testReleasedEntriesIgnoreTheTemplateDependencies` is the property for.
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
            "_RUNTIME_CODE,\n    DEPENDENCIES as AddressRegistry_",
            tag,
            "_DEPENDENCIES\n} from \"../generated/",
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
        "/// The deploy address, code hash, creation code, runtime code and dependency\n"
        "/// list of each entry are aliased from that release's own frozen snapshot, so\n"
        "/// what a release deployed, and what it required to already be on chain, are\n"
        "/// read from the immutable file and from nowhere else. A dependency dropped\n"
        "/// from current source stays required by the releases cut with it, and one\n"
        "/// added is not imposed on releases cut without it.\n" "///\n"
        "/// The key and the artifact path are explorer and ordering metadata\n"
        "/// regenerated from the CURRENT declaration, and are not part of that\n"
        "/// record. A moved source path retroactively updates every entry's artifact\n"
        "/// path, which is intended: the alternative is parsing this generated file\n"
        "/// back in to preserve what it last said.\n" "library LibAddressRegistryReleased {\n"
        "    /// Every frozen release, in tag order.\n" "    /// @return suites The released suites.\n"
        "    function releasedSuites() internal pure returns (DeploySuite[] memory suites) {\n";

    /// The entry one release contributes.
    /// @param index The entry's index.
    /// @param tag The release tag.
    /// @return The entry's statements.
    function expectedEntry(string memory index, string memory tag) internal pure returns (string memory) {
        return string.concat(
            "        suites[",
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
            "            dependencies: abi.decode(AddressRegistry_",
            tag,
            "_DEPENDENCIES, (address[]))\n        });\n"
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

    /// A released entry's dependency list MUST come from that release's OWN
    /// frozen snapshot, and the template's list MUST NOT reach it.
    ///
    /// The list is not metadata. `RainDeployBroadcast.run` hands
    /// `suite.dependencies` to `LibRainDeploy.deployToNetworks`, which reverts
    /// `MissingDependency` for any of them with no code on the target network —
    /// so it is a PRECONDITION of the broadcast, and re-broadcasting a past
    /// release onto a newly supported chain has to check the preconditions that
    /// release was cut with. Rebuilding it from the candidate declaration
    /// checks today's instead.
    ///
    /// The template here differs from what any record holds, so an emitter that
    /// still read it would be seen writing those addresses out. Two releases,
    /// because each MUST take its list from its own constant: one release
    /// inheriting its successor's is the same defect one step smaller.
    function testReleasedEntriesTakeDependenciesFromTheFrozenRecord() external pure {
        DeploySuite memory declared = emitterTemplate();
        declared.dependencies = new address[](2);
        declared.dependencies[0] = address(0xdead);
        declared.dependencies[1] = address(0xbeef);

        string memory emitted =
            LibRainDeploySnapshot.releasedLibraryBlock(vm, EMITTED_LIBRARY, EMITTED_CONTRACT, recordOf(2), declared);

        assertTrue(
            vm.contains(emitted, "dependencies: abi.decode(AddressRegistry_0_0_1_DEPENDENCIES, (address[]))"),
            "the first release does not read its own frozen dependency list"
        );
        assertTrue(
            vm.contains(emitted, "dependencies: abi.decode(AddressRegistry_0_0_2_DEPENDENCIES, (address[]))"),
            "the second release does not read its own frozen dependency list"
        );

        assertFalse(vm.contains(emitted, vm.toString(address(0xdead))), "the declaration's dependency was emitted");
        assertFalse(vm.contains(emitted, vm.toString(address(0xbeef))), "the declaration's dependency was emitted");
        assertFalse(vm.contains(emitted, "address[] memory"), "an entry still builds its list from the declaration");
    }

    /// PROPERTY: the emitted released lib is INDEPENDENT of the template's
    /// dependency list — byte identical under any list at all.
    ///
    /// The two failures this closes are the same property twice. A dependency
    /// DROPPED from current source must stay required by the releases cut with
    /// it, or an old release re-broadcast onto a new chain deploys against a
    /// precondition nobody checked. One ADDED must not be imposed on releases
    /// cut without it, or that re-broadcast reverts `MissingDependency` on
    /// something that release never needed. Both say current source cannot move
    /// a released entry's list, so it is stated as invariance rather than as
    /// two examples — two examples is also what a partial re-read passes.
    /// @param dependencies Whatever the candidate declaration now says.
    function testReleasedEntriesIgnoreTheTemplateDependencies(address[] memory dependencies) external pure {
        DeploySuite memory declared = emitterTemplate();
        declared.dependencies = dependencies;

        assertEq(
            LibRainDeploySnapshot.releasedLibraryBlock(vm, EMITTED_LIBRARY, EMITTED_CONTRACT, recordOf(2), declared),
            LibRainDeploySnapshot.releasedLibraryBlock(
                vm, EMITTED_LIBRARY, EMITTED_CONTRACT, recordOf(2), emitterTemplate()
            ),
            "the template's dependency list reached a released entry"
        );
    }

    /// Where the frozen-dependency round trip writes its snapshots. NOT tag
    /// shaped, for the reason `testWriteSnapshotWritesTheSnapshotAtItsPath`
    /// gives: the record root is the real `src/generated/`, walked by the
    /// inherited record check in contracts forge runs in parallel with this
    /// one, so a tag-shaped name here is a release they have to fail on.
    string constant DEPENDENCIES_FIXTURE_DIR = "write-dependencies-not-a-tag";

    /// Freezes `dependencies` into a snapshot and returns the source written.
    ///
    /// The EVM state is rolled back around the write so each call is an
    /// INDEPENDENT freeze. `writeSnapshot` deploys the creation code it is
    /// handed through the Zoltu factory, which is `CREATE2` under a zero salt,
    /// so one creation code lands at one address and a second deploy of it in
    /// the same test would fail on the first still being there. Filesystem
    /// cheatcodes are not undone by a state rollback, which is what makes the
    /// source read back the source that call wrote.
    /// @param dependencies The list to freeze.
    /// @return The snapshot source.
    function freezeDependencies(address[] memory dependencies) internal returns (string memory) {
        uint256 state = vm.snapshotState();
        string memory source = vm.readFile(
            LibRainDeploySnapshot.writeSnapshot(
                vm, DEPENDENCIES_FIXTURE_DIR, FIXTURE_CONTRACT, type(MockDeployable).creationCode, dependencies
            )
        );
        assertTrue(vm.revertToState(state), "the deploy state did not roll back");
        return source;
    }

    /// The `address[]` a snapshot's `DEPENDENCIES` constant holds, decoded out
    /// of the source the generator wrote.
    ///
    /// Read back out of the FILE rather than returned by the writer, because
    /// the file is the whole point: what a release required has to survive as
    /// bytes on disk that a repo whose source has since changed can still read.
    /// `abi.decode` here is the same expression `releasedLibraryBlock` emits
    /// into the released lib, so what that expression evaluates to is what this
    /// asserts about.
    /// @param source The snapshot source.
    /// @return The frozen dependency list.
    function frozenDependencies(string memory source) internal pure returns (address[] memory) {
        string[] memory afterName = vm.split(source, "bytes constant DEPENDENCIES =");
        string[] memory afterOpen = vm.split(afterName[1], "hex\"");
        return abi.decode(vm.parseBytes(string.concat("0x", vm.split(afterOpen[1], "\"")[0])), (address[]));
    }

    /// A snapshot MUST record the dependency list it is handed, exactly, and
    /// `abi.decode` MUST give that list back. This is the half of the freeze
    /// that lives on disk: the released lib only ever names the constant, so a
    /// list the constant does not hold is a list no release can read.
    ///
    /// The empty list is asserted because it is what every contract in this
    /// repo declares, and therefore the case a round trip is most likely to be
    /// quietly wrong about — an encoder that wrote nothing at all would look
    /// correct against this repo's own committed snapshots forever.
    function testWriteSnapshotFreezesTheDependencyList() external {
        address[] memory none = new address[](0);

        address[] memory one = new address[](1);
        one[0] = address(0xdead);

        address[] memory three = new address[](3);
        three[0] = address(0xdead);
        // A zero in the middle. `abi.encode` of an address array is not
        // self-delimiting, so a length or offset the round trip got wrong reads
        // a neighbouring word rather than failing, and zero is the value that
        // would hide it.
        three[1] = address(0);
        three[2] = address(0xbeef);

        // Read while the snapshots are still there, asserted once they are
        // gone: forge-std assertions revert, so undoing afterwards undoes in
        // every case except a failure.
        string memory sourceNone = freezeDependencies(none);
        string memory sourceOne = freezeDependencies(one);
        string memory sourceThree = freezeDependencies(three);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(LibRainDeploySnapshot.dirForSnapshot(DEPENDENCIES_FIXTURE_DIR), true);

        assertEq(frozenDependencies(sourceNone), none, "an empty list did not round trip as empty");
        assertEq(frozenDependencies(sourceOne), one, "a one element list did not round trip");
        assertEq(frozenDependencies(sourceThree), three, "a three element list did not round trip");
    }

    /// Tags MUST compare as VERSIONS and not as text. `0_10_0` follows `0_9_0`
    /// as a release and precedes it as a string, so a text comparison both
    /// misorders the record and, since the freeze's ordering guard asks this
    /// same question, would admit a release below the newest one.
    ///
    /// Strictly: a tag does not precede itself. That is the boundary the guard
    /// refuses on, so "follows" meaning "greater or equal" here would be a tag
    /// re-cut being called a new release.
    function testTagPrecedesComparesVersionsNotText() external pure {
        assertTrue(LibRainDeploySnapshot.tagPrecedes(vm, "0_9_0", "0_10_0"));
        assertFalse(LibRainDeploySnapshot.tagPrecedes(vm, "0_10_0", "0_9_0"));

        assertFalse(LibRainDeploySnapshot.tagPrecedes(vm, "0_1_7", "0_1_7"));

        // Every component, and the most significant one that differs decides.
        assertTrue(LibRainDeploySnapshot.tagPrecedes(vm, "0_1_6", "0_1_7"));
        assertFalse(LibRainDeploySnapshot.tagPrecedes(vm, "0_1_7", "0_1_6"));
        assertTrue(LibRainDeploySnapshot.tagPrecedes(vm, "0_1_9", "0_2_0"));
        assertFalse(LibRainDeploySnapshot.tagPrecedes(vm, "0_2_0", "0_1_9"));
        assertTrue(LibRainDeploySnapshot.tagPrecedes(vm, "0_9_9", "1_0_0"));
        assertFalse(LibRainDeploySnapshot.tagPrecedes(vm, "1_0_0", "0_9_9"));
    }

    /// Over EVERY pair of tags, the order MUST be the order of the components
    /// read as numbers, most significant first — a single wrong comparison is a
    /// record that sorts wrongly and a guard that admits the tag it sorts
    /// wrongly.
    /// @param aMajor The first tag's major component.
    /// @param aMinor The first tag's minor component.
    /// @param aPatch The first tag's patch component.
    /// @param bMajor The second tag's major component.
    /// @param bMinor The second tag's minor component.
    /// @param bPatch The second tag's patch component.
    function testTagPrecedesMatchesComponentOrder(
        uint8 aMajor,
        uint8 aMinor,
        uint8 aPatch,
        uint8 bMajor,
        uint8 bMinor,
        uint8 bPatch
    ) external pure {
        string memory a = tagOf(aMajor, aMinor, aPatch);
        string memory b = tagOf(bMajor, bMinor, bPatch);

        bool precedes = aMajor != bMajor
            ? aMajor < bMajor
            : (aMinor != bMinor ? aMinor < bMinor : (aPatch != bPatch ? aPatch < bPatch : false));

        assertEq(LibRainDeploySnapshot.tagPrecedes(vm, a, b), precedes);
        // Strict, so exactly one of the two orderings holds unless they are the
        // same release, when neither does.
        assertFalse(LibRainDeploySnapshot.tagPrecedes(vm, a, a));
        assertEq(LibRainDeploySnapshot.tagPrecedes(vm, b, a), !precedes && keccak256(bytes(a)) != keccak256(bytes(b)));
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

    /// Every record the ordering guard is driven against gets a root of its
    /// own, for the reason `RELEASED_FIXTURE_ROOT` is not `FIXTURE_ROOT`: forge
    /// runs the tests in a contract concurrently, and a guard test sees the
    /// wrong newest release the moment another test's fixture is in the tree it
    /// is reading.
    string constant NEWEST_FIXTURE_ROOT = "test/generated-newest";

    /// The record with nothing released in it. See `NEWEST_FIXTURE_ROOT`.
    string constant UNRELEASED_FIXTURE_ROOT = "test/generated-unreleased";

    /// The record a below-the-newest tag is refused against. See
    /// `NEWEST_FIXTURE_ROOT`.
    string constant BELOW_FIXTURE_ROOT = "test/generated-below";

    /// The record the newest tag itself is refused against. See
    /// `NEWEST_FIXTURE_ROOT`.
    string constant EQUAL_FIXTURE_ROOT = "test/generated-equal";

    /// The record strictly greater tags are accepted against. See
    /// `NEWEST_FIXTURE_ROOT`.
    string constant GREATER_FIXTURE_ROOT = "test/generated-greater";

    /// The record every fuzzed tag is put to. COMMITTED, and read only — see
    /// the fixture itself for why a fuzz cannot build the record it is put
    /// against.
    string constant FROZEN_FIXTURE_ROOT = "test/fixture-record";

    /// The one release in `FROZEN_FIXTURE_ROOT`. Every component is the same,
    /// so a fuzzed tag that differs in any one of them lands on one side of it
    /// or the other by that component alone.
    string constant FROZEN_FIXTURE_NEWEST = "1_1_1";

    /// The newest release is the greatest TAG, not a position in the walk. The
    /// walk's order is the filesystem's, so an answer read off either end of it
    /// is an answer about where a directory sorted rather than which release is
    /// newest — and the guard would then compare the tag being cut against the
    /// wrong release.
    ///
    /// `10_0_0` is the newest of these three and is neither the first nor the
    /// last of them by text, so both ends are wrong answers here.
    function testNewestFrozenTagIsTheGreatestReleaseNotAPositionInTheWalk() external {
        writeFixture(string.concat(NEWEST_FIXTURE_ROOT, "/0_1_0/", FIXTURE_CONTRACT, ".sol"));
        writeFixture(string.concat(NEWEST_FIXTURE_ROOT, "/10_0_0/", FIXTURE_CONTRACT, ".sol"));
        writeFixture(string.concat(NEWEST_FIXTURE_ROOT, "/9_0_0/", FIXTURE_CONTRACT, ".sol"));
        // Not releases: the rolling snapshot, and a scratch directory a test or
        // a human left behind. Neither is a release the next one has to follow.
        writeFixture(
            string.concat(NEWEST_FIXTURE_ROOT, "/", LibRainDeploySnapshot.CANDIDATE, "/", FIXTURE_CONTRACT, ".sol")
        );
        writeFixture(string.concat(NEWEST_FIXTURE_ROOT, "/collision-guard/", FIXTURE_CONTRACT, ".sol"));

        string memory newest = LibRainDeploySnapshot.newestFrozenTag(vm, NEWEST_FIXTURE_ROOT);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(NEWEST_FIXTURE_ROOT, true);

        assertEq(newest, "10_0_0");
    }

    /// A repo that has released nothing has nothing for a first release to
    /// follow, so EVERY tag MUST be accepted. That is the state of this repo
    /// today, so a guard that refused here would refuse the first release of
    /// every deploy repo that inherits it.
    ///
    /// Both spellings of "nothing released": a record root that is not there at
    /// all, and one that is there holding only a rolling snapshot.
    function testNoFrozenReleaseAcceptsAnyFirstRelease() external {
        assertEq(LibRainDeploySnapshot.newestFrozenTag(vm, MISSING_FIXTURE_ROOT), "");
        this.externalCheckReleaseFollowsRecord(MISSING_FIXTURE_ROOT, "0_0_1");
        this.externalCheckReleaseFollowsRecord(MISSING_FIXTURE_ROOT, "9_9_9");

        writeFixture(
            string.concat(UNRELEASED_FIXTURE_ROOT, "/", LibRainDeploySnapshot.CANDIDATE, "/", FIXTURE_CONTRACT, ".sol")
        );

        string memory newest = LibRainDeploySnapshot.newestFrozenTag(vm, UNRELEASED_FIXTURE_ROOT);
        this.externalCheckReleaseFollowsRecord(UNRELEASED_FIXTURE_ROOT, "0_0_1");

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(UNRELEASED_FIXTURE_ROOT, true);

        assertEq(newest, "");
    }

    /// A tag BELOW the newest release MUST be refused, and against the NEWEST
    /// release rather than any release. The record is append-only, so a tag
    /// frozen out of order is permanent: `releasedSuites()` declares it forever
    /// and the chain group then demands it stay live forever.
    ///
    /// This is the production shape. `0_1_9` is a plausible fat finger for the
    /// release after `0_2_0`, it is greater than a release that IS in the
    /// record, and every other guard admits it — its directory does not exist,
    /// its shape is a valid version, and the bytes it would freeze are the
    /// candidate's, already live on chain.
    function testCheckReleaseFollowsRecordRefusesATagBelowTheNewestRelease() external {
        writeFixture(string.concat(BELOW_FIXTURE_ROOT, "/0_1_0/", FIXTURE_CONTRACT, ".sol"));
        writeFixture(string.concat(BELOW_FIXTURE_ROOT, "/0_2_0/", FIXTURE_CONTRACT, ".sol"));

        vm.expectRevert(abi.encodeWithSelector(NonMonotonicRelease.selector, "0_1_9", "0_2_0"));
        this.externalCheckReleaseFollowsRecord(BELOW_FIXTURE_ROOT, "0_1_9");

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(BELOW_FIXTURE_ROOT, true);
    }

    /// The newest tag ITSELF MUST be refused: equality is not "follows". The
    /// fail-safe boundary, and the one case `SnapshotAlreadyFrozen` also
    /// refuses — both must hold, so neither is load bearing alone and this one
    /// holds against a record root whose directories are not where a freeze
    /// would look for them.
    function testCheckReleaseFollowsRecordRefusesTheNewestTagItself() external {
        writeFixture(string.concat(EQUAL_FIXTURE_ROOT, "/0_2_0/", FIXTURE_CONTRACT, ".sol"));

        vm.expectRevert(abi.encodeWithSelector(NonMonotonicRelease.selector, "0_2_0", "0_2_0"));
        this.externalCheckReleaseFollowsRecord(EQUAL_FIXTURE_ROOT, "0_2_0");

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(EQUAL_FIXTURE_ROOT, true);
    }

    /// A tag that strictly follows the newest release MUST be accepted,
    /// whichever component moved — a guard that refused an ordinary release
    /// would stop every release this repo cuts.
    ///
    /// The last pair is the one a text comparison gets wrong: `0_10_0` follows
    /// `0_9_0` as a release and precedes it as a string.
    function testCheckReleaseFollowsRecordAcceptsAnyStrictlyGreaterTag() external {
        string[3] memory records = ["0_1_6", "0_9_9", "0_9_0"];
        string[3] memory tags = ["0_1_7", "1_0_0", "0_10_0"];

        for (uint256 i = 0; i < records.length; i++) {
            writeFixture(string.concat(GREATER_FIXTURE_ROOT, "/", records[i], "/", FIXTURE_CONTRACT, ".sol"));

            this.externalCheckReleaseFollowsRecord(GREATER_FIXTURE_ROOT, tags[i]);

            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.removeDir(GREATER_FIXTURE_ROOT, true);
        }
    }

    /// Over EVERY tag, against a record on disk, the guard MUST accept exactly
    /// the tags that strictly follow the newest release and refuse every other
    /// one, naming both tags when it does.
    ///
    /// The record is asserted to be the fixture on every case rather than
    /// assumed: the whole answer is relative to the newest release, so a
    /// fixture that has quietly grown a release is a test that has quietly
    /// changed what it asks.
    /// @param major The candidate tag's major component.
    /// @param minor The candidate tag's minor component.
    /// @param patch The candidate tag's patch component.
    function testCheckReleaseFollowsRecordAcceptsExactlyTheStrictlyGreater(uint8 major, uint8 minor, uint8 patch)
        external
    {
        assertEq(LibRainDeploySnapshot.newestFrozenTag(vm, FROZEN_FIXTURE_ROOT), FROZEN_FIXTURE_NEWEST);

        string memory tag = tagOf(major, minor, patch);
        bool follows = major != 1 ? major > 1 : (minor != 1 ? minor > 1 : patch > 1);

        if (!follows) {
            vm.expectRevert(abi.encodeWithSelector(NonMonotonicRelease.selector, tag, FROZEN_FIXTURE_NEWEST));
        }
        this.externalCheckReleaseFollowsRecord(FROZEN_FIXTURE_ROOT, tag);
    }
}
