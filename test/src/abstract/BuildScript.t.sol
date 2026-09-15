// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {BuildScriptHarness} from "../../concrete/BuildScriptHarness.sol";

struct AstReferences {
    int256[] ids;
    uint256 count;
}

/// @title BuildScriptTest
/// @notice The split between the two entry points every deploy repo inherits.
///
/// The contract this repo compiles is not what these run against: a
/// `cutRelease()` here cuts THIS repo's tag, and `src/generated/` is
/// append-only, so each test drives a harness over a fixture record of its own.
/// A shared root would have the second test refused as a re-cut of the first.
contract BuildScriptTest is Test {
    /// The contract the fixture snapshots describe.
    string constant FIXTURE_CONTRACT = "Fixture";

    /// Where the `run()` fixture's record is built.
    string constant RUN_FIXTURE_ROOT = "test/generated-buildscript-run";

    /// Where the freeze fixture's record is built.
    string constant CUT_FIXTURE_ROOT = "test/generated-buildscript-cut";

    /// Where the lib-ordering fixture's record is built.
    string constant LIBS_FIXTURE_ROOT = "test/generated-buildscript-libs";

    /// Carries its AST because `foundry.toml` sets `ast = true`.
    string constant BASE_ARTIFACT = "out/BuildScript.sol/BuildScript.json";

    string constant HARNESS_ARTIFACT = "out/BuildScriptHarness.sol/BuildScriptHarness.json";

    string constant BASE_SOURCE = "src/abstract/BuildScript.sol";

    string constant HARNESS_SOURCE = "test/concrete/BuildScriptHarness.sol";

    /// Clears a fixture record an earlier failure left behind.
    ///
    /// A cheatcode write is not undone by a revert, so a failing test leaves
    /// its markers on disk and the next run reads THOSE — an assertion about
    /// the previous run rather than about this one.
    /// @param root The fixture record root to clear.
    function resetFixture(string memory root) internal {
        if (vm.exists(root)) {
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.removeDir(root, true);
        }
    }

    /// PROPERTY: `run()` regenerates everything and freezes NOTHING.
    ///
    /// This is the entry point CI calls on every push. A `run()` that cut a
    /// release would freeze whatever a branch happened to compile under the
    /// repo's current tag, and that tag can then never be cut again for real.
    ///
    /// The lib marker also carries the order: the libs are written after the
    /// snapshots, from a record that holds no release.
    function testRunRegeneratesAndFreezesNothing() external {
        resetFixture(RUN_FIXTURE_ROOT);
        BuildScriptHarness harness = new BuildScriptHarness(RUN_FIXTURE_ROOT, FIXTURE_CONTRACT);
        harness.run();

        // Read while the fixture is still there, asserted once it is gone.
        string memory rolling = vm.readFile(harness.rollingPath());
        string memory libs = vm.readFile(harness.libsPath());
        string[] memory record = LibRainDeploySnapshot.frozenSnapshotPaths(vm, RUN_FIXTURE_ROOT);
        bool frozenExists = vm.exists(harness.frozenPath());

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(RUN_FIXTURE_ROOT, true);

        assertEq(rolling, harness.regeneratedSnapshot());
        assertEq(libs, harness.libsMarker(0, true));
        assertEq(record.length, 0);
        assertFalse(frozenExists);
    }

    /// PROPERTY: `cutRelease()` freezes the snapshot its OWN regeneration
    /// wrote, not the one that was on disk when it was called.
    ///
    /// The regeneration reaches `freeze` as an internal function pointer taken
    /// in the base, so what a release records is what the DERIVED hook writes.
    /// A pointer that resolved anywhere else freezes the stale bytes, and a
    /// release recording bytes its own deploy did not produce is silent
    /// afterwards — the immutability guard only fires on a re-cut.
    function testCutReleaseFreezesTheRegeneratedSnapshot() external {
        resetFixture(CUT_FIXTURE_ROOT);
        BuildScriptHarness harness = new BuildScriptHarness(CUT_FIXTURE_ROOT, FIXTURE_CONTRACT);
        string memory stale = harness.marker("stale");
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(LibRainDeploySnapshot.dirForSnapshot(CUT_FIXTURE_ROOT, LibRainDeploySnapshot.CANDIDATE), true);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(harness.rollingPath(), stale);

        harness.cutRelease();

        // Read while the fixture is still there, asserted once it is gone.
        bool frozenExists = vm.exists(harness.frozenPath());
        string memory frozen = frozenExists ? vm.readFile(harness.frozenPath()) : "";
        string memory rolling = vm.readFile(harness.rollingPath());
        string[] memory record = LibRainDeploySnapshot.frozenSnapshotPaths(vm, CUT_FIXTURE_ROOT);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(CUT_FIXTURE_ROOT, true);

        assertTrue(frozenExists);
        assertEq(frozen, harness.regeneratedSnapshot());
        assertNotEq(frozen, stale);
        assertEq(rolling, harness.regeneratedSnapshot());
        assertEq(record.length, 1);
    }

    /// PROPERTY: `cutRelease()` regenerates the libs AFTER the freeze, so a lib
    /// emitted from the record holds the release being cut.
    ///
    /// Libs written before the freeze describe the record as it was one release
    /// ago, and the release publishes a declaration that omits itself — which
    /// every check downstream then reads as a release nobody ever made.
    function testCutReleaseRegeneratesLibsFromTheRecordJustCut() external {
        resetFixture(LIBS_FIXTURE_ROOT);
        BuildScriptHarness harness = new BuildScriptHarness(LIBS_FIXTURE_ROOT, FIXTURE_CONTRACT);
        harness.cutRelease();

        // Read while the fixture is still there, asserted once it is gone.
        string memory libs = vm.readFile(harness.libsPath());

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(LIBS_FIXTURE_ROOT, true);

        assertEq(libs, harness.libsMarker(1, true));
    }

    /// PROPERTY: a repo that overrides nothing freezes into its OWN record.
    ///
    /// The root is overridable only so a release can be cut somewhere a test
    /// may leave one. The default is the tree `RegistryDeploySuites` reads its
    /// releases from, and a default pointing anywhere else writes releases
    /// nothing enumerates.
    function testRecordRootDefaultsToTheRepoRecord() external {
        BuildScriptHarness harness = new BuildScriptHarness("", FIXTURE_CONTRACT);
        assertEq(harness.externalRecordRoot(), LibRainDeploySnapshot.LIB_FS_ROOT);
    }

    function testTheAstIsTheBaseTheHarnessInherits() external view {
        assertEq(
            keccak256(vm.getCode(string.concat(HARNESS_SOURCE, ":BuildScriptHarness"))),
            keccak256(type(BuildScriptHarness).creationCode),
            "the harness artifact is not the harness this suite compiles"
        );

        string memory harness = vm.readFile(HARNESS_ARTIFACT);
        assertEq(importPathOfBase(harness), BASE_SOURCE, "the harness inherits its base from somewhere else");
        assertEq(
            vm.parseJsonString(baseArtifact(), "$.ast.absolutePath"),
            BASE_SOURCE,
            "the base artifact describes another file"
        );
    }

    function testRunCallsEveryHookThatRegenerates() external view {
        string memory json = baseArtifact();
        string[] memory members = functionPaths(json);
        int256[] memory called = statementCallIds(json, namedFunctionPath(json, members, "run"));

        uint256 hooks = 0;
        for (uint256 i = 0; i < members.length; i++) {
            if (!isHook(json, members[i]) || !regenerates(json, members[i])) {
                continue;
            }
            hooks++;
            assertTrue(
                referencesId(called, declarationId(json, members[i])),
                string.concat("run() does not call the hook ", nodeField(json, members[i], "name"))
            );
        }

        assertGt(hooks, 0, "the base declares no hook that regenerates anything");
        assertEq(called.length, hooks, "run() holds a call that is not one of those hooks");
    }

    function testEveryHookIsReachedFromAnEntryPoint() external view {
        string memory json = baseArtifact();
        string[] memory members = functionPaths(json);
        bool[] memory reached = reachedFromEntryPoints(json, members);

        uint256 hooks = 0;
        for (uint256 i = 0; i < members.length; i++) {
            if (!isHook(json, members[i])) {
                continue;
            }
            hooks++;
            assertTrue(reached[i], string.concat("nothing reaches the hook ", nodeField(json, members[i], "name")));
        }

        assertGt(hooks, 0, "the base declares no hooks");
    }

    function baseArtifact() internal view returns (string memory) {
        return vm.readFile(BASE_ARTIFACT);
    }

    function baseContractPath(string memory json) internal view returns (string memory) {
        string memory found = "";
        uint256 count = 0;
        for (uint256 i = 0; vm.keyExistsJson(json, string.concat("$.ast.nodes[", vm.toString(i), "].nodeType")); i++) {
            string memory node = string.concat("$.ast.nodes[", vm.toString(i), "]");
            if (
                keccak256(bytes(vm.parseJsonString(json, string.concat(node, ".nodeType"))))
                    == keccak256("ContractDefinition")
            ) {
                found = node;
                count++;
            }
        }

        assertEq(count, 1, "the base source does not declare exactly one contract");
        assertEq(vm.parseJsonString(json, string.concat(found, ".name")), "BuildScript", "the contract is not the base");
        return found;
    }

    function importPathOfBase(string memory json) internal view returns (string memory) {
        string memory contractPath = "";
        for (uint256 i = 0; vm.keyExistsJson(json, string.concat("$.ast.nodes[", vm.toString(i), "].nodeType")); i++) {
            string memory node = string.concat("$.ast.nodes[", vm.toString(i), "]");
            if (
                keccak256(bytes(vm.parseJsonString(json, string.concat(node, ".nodeType"))))
                    == keccak256("ContractDefinition")
            ) {
                contractPath = node;
            }
        }
        assertFalse(
            vm.keyExistsJson(json, string.concat(contractPath, ".baseContracts[1]")),
            "the harness inherits more than the base"
        );
        int256 base =
            vm.parseJsonInt(json, string.concat(contractPath, ".baseContracts[0].baseName.referencedDeclaration"));

        for (uint256 i = 0; vm.keyExistsJson(json, string.concat("$.ast.nodes[", vm.toString(i), "].nodeType")); i++) {
            string memory node = string.concat("$.ast.nodes[", vm.toString(i), "]");
            for (
                uint256 j = 0;
                vm.keyExistsJson(json, string.concat(node, ".symbolAliases[", vm.toString(j), "]"));
                j++
            ) {
                string memory symbolAlias = string.concat(node, ".symbolAliases[", vm.toString(j), "]");
                if (vm.parseJsonInt(json, string.concat(symbolAlias, ".foreign.referencedDeclaration")) == base) {
                    return vm.parseJsonString(json, string.concat(node, ".absolutePath"));
                }
            }
        }
        revert("the harness imports no base");
    }

    function functionPaths(string memory json) internal view returns (string[] memory) {
        string memory contractPath = baseContractPath(json);
        string[] memory found = new string[](64);
        uint256 count = 0;
        for (
            uint256 i = 0;
            vm.keyExistsJson(json, string.concat(contractPath, ".nodes[", vm.toString(i), "].nodeType"));
            i++
        ) {
            string memory node = string.concat(contractPath, ".nodes[", vm.toString(i), "]");
            if (
                keccak256(bytes(vm.parseJsonString(json, string.concat(node, ".nodeType"))))
                    == keccak256("FunctionDefinition")
            ) {
                found[count] = node;
                count++;
            }
        }

        string[] memory paths = new string[](count);
        for (uint256 j = 0; j < count; j++) {
            paths[j] = found[j];
        }
        return paths;
    }

    function namedFunctionPath(string memory json, string[] memory members, string memory name)
        internal
        pure
        returns (string memory)
    {
        string memory found = "";
        uint256 count = 0;
        for (uint256 i = 0; i < members.length; i++) {
            if (keccak256(bytes(nodeField(json, members[i], "name"))) == keccak256(bytes(name))) {
                found = members[i];
                count++;
            }
        }

        assertEq(count, 1, string.concat("the base does not declare exactly one ", name));
        return found;
    }

    function nodeField(string memory json, string memory path, string memory name)
        internal
        pure
        returns (string memory)
    {
        return vm.parseJsonString(json, string.concat(path, ".", name));
    }

    /// `int256` because solc numbers its built-ins negative.
    function declarationId(string memory json, string memory path) internal pure returns (int256) {
        return vm.parseJsonInt(json, string.concat(path, ".id"));
    }

    function isHook(string memory json, string memory path) internal pure returns (bool) {
        return keccak256(bytes(nodeField(json, path, "visibility"))) == keccak256("internal")
            && vm.parseJsonBool(json, string.concat(path, ".virtual"));
    }

    function regenerates(string memory json, string memory path) internal pure returns (bool) {
        return keccak256(bytes(nodeField(json, path, "stateMutability"))) == keccak256("nonpayable");
    }

    function isEntryPoint(string memory json, string memory path) internal pure returns (bool) {
        bytes32 visibility = keccak256(bytes(nodeField(json, path, "visibility")));
        return visibility == keccak256("external") || visibility == keccak256("public");
    }

    function statementCallIds(string memory json, string memory path) internal view returns (int256[] memory) {
        int256[] memory found = new int256[](64);
        uint256 count = 0;
        for (
            uint256 i = 0;
            vm.keyExistsJson(json, string.concat(path, ".body.statements[", vm.toString(i), "].nodeType"));
            i++
        ) {
            string memory statement = string.concat(path, ".body.statements[", vm.toString(i), "]");
            assertEq(
                vm.parseJsonString(json, string.concat(statement, ".nodeType")),
                "ExpressionStatement",
                "the entry point holds a statement that is not a call"
            );

            string memory call = string.concat(statement, ".expression");
            assertEq(
                vm.parseJsonString(json, string.concat(call, ".nodeType")),
                "FunctionCall",
                "the entry point holds an expression that is not a call"
            );
            assertEq(
                vm.parseJsonString(json, string.concat(call, ".expression.nodeType")),
                "Identifier",
                "the entry point calls something other than a function of its own"
            );

            found[count] = vm.parseJsonInt(json, string.concat(call, ".expression.referencedDeclaration"));
            count++;
        }

        int256[] memory ids = new int256[](count);
        for (uint256 j = 0; j < count; j++) {
            ids[j] = found[j];
        }
        return ids;
    }

    function reachedFromEntryPoints(string memory json, string[] memory members) internal view returns (bool[] memory) {
        int256[] memory ids = new int256[](members.length);
        bool[] memory reached = new bool[](members.length);
        int256[][] memory references = new int256[][](members.length);
        for (uint256 i = 0; i < members.length; i++) {
            ids[i] = declarationId(json, members[i]);
            reached[i] = isEntryPoint(json, members[i]);
            references[i] = referencedIds(json, members[i]);
        }

        for (uint256 pass = 0; pass < members.length; pass++) {
            for (uint256 i = 0; i < members.length; i++) {
                if (!reached[i]) {
                    continue;
                }
                for (uint256 j = 0; j < members.length; j++) {
                    reached[j] = reached[j] || referencesId(references[i], ids[j]);
                }
            }
        }
        return reached;
    }

    function referencedIds(string memory json, string memory path) internal view returns (int256[] memory) {
        AstReferences memory references = AstReferences(new int256[](256), 0);
        collectReferences(json, path, references);

        int256[] memory ids = new int256[](references.count);
        for (uint256 i = 0; i < references.count; i++) {
            ids[i] = references.ids[i];
        }
        return ids;
    }

    function collectReferences(string memory json, string memory path, AstReferences memory references) internal view {
        string memory nodeType = string.concat(path, ".nodeType");
        if (!vm.keyExistsJson(json, nodeType)) {
            return;
        }
        if (keccak256(bytes(vm.parseJsonString(json, nodeType))) == keccak256("Identifier")) {
            references.ids[references.count] = vm.parseJsonInt(json, string.concat(path, ".referencedDeclaration"));
            references.count++;
        }

        string[] memory keys = vm.parseJsonKeys(json, path);
        for (uint256 i = 0; i < keys.length; i++) {
            string memory child = string.concat(path, ".", keys[i]);
            collectReferences(json, child, references);
            for (uint256 j = 0; vm.keyExistsJson(json, string.concat(child, "[", vm.toString(j), "].nodeType")); j++) {
                collectReferences(json, string.concat(child, "[", vm.toString(j), "]"), references);
            }
        }
    }

    function referencesId(int256[] memory ids, int256 id) internal pure returns (bool) {
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] == id) {
                return true;
            }
        }
        return false;
    }
}
