// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {BuildScriptHarness} from "../../concrete/BuildScriptHarness.sol";

/// What one walk of the AST has found referenced, as declaration ids.
///
/// A memory struct so a recursion into a subtree writes what it finds where the
/// caller can read it: every frame of the walk shares this one accumulator.
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
///
/// What the harness can show is a hook that RAN. A hook nothing calls leaves
/// every marker exactly where a wired base would, so the wiring itself is
/// asserted from the compiler's AST instead, and against the base's own
/// declarations rather than a list of the hooks it holds today.
contract BuildScriptTest is Test {
    /// The contract the fixture snapshots describe.
    string constant FIXTURE_CONTRACT = "Fixture";

    /// Where the `run()` fixture's record is built.
    string constant RUN_FIXTURE_ROOT = "test/generated-buildscript-run";

    /// Where the freeze fixture's record is built.
    string constant CUT_FIXTURE_ROOT = "test/generated-buildscript-cut";

    /// Where the lib-ordering fixture's record is built.
    string constant LIBS_FIXTURE_ROOT = "test/generated-buildscript-libs";

    /// The compiled base, which carries its AST because `foundry.toml` sets
    /// `ast = true`.
    string constant BASE_ARTIFACT = "out/BuildScript.sol/BuildScript.json";

    /// The compiled harness, which is what ties that artifact to a contract
    /// this suite really runs.
    string constant HARNESS_ARTIFACT = "out/BuildScriptHarness.sol/BuildScriptHarness.json";

    /// The file the base's artifact has to be describing.
    string constant BASE_SOURCE = "src/abstract/BuildScript.sol";

    /// The file the harness's artifact has to be describing.
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

    /// PROPERTY: the AST the assertions below read is the base the harness
    /// above inherits, in the file this repo compiles it from.
    ///
    /// Every one of them is a claim about a file named by a hard-coded path,
    /// and an artifact left behind by a moved or renamed source parses exactly
    /// as well as a live one — a hook walk over a dead file finds no unwired
    /// hook and reports that as the property holding.
    ///
    /// The base is abstract, so its own creation code cannot be the anchor the
    /// way `CreditHyperCoreTest` uses one. The harness is concrete and this
    /// file drives it, so the chain runs through it instead: the harness
    /// artifact is the harness this suite compiled, the base it inherits was
    /// imported from `BASE_SOURCE`, and the base artifact describes that same
    /// file.
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

    /// PROPERTY: `run()` calls every hook that regenerates something, and holds
    /// nothing else.
    ///
    /// THIS ASSERTION IS THE SPECIFICATION of the entry point CI calls on every
    /// push: it regenerates everything this repo generates. A hook is what a
    /// deriving repo implements, so a hook nothing calls is a generator that no
    /// push ever runs — its output drifts from its inputs until a release cuts
    /// the drift into the append-only record, which is the one place it can
    /// never be fixed.
    ///
    /// The hooks are enumerated from the base's own declarations rather than
    /// named here, because naming them is the failure: a third hook added
    /// beside the two that exist today is wired by the same edit that adds it
    /// or by nobody at all, and a test that lists today's two says nothing
    /// either way.
    ///
    /// `run()` holding nothing but those calls is the other half. Every
    /// assertion here is about the set of declarations `run()` calls, and a set
    /// says nothing about a statement that is not a call — a guard, an early
    /// return, an inlined generator — which is exactly where a regeneration
    /// that no hook can be overridden to change would land.
    ///
    /// Order is not asserted here and cannot be: declaration order is not call
    /// order, and the order that is observable —
    /// `regenerateSnapshots` before `regenerateLibs` — is already pinned by
    /// `testRunRegeneratesAndFreezesNothing` through the harness's markers.
    ///
    /// A hook that only reads is not `run()`'s to call: `recordRoot()` and
    /// `snapshotContractNames()` answer questions for whoever asks one, and
    /// `run()` asks neither. They are held to being called by something in
    /// `testEveryHookIsReachedFromAnEntryPoint` instead.
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

    /// PROPERTY: every hook the base declares is reached from an entry point.
    ///
    /// The half of the wiring `run()` cannot carry. A hook that only reads is
    /// called where its answer is needed, which for the two that exist today is
    /// `cutRelease()` — but a hook reached from neither entry point is one a
    /// deriving repo is asked to implement and that nothing ever calls, and
    /// that is the same defect whether the hook writes files or answers a
    /// question.
    ///
    /// Reachability, not a direct call: `regenerateSnapshots` reaches `freeze`
    /// as an internal function pointer rather than as a call, and a hook whose
    /// only caller is another hook's default body is wired.
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

    /// The base's artifact JSON.
    /// @return The whole file.
    function baseArtifact() internal view returns (string memory) {
        return vm.readFile(BASE_ARTIFACT);
    }

    /// The JSON path of the source unit's only contract.
    ///
    /// Walked rather than indexed: the top-level nodes are the pragma, the
    /// imports and then the contract, so an import added or removed moves the
    /// index of everything below.
    /// @param json The base's artifact.
    /// @return The path.
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

    /// The path the harness's only base contract was imported from.
    ///
    /// The import is matched to the inheritance by declaration id rather than
    /// by name, so a second contract spelled `BuildScript` in a file the
    /// harness also imports is not a way to point the assertions at one file
    /// while inheriting another. Both ids are read out of the harness's own
    /// artifact, which is one compilation and therefore one id space.
    /// @param json The harness's artifact.
    /// @return The imported file's path.
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

    /// Every function the base declares, as JSON paths.
    ///
    /// Collected from the contract's own members, so a hook added to the base
    /// is in this walk the moment it is declared and before anything calls it.
    /// @param json The base's artifact.
    /// @return One path per function.
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

    /// The path of the one function declared under a name.
    /// @param json The base's artifact.
    /// @param members Every function the base declares.
    /// @param name The function's name.
    /// @return The path.
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

    /// One string field of an AST node.
    /// @param json The base's artifact.
    /// @param path The node's path.
    /// @param name The field to read.
    /// @return The field.
    function nodeField(string memory json, string memory path, string memory name)
        internal
        pure
        returns (string memory)
    {
        return vm.parseJsonString(json, string.concat(path, ".", name));
    }

    /// A declaration's own id, as `int256` because solc numbers its built-ins
    /// negative and both sides of a comparison have to be the same type.
    /// @param json The base's artifact.
    /// @param path The declaration's path.
    /// @return The id.
    function declarationId(string memory json, string memory path) internal pure returns (int256) {
        return vm.parseJsonInt(json, string.concat(path, ".id"));
    }

    /// Whether a function is a hook: `internal virtual`, which is the whole of
    /// what a deriving repo can implement and nothing outside the base can
    /// call.
    /// @param json The base's artifact.
    /// @param path The function's path.
    /// @return Whether it is a hook.
    function isHook(string memory json, string memory path) internal pure returns (bool) {
        return keccak256(bytes(nodeField(json, path, "visibility"))) == keccak256("internal")
            && vm.parseJsonBool(json, string.concat(path, ".virtual"));
    }

    /// Whether a function can write anything, which for a hook is what makes it
    /// a generator rather than an answer to a question.
    /// @param json The base's artifact.
    /// @param path The function's path.
    /// @return Whether it can write.
    function regenerates(string memory json, string memory path) internal pure returns (bool) {
        return keccak256(bytes(nodeField(json, path, "stateMutability"))) == keccak256("nonpayable");
    }

    /// Whether a function can be called from outside the contract, which is
    /// what makes it the start of a wiring chain rather than a link in one.
    /// @param json The base's artifact.
    /// @param path The function's path.
    /// @return Whether it is an entry point.
    function isEntryPoint(string memory json, string memory path) internal pure returns (bool) {
        bytes32 visibility = keccak256(bytes(nodeField(json, path, "visibility")));
        return visibility == keccak256("external") || visibility == keccak256("public");
    }

    /// The declaration each statement of a function body calls.
    ///
    /// Every statement MUST be a plain call of a function the contract
    /// declares, so a body that does anything else fails here rather than being
    /// counted as a call of nothing.
    /// @param json The base's artifact.
    /// @param path The function's path.
    /// @return One id per statement.
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

    /// Which of the base's functions are reached from an entry point, by the
    /// references each one holds.
    /// @param json The base's artifact.
    /// @param members Every function the base declares.
    /// @return One flag per member, in the same order.
    function reachedFromEntryPoints(string memory json, string[] memory members) internal view returns (bool[] memory) {
        int256[] memory ids = new int256[](members.length);
        bool[] memory reached = new bool[](members.length);
        int256[][] memory references = new int256[][](members.length);
        for (uint256 i = 0; i < members.length; i++) {
            ids[i] = declarationId(json, members[i]);
            reached[i] = isEntryPoint(json, members[i]);
            references[i] = referencedIds(json, members[i]);
        }

        // One pass per member: a pass that changes nothing has closed the set,
        // and a pass that changes something adds at least one member to it.
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

    /// Every declaration a function references anywhere inside itself.
    /// @param json The base's artifact.
    /// @param path The function's path.
    /// @return One id per reference.
    function referencedIds(string memory json, string memory path) internal view returns (int256[] memory) {
        AstReferences memory references = AstReferences(new int256[](256), 0);
        collectReferences(json, path, references);

        int256[] memory ids = new int256[](references.count);
        for (uint256 i = 0; i < references.count; i++) {
            ids[i] = references.ids[i];
        }
        return ids;
    }

    /// Collects every declaration the subtree at `path` references.
    ///
    /// Generic over node shapes rather than a walk of the expressions the base
    /// happens to hold today: a hook handed to a library as a function pointer
    /// is a reference several levels inside an argument list, and a call moved
    /// inside a block is one level inside a statement. Neither is a hook that
    /// nothing wires, so neither may read as one here.
    /// @param json The base's artifact.
    /// @param path The subtree's root.
    /// @param references The accumulator every recursion shares.
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

    /// Whether a set of references holds one id.
    /// @param ids The references.
    /// @param id The id.
    /// @return Whether it is there.
    function referencesId(int256[] memory ids, int256 id) internal pure returns (bool) {
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] == id) {
                return true;
            }
        }
        return false;
    }
}
