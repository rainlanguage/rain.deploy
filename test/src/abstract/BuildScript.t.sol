// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployConfig} from "../../../src/lib/LibRainDeployConfig.sol";
import {LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {BuildScriptHarness} from "../../concrete/BuildScriptHarness.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";

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
    /// Where the `run()` fixture's record is built.
    string constant RUN_FIXTURE_ROOT = "test/generated-buildscript-run";

    /// The root whose declared paths are read.
    string constant RUN_DECLARED_FIXTURE_ROOT = "test/generated-buildscript-run-declared";

    /// Where the freeze fixture's record is built.
    string constant CUT_FIXTURE_ROOT = "test/generated-buildscript-cut";

    /// Where the lib-ordering fixture's record is built.
    string constant LIBS_FIXTURE_ROOT = "test/generated-buildscript-libs";

    /// Where the `run()` config fixture's record is built.
    string constant RUN_CONFIG_FIXTURE_ROOT = "test/generated-buildscript-run-config";

    /// Where the `cutRelease()` config fixture's record is built. Its own root,
    /// like every other fixture here: forge runs the tests in a contract in
    /// parallel, so a root two of them share is one deleting the tree the other
    /// is midway through reading.
    string constant CUT_CONFIG_FIXTURE_ROOT = "test/generated-buildscript-cut-config";

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

    /// A harness over a cleared record and a fresh lib dir for `regenerateLibs` to write into.
    /// @param root The fixture record root.
    function newHarness(string memory root) internal returns (BuildScriptHarness) {
        resetFixture(root);
        BuildScriptHarness harness = new BuildScriptHarness(root);
        string memory libDir = harness.externalLibDir();
        resetFixture(libDir);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(libDir, true);
        return harness;
    }

    /// PROPERTY: `run()` regenerates everything and freezes NOTHING.
    ///
    /// This is the entry point CI calls on every push. A `run()` that cut a
    /// release would freeze whatever a branch happened to compile under the
    /// repo's current tag, and that tag can then never be cut again for real.
    function testRunRegeneratesAndFreezesNothing() external {
        BuildScriptHarness harness = newHarness(RUN_FIXTURE_ROOT);
        harness.seedConfig();
        harness.run();

        // Read while the fixture is still there, asserted once it is gone.
        string memory rolling = vm.readFile(harness.rollingPath());
        string memory released = vm.readFile(harness.releasedLibPath());
        bool aggregateExists = vm.exists(harness.aggregatePath());
        string[] memory record = LibRainDeploySnapshot.frozenSnapshotPaths(vm, RUN_FIXTURE_ROOT);
        bool frozenExists = vm.exists(harness.frozenPath());

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(RUN_FIXTURE_ROOT, true);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(harness.externalLibDir(), true);

        assertTrue(vm.contains(rolling, vm.toString(keccak256(type(MockDeployableV2).runtimeCode))));
        assertTrue(vm.contains(released, "new DeploySuite[](0)"));
        assertTrue(aggregateExists);
        assertEq(record.length, 0);
        assertFalse(frozenExists);
    }

    /// PROPERTY: `run()` declares the rolling snapshot its hook writes, the
    /// contract's released-suites lib and the aggregate.
    function testRunDeclaresTheRollingSnapshotAndTheReleasedLibs() external {
        BuildScriptHarness harness = new BuildScriptHarness(RUN_DECLARED_FIXTURE_ROOT);
        string[] memory paths = harness.externalGeneratedPaths();

        assertEq(paths.length, 5);
        assertEq(paths[0], harness.rollingPath());
        assertEq(paths[0], "test/generated-buildscript-run-declared/candidate/MockDeployableV2.sol");
        assertEq(
            paths[1], "fixture-lib/buildscript-harness/generated-buildscript-run-declared/LibMockDeployableV2Released.sol"
        );
        assertEq(paths[2], "fixture-lib/buildscript-harness/generated-buildscript-run-declared/LibReleasedSuites.sol");
        assertEq(paths[3], "foundry.toml");
        assertEq(paths[4], ".env.example");
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
        BuildScriptHarness harness = newHarness(CUT_FIXTURE_ROOT);
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
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(harness.externalLibDir(), true);

        assertTrue(frozenExists);
        assertEq(frozen, rolling);
        assertNotEq(frozen, stale);
        assertTrue(vm.contains(frozen, vm.toString(keccak256(type(MockDeployableV2).runtimeCode))));
        assertEq(record.length, 1);
    }

    /// PROPERTY: `cutRelease()` regenerates the libs AFTER the freeze, so a lib
    /// emitted from the record holds the release being cut.
    ///
    /// Libs written before the freeze describe the record as it was one release
    /// ago, and the release publishes a declaration that omits itself — which
    /// every check downstream then reads as a release nobody ever made.
    function testCutReleaseRegeneratesLibsFromTheRecordJustCut() external {
        BuildScriptHarness harness = newHarness(LIBS_FIXTURE_ROOT);
        harness.cutRelease();

        // Read while the fixture is still there, asserted once it is gone.
        string memory released = vm.readFile(harness.releasedLibPath());

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(LIBS_FIXTURE_ROOT, true);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(harness.externalLibDir(), true);

        assertTrue(vm.contains(released, "new DeploySuite[](1)"));
        assertTrue(
            vm.contains(
                released, string.concat("suite: \"harness-candidate@", LibRainDeploySnapshot.deployTag(vm), "\"")
            )
        );
    }

    function testRunStagesTheNetworkConfig() external {
        BuildScriptHarness harness = newHarness(RUN_CONFIG_FIXTURE_ROOT);
        harness.seedConfig();
        harness.run();

        // Read while the fixture is still there, asserted once it is gone.
        string memory stagedConfig = vm.readFile(harness.externalStagedConfigPath());
        string memory stagedEnvExample = vm.readFile(harness.externalStagedEnvExamplePath());
        string memory config = vm.readFile(harness.externalConfigPath());
        string memory envExample = vm.readFile(harness.externalEnvExamplePath());

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(RUN_CONFIG_FIXTURE_ROOT, true);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(harness.externalLibDir(), true);

        assertEq(
            stagedConfig,
            string.concat(
                "# hand written\n",
                "# rain-deploy:generated:rpc_endpoints:begin\n",
                LibRainDeployConfig.rpcEndpointsSection(vm, LibRainDeploy.supportedNetworkConfigs()),
                "# rain-deploy:generated:rpc_endpoints:end\n",
                "# rain-deploy:generated:etherscan:begin\n",
                LibRainDeployConfig.etherscanSection(vm, LibRainDeploy.supportedNetworkConfigs()),
                "# rain-deploy:generated:etherscan:end\n"
            )
        );
        assertEq(
            stagedEnvExample,
            string.concat(
                "# hand written\n",
                "# rain-deploy:generated:env:begin\n",
                LibRainDeployConfig.envExampleSection(vm, LibRainDeploy.supportedNetworkConfigs()),
                "# rain-deploy:generated:env:end\n"
            )
        );
        assertEq(config, harness.configSeed());
        assertEq(envExample, harness.envExampleSeed());
    }

    /// PROPERTY: `cutRelease()` stages nothing and leaves the config exactly as
    /// it found it.
    ///
    /// The config is not part of a release record. A `cutRelease()` that
    /// rewrote it would put a config change inside the one operation that can
    /// never be repeated, where `run()` is the entry point every push already
    /// runs and the only one `Git is clean` currency checks.
    ///
    /// The staging directory being ABSENT is what says so now: a staged file
    /// left behind by a release is one the next install puts in place,
    /// which is the config change happening anyway, one step later.
    function testCutReleaseLeavesTheConfigAlone() external {
        BuildScriptHarness harness = newHarness(CUT_CONFIG_FIXTURE_ROOT);
        harness.seedConfig();
        harness.cutRelease();

        // Read while the fixture is still there, asserted once it is gone.
        string memory config = vm.readFile(harness.externalConfigPath());
        string memory envExample = vm.readFile(harness.externalEnvExamplePath());
        bool stagedAnything = vm.exists(harness.externalStagedDir());

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(CUT_CONFIG_FIXTURE_ROOT, true);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(harness.externalLibDir(), true);

        assertEq(config, harness.configSeed());
        assertEq(envExample, harness.envExampleSeed());
        assertFalse(stagedAnything);
    }

    /// PROPERTY: a repo that overrides nothing freezes into its OWN record.
    ///
    /// The root is overridable only so a release can be cut somewhere a test
    /// may leave one. The default is the tree `RegistryDeploySuites` reads its
    /// releases from, and a default pointing anywhere else writes releases
    /// nothing enumerates.
    function testRecordRootDefaultsToTheRepoRecord() external {
        BuildScriptHarness harness = new BuildScriptHarness("");
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

    /// PROPERTY: `run()` calls every generator the base declares, and holds
    /// nothing else.
    ///
    /// THIS ASSERTION IS THE SPECIFICATION of the entry point CI calls on every
    /// push: it regenerates everything this repo generates. A generator nothing
    /// calls is one that no push ever runs — its output drifts from its inputs
    /// until a release cuts the drift into the append-only record, which is the
    /// one place it can never be fixed.
    ///
    /// A generator is an `internal` function that can write, whether or not it
    /// is a hook. `regenerateConfig` is deliberately NOT a hook — the roster it
    /// emits from is this package's own, and a repo able to override the
    /// emission would deploy to and verify fewer chains with nothing red — and
    /// a generator the base holds itself is as capable of being wired to
    /// nothing as one a deriving repo implements.
    ///
    /// They are enumerated from the base's own declarations rather than named
    /// here, because naming them is the failure: a fourth generator added
    /// beside the three that exist today is wired by the same edit that adds it
    /// or by nobody at all, and a test that lists today's three says nothing
    /// either way.
    ///
    /// `run()` holding nothing but those calls and one read each of its declaration and its checked generated
    /// contracts is the other half. Every
    /// assertion here is about the set of declarations `run()` calls, and a set
    /// says nothing about a statement that is not a call — a guard, an early
    /// return, an inlined generator — which is exactly where a regeneration
    /// nothing declares would land.
    ///
    /// Order is not asserted here and cannot be: declaration order is not call
    /// order. The order a release depends on — the libs regenerated after the
    /// freeze — is pinned by `testCutReleaseRegeneratesLibsFromTheRecordJustCut`.
    ///
    /// A function that only reads is not `run()`'s to call: `recordRoot()`,
    /// `configRoot()` and `snapshotContractNames()` answer questions for
    /// whoever asks one, and `run()` asks none of them. They are held to being
    /// called by something in `testEveryHookIsReachedFromAnEntryPoint` instead.
    function testRunCallsEveryGenerator() external view {
        string memory json = baseArtifact();
        string[] memory members = functionPaths(json);
        int256[] memory called = statementCallIds(json, namedFunctionPath(json, members, "run"));

        uint256 generators = 0;
        for (uint256 i = 0; i < members.length; i++) {
            if (!isGenerator(json, members[i])) {
                continue;
            }
            generators++;
            assertTrue(
                referencesId(called, declarationId(json, members[i])),
                string.concat("run() does not call the generator ", nodeField(json, members[i], "name"))
            );
        }

        assertTrue(
            referencesId(called, declarationId(json, namedFunctionPath(json, members, "declareGeneratedPaths"))),
            "run() does not declare its generated paths"
        );

        assertGt(generators, 0, "the base declares no generator");
        assertEq(
            called.length, generators + 1, "run() holds a call that is not one of those generators or the declaration"
        );
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

    function baseArtifact() internal view returns (string memory) {
        return vm.readFile(BASE_ARTIFACT);
    }

    /// Walked rather than indexed: the top-level nodes are the pragma, the
    /// imports and then the contract, so an import added or removed moves the
    /// index of everything below.
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

    /// The import is matched to the inheritance by declaration id rather than
    /// by name, so a second contract spelled `BuildScript` in a file the
    /// harness also imports is not a way to point the assertions at one file
    /// while inheriting another. Both ids are read out of the harness's own
    /// artifact, which is one compilation and therefore one id space.
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

    /// Collected from the contract's own members, so a hook added to the base
    /// is in this walk the moment it is declared and before anything calls it.
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

    /// Whether a function is a hook: `internal virtual`, which is the whole of
    /// what a deriving repo can implement and nothing outside the base can
    /// call.
    function isHook(string memory json, string memory path) internal pure returns (bool) {
        return keccak256(bytes(nodeField(json, path, "visibility"))) == keccak256("internal")
            && vm.parseJsonBool(json, string.concat(path, ".virtual"));
    }

    /// Whether a function is a generator: `internal`, and able to write. That
    /// is what makes it something `run()` has to call, and it is independent of
    /// `virtual` — which is about who can change the emission, not about
    /// whether anything runs it.
    function isGenerator(string memory json, string memory path) internal pure returns (bool) {
        return keccak256(bytes(nodeField(json, path, "visibility"))) == keccak256("internal")
            && keccak256(bytes(nodeField(json, path, "stateMutability"))) == keccak256("nonpayable");
    }

    /// Whether a function can be called from outside the contract, which is
    /// what makes it the start of a wiring chain rather than a link in one.
    function isEntryPoint(string memory json, string memory path) internal pure returns (bool) {
        bytes32 visibility = keccak256(bytes(nodeField(json, path, "visibility")));
        return visibility == keccak256("external") || visibility == keccak256("public");
    }

    /// Every statement MUST be a plain call of a function the contract
    /// declares, so a body that does anything else fails here rather than being
    /// counted as a call of nothing.
    function statementCallIds(string memory json, string memory path) internal view returns (int256[] memory) {
        int256[] memory found = new int256[](64);
        uint256 count = 0;
        bool readDeclaration = false;
        bool readGenerated = false;
        for (
            uint256 i = 0;
            vm.keyExistsJson(json, string.concat(path, ".body.statements[", vm.toString(i), "].nodeType"));
            i++
        ) {
            string memory statement = string.concat(path, ".body.statements[", vm.toString(i), "]");
            string memory nodeType = vm.parseJsonString(json, string.concat(statement, ".nodeType"));
            string memory call;
            if (keccak256(bytes(nodeType)) == keccak256("VariableDeclarationStatement")) {
                call = string.concat(statement, ".initialValue");
            } else {
                assertEq(nodeType, "ExpressionStatement", "the entry point holds a statement that is not a call");
                call = string.concat(statement, ".expression");
            }
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
            if (keccak256(bytes(nodeType)) == keccak256("VariableDeclarationStatement")) {
                string memory bound = vm.parseJsonString(json, string.concat(call, ".expression.name"));
                if (keccak256(bytes(bound)) == keccak256("declaration")) {
                    assertFalse(readDeclaration, "the entry point reads its declaration twice");
                    readDeclaration = true;
                    continue;
                }
                assertEq(
                    bound,
                    "checkedGeneratedContracts",
                    "the entry point binds something other than its declaration or its generated contracts"
                );
                assertFalse(readGenerated, "the entry point reads its generated contracts twice");
                readGenerated = true;
                continue;
            }

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

        // A pass that adds nothing has closed the set.
        bool changed = true;
        while (changed) {
            changed = false;
            for (uint256 i = 0; i < members.length; i++) {
                if (!reached[i]) {
                    continue;
                }
                for (uint256 j = 0; j < members.length; j++) {
                    if (!reached[j] && referencesId(references[i], ids[j])) {
                        reached[j] = true;
                        changed = true;
                    }
                }
            }
        }
        return reached;
    }

    /// One query, not a walk: every cheatcode call is handed the whole artifact.
    function referencedIds(string memory json, string memory path) internal view returns (int256[] memory) {
        string memory key = string.concat(path, "..[?(@.nodeType == 'Identifier')].referencedDeclaration");
        if (!vm.keyExistsJson(json, key)) {
            return new int256[](0);
        }
        bytes memory raw = vm.parseJson(json, key);
        // One match decodes as a value, several as an array.
        if (raw.length == 32) {
            int256[] memory one = new int256[](1);
            one[0] = abi.decode(raw, (int256));
            return one;
        }
        return abi.decode(raw, (int256[]));
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
