// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {
    BuildHookMissing,
    EmptyRoster,
    GeneratedBlockMalformed,
    LibRainDeployConfig,
    NoChainId
} from "../../../src/lib/LibRainDeployConfig.sol";

/// @title LibRainDeployConfigTest
/// @notice The generator that replaces the comparison. What a comparison
/// asserted about two lists, this has to EMIT, so the expectations here are
/// string literals rather than anything the library builds — an expectation
/// concatenated the way the source concatenates it would pass for any spelling
/// the source happens to use, including a broken one.
///
/// The fixture roster is `alpha`/`beta`/`gamma`, which no real network is
/// named, so nothing here can pass against this repo's own config by accident.
contract LibRainDeployConfigTest is Test {
    /// Where the `writeNetworkConfig` fixture is built. Under `test/`, which is
    /// the root the config grants read-write; `foundry.toml` itself is written
    /// only by `script/Build.sol`, never from here.
    ///
    /// One root per test, because forge runs the tests in a contract in
    /// parallel: a shared root is one test deleting the tree another is
    /// midway through reading.
    string constant CONFIG_FIXTURE_ROOT = "test/generated-config-write";

    /// Where the `writeEnvExample` fixture is built.
    string constant ENV_FIXTURE_ROOT = "test/generated-config-env";

    /// Where the fixture carrying no markers is built.
    string constant NO_MARKERS_FIXTURE_ROOT = "test/generated-config-no-markers";

    /// Where the `writeStagedConfig` fixture is built.
    string constant STAGED_FIXTURE_ROOT = "test/generated-config-staged";

    /// Where the fixture for a repo with no build hook is built.
    string constant NO_HOOK_FIXTURE_ROOT = "test/generated-config-no-hook";

    /// A roster of three, one of which carries an explorer url, so both
    /// `[etherscan]` entry shapes are emitted by one call.
    /// @return The fixture roster.
    function fixtureRoster() internal pure returns (SupportedNetwork[] memory) {
        SupportedNetwork[] memory networks = new SupportedNetwork[](3);
        networks[0] =
            SupportedNetwork({name: "alpha", chainId: 11, explorerUrl: "", defaultRpcUrl: "https://alpha.example"});
        networks[1] = SupportedNetwork({
            name: "beta", chainId: 22, explorerUrl: "https://beta.example/api", defaultRpcUrl: "https://beta.example"
        });
        networks[2] =
            SupportedNetwork({name: "gamma", chainId: 33, explorerUrl: "", defaultRpcUrl: "https://gamma.example"});
        return networks;
    }

    /// A roster of one, for the cases where three would say nothing extra.
    /// @param name The network name.
    /// @param chainId The chain id it declares.
    /// @return The roster.
    function singleRoster(string memory name, uint256 chainId) internal pure returns (SupportedNetwork[] memory) {
        SupportedNetwork[] memory networks = new SupportedNetwork[](1);
        networks[0] = SupportedNetwork({name: name, chainId: chainId, explorerUrl: "", defaultRpcUrl: "https://one"});
        return networks;
    }

    /// Clears a fixture tree an earlier failure left behind. A cheatcode write
    /// is not undone by a revert, so a failing test leaves its files on disk
    /// and the next run reads THOSE.
    /// @param root The fixture root to clear.
    function resetFixtures(string memory root) internal {
        if (vm.exists(root)) {
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.removeDir(root, true);
        }
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(root, true);
    }

    /// Writes a fixture file, creating the root above it.
    /// @param root The fixture root the file sits under.
    /// @param path The file to write.
    /// @param content What to write there.
    function writeFixture(string memory root, string memory path, string memory content) internal {
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(root, true);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(path, content);
    }

    /// External wrappers, so `vm.expectRevert` sees a call at a lower depth
    /// than its own. An internal library call reverts at this contract's depth
    /// and the cheatcode refuses it.
    /// @param networks The roster to render.
    /// @return The section.
    function externalRpcEndpointsSection(SupportedNetwork[] memory networks) external pure returns (string memory) {
        return LibRainDeployConfig.rpcEndpointsSection(vm, networks);
    }

    /// @param networks The roster to render.
    /// @return The section.
    function externalEtherscanSection(SupportedNetwork[] memory networks) external pure returns (string memory) {
        return LibRainDeployConfig.etherscanSection(vm, networks);
    }

    /// @param networks The roster to render.
    /// @return The block.
    function externalEnvExampleSection(SupportedNetwork[] memory networks) external pure returns (string memory) {
        return LibRainDeployConfig.envExampleSection(vm, networks);
    }

    /// @param path The file the content came from, for the error only.
    /// @param content The whole file.
    /// @param name The block name.
    /// @param body The block's new content.
    /// @return The whole file, with the block replaced.
    function externalSpliceBlock(string memory path, string memory content, string memory name, string memory body)
        external
        pure
        returns (string memory)
    {
        return LibRainDeployConfig.spliceBlock(vm, path, content, name, body);
    }

    /// @param path The config to read.
    /// @param staged Where to write the spliced result.
    /// @param networks The roster.
    function externalWriteNetworkConfig(string memory path, string memory staged, SupportedNetwork[] memory networks)
        external
    {
        LibRainDeployConfig.writeNetworkConfig(vm, path, staged, networks);
    }

    /// @param root The project root to stage under.
    /// @param hookPath The build hook that would install what is staged.
    /// @param networks The roster.
    function externalWriteStagedConfig(string memory root, string memory hookPath, SupportedNetwork[] memory networks)
        external
    {
        LibRainDeployConfig.writeStagedConfig(vm, root, hookPath, networks);
    }

    /// PROPERTY: the `[rpc_endpoints]` section is the roster, in roster order,
    /// each alias interpolating its own `<NAME>_RPC_URL`.
    function testRpcEndpointsSectionIsTheRoster() external pure {
        assertEq(
            LibRainDeployConfig.rpcEndpointsSection(vm, fixtureRoster()),
            "[rpc_endpoints]\n" 'alpha = "${ALPHA_RPC_URL}"\n' 'beta = "${BETA_RPC_URL}"\n'
            'gamma = "${GAMMA_RPC_URL}"\n'
        );
    }

    /// PROPERTY: the `[etherscan]` section states `chain` on every entry, and
    /// `url` as well on the entries the roster gives one for.
    ///
    /// This is #192's closing assertion, carried across the change that removed
    /// the test which made it. What was asserted about a hand-written section
    /// is emitted here, so a section carrying an entry with neither is no
    /// longer a state this repo or a consumer can be in.
    function testEtherscanSectionStatesChainOnEveryEntry() external pure {
        assertEq(
            LibRainDeployConfig.etherscanSection(vm, fixtureRoster()),
            "[etherscan]\n" 'alpha = { key = "${CI_DEPLOY_ALPHA_ETHERSCAN_API_KEY}", chain = 11 }\n'
            'beta = { key = "${CI_DEPLOY_BETA_ETHERSCAN_API_KEY}", chain = 22, url = "https://beta.example/api" }\n'
            'gamma = { key = "${CI_DEPLOY_GAMMA_ETHERSCAN_API_KEY}", chain = 33 }\n'
        );
    }

    /// PROPERTY: what is emitted parses as the section it claims to be, and
    /// every entry in it satisfies foundry's own condition for an entry it can
    /// resolve.
    ///
    /// Asked of foundry's TOML parser rather than of the emitted text, so the
    /// oracle is the file format and not the concatenation under test. The
    /// literal above pins the bytes; this pins what they MEAN.
    function testEtherscanSectionEntriesAreResolvable() external view {
        string memory section = LibRainDeployConfig.etherscanSection(vm, fixtureRoster());
        string[] memory entries = vm.parseTomlKeys(section, ".etherscan");
        assertEq(entries.length, 3);
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(
                vm.keyExistsToml(section, string.concat(".etherscan.", entries[i], ".chain"))
                    || vm.keyExistsToml(section, string.concat(".etherscan.", entries[i], ".url")),
                string.concat("[etherscan] entry states neither chain nor url: ", entries[i])
            );
        }
    }

    /// PROPERTY: the same holds of the section generated from the REAL roster,
    /// which is the one every consumer's config is written from.
    function testEtherscanSectionOfTheSupportedNetworksIsResolvable() external view {
        SupportedNetwork[] memory networks = LibRainDeploy.supportedNetworkConfigs();
        string memory section = LibRainDeployConfig.etherscanSection(vm, networks);
        string[] memory entries = vm.parseTomlKeys(section, ".etherscan");
        assertEq(entries.length, networks.length);
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(
                vm.keyExistsToml(section, string.concat(".etherscan.", entries[i], ".chain"))
                    || vm.keyExistsToml(section, string.concat(".etherscan.", entries[i], ".url")),
                string.concat("[etherscan] entry states neither chain nor url: ", entries[i])
            );
        }
    }

    /// PROPERTY: a roster entry with no chain id is refused rather than emitted
    /// as `chain = 0`, which resolves to no chain at all.
    function testEtherscanSectionZeroChainIdReverts() external {
        SupportedNetwork[] memory networks = fixtureRoster();
        networks[1].chainId = 0;
        vm.expectRevert(abi.encodeWithSelector(NoChainId.selector, "beta"));
        this.externalEtherscanSection(networks);
    }

    /// PROPERTY: the `.env.example` block declares each network's endpoint
    /// variable bound to the roster's default for it.
    function testEnvExampleSectionIsTheRosterDefaults() external pure {
        assertEq(
            LibRainDeployConfig.envExampleSection(vm, fixtureRoster()),
            "ALPHA_RPC_URL=https://alpha.example\n" "BETA_RPC_URL=https://beta.example\n"
            "GAMMA_RPC_URL=https://gamma.example\n"
        );
    }

    /// PROPERTY: a network name that is not already uppercase reaches the
    /// variable names uppercased, and an underscore survives it.
    ///
    /// Every real network name is lowercase, so a generator that passed the
    /// name through unchanged would emit `base_sepolia = "${base_sepolia_RPC_URL}"`
    /// and every endpoint would be unbound at the same time.
    function testVariableNamesAreUppercased() external pure {
        assertEq(LibRainDeployConfig.rpcUrlVar(vm, "base_sepolia"), "BASE_SEPOLIA_RPC_URL");
        assertEq(LibRainDeployConfig.etherscanKeyVar(vm, "base_sepolia"), "CI_DEPLOY_BASE_SEPOLIA_ETHERSCAN_API_KEY");
    }

    /// PROPERTY: an empty roster is refused by every emitter rather than
    /// written as an empty section.
    ///
    /// An empty `[rpc_endpoints]` is a repo that deploys nowhere and forks
    /// nothing, with every check that reads it green for want of a subject.
    function testEmptyRosterReverts() external {
        SupportedNetwork[] memory networks = new SupportedNetwork[](0);

        vm.expectRevert(EmptyRoster.selector);
        this.externalRpcEndpointsSection(networks);

        vm.expectRevert(EmptyRoster.selector);
        this.externalEtherscanSection(networks);

        vm.expectRevert(EmptyRoster.selector);
        this.externalEnvExampleSection(networks);
    }

    /// PROPERTY: a splice replaces what is between the markers and moves
    /// nothing outside them.
    ///
    /// The whole reason the blocks are delimited: everything else in a
    /// `foundry.toml` is hand written, and a generator that owned the file
    /// would take the profile with it.
    function testSpliceReplacesOnlyBetweenTheMarkers() external pure {
        string memory before = "# leading prose\n" "# rain-deploy:generated:env:begin\n" "STALE=1\n"
            "# rain-deploy:generated:env:end\n" "# trailing prose\n";

        assertEq(
            LibRainDeployConfig.spliceBlock(vm, "fixture", before, "env", "FRESH=2\n"),
            "# leading prose\n" "# rain-deploy:generated:env:begin\n" "FRESH=2\n" "# rain-deploy:generated:env:end\n"
            "# trailing prose\n"
        );
    }

    /// PROPERTY: splicing the same body twice is the same file, so a build that
    /// changed nothing leaves nothing for `Git is clean` to see.
    function testSpliceIsIdempotent() external pure {
        string memory before = "# rain-deploy:generated:env:begin\n" "STALE=1\n" "# rain-deploy:generated:env:end\n";
        string memory once = LibRainDeployConfig.spliceBlock(vm, "fixture", before, "env", "FRESH=2\n");
        assertEq(LibRainDeployConfig.spliceBlock(vm, "fixture", once, "env", "FRESH=2\n"), once);
    }

    /// PROPERTY: a file carrying more than one block has the named one replaced
    /// and the others left where they are.
    function testSpliceLeavesTheOtherBlocksAlone() external pure {
        string memory before = "# rain-deploy:generated:rpc_endpoints:begin\n" "[rpc_endpoints]\n"
            "# rain-deploy:generated:rpc_endpoints:end\n" "\n" "# rain-deploy:generated:etherscan:begin\n" "STALE\n"
            "# rain-deploy:generated:etherscan:end\n";

        assertEq(
            LibRainDeployConfig.spliceBlock(vm, "fixture", before, "etherscan", "[etherscan]\n"),
            "# rain-deploy:generated:rpc_endpoints:begin\n" "[rpc_endpoints]\n"
            "# rain-deploy:generated:rpc_endpoints:end\n" "\n" "# rain-deploy:generated:etherscan:begin\n"
            "[etherscan]\n" "# rain-deploy:generated:etherscan:end\n"
        );
    }

    /// PROPERTY: a file with no begin marker is refused, naming the file and
    /// the block.
    ///
    /// This is what a consumer that has not adopted the generated blocks looks
    /// like, and it MUST be loud: appending the section instead would be a
    /// duplicate TOML key at the next forge startup, and skipping it silently
    /// would leave a hand-written config nothing regenerates and nothing
    /// compares any more.
    function testSpliceMissingBeginMarkerReverts() external {
        vm.expectRevert(abi.encodeWithSelector(GeneratedBlockMalformed.selector, "fixture", "env"));
        this.externalSpliceBlock(
            "fixture", "# nothing generated here\n# rain-deploy:generated:env:end\n", "env", "FRESH=2\n"
        );
    }

    /// PROPERTY: a file with a begin marker and no end marker is refused.
    function testSpliceMissingEndMarkerReverts() external {
        vm.expectRevert(abi.encodeWithSelector(GeneratedBlockMalformed.selector, "fixture", "env"));
        this.externalSpliceBlock("fixture", "# rain-deploy:generated:env:begin\nSTALE=1\n", "env", "FRESH=2\n");
    }

    /// PROPERTY: a second begin marker is refused rather than one of the two
    /// blocks being picked.
    function testSpliceDuplicateBeginMarkerReverts() external {
        vm.expectRevert(abi.encodeWithSelector(GeneratedBlockMalformed.selector, "fixture", "env"));
        this.externalSpliceBlock(
            "fixture",
            "# rain-deploy:generated:env:begin\n" "STALE=1\n" "# rain-deploy:generated:env:end\n"
            "# rain-deploy:generated:env:begin\n" "ALSO_STALE=1\n" "# rain-deploy:generated:env:end\n",
            "env",
            "FRESH=2\n"
        );
    }

    /// PROPERTY: a second end marker is refused.
    function testSpliceDuplicateEndMarkerReverts() external {
        vm.expectRevert(abi.encodeWithSelector(GeneratedBlockMalformed.selector, "fixture", "env"));
        this.externalSpliceBlock(
            "fixture",
            "# rain-deploy:generated:env:begin\n" "STALE=1\n" "# rain-deploy:generated:env:end\n"
            "# rain-deploy:generated:env:end\n",
            "env",
            "FRESH=2\n"
        );
    }

    /// PROPERTY: an end marker BEFORE the begin marker is refused rather than
    /// spliced around, which would move the marker to the other side of the
    /// block and leave a file that never splices again.
    function testSpliceEndBeforeBeginReverts() external {
        vm.expectRevert(abi.encodeWithSelector(GeneratedBlockMalformed.selector, "fixture", "env"));
        this.externalSpliceBlock(
            "fixture",
            "# rain-deploy:generated:env:end\n" "STALE=1\n" "# rain-deploy:generated:env:begin\n",
            "env",
            "FRESH=2\n"
        );
    }

    /// PROPERTY: the config writer replaces BOTH sections of the file it reads,
    /// and nothing else in it, writing the result WHERE IT WAS TOLD rather than
    /// back over what it read.
    ///
    /// The source staying untouched is the property: foundry refuses a
    /// cheatcode write to the project root's own `foundry.toml`, so the only
    /// thing that can put this result there is `script/build.sh`.
    function testWriteNetworkConfigWritesBothSections() external {
        resetFixtures(CONFIG_FIXTURE_ROOT);
        string memory path = string.concat(CONFIG_FIXTURE_ROOT, "/foundry.toml");
        string memory staged = string.concat(CONFIG_FIXTURE_ROOT, "/staged-foundry.toml");
        string memory source = "[profile.default]\n" "src = \"src\"\n" "\n"
            "# rain-deploy:generated:rpc_endpoints:begin\n" "STALE\n" "# rain-deploy:generated:rpc_endpoints:end\n" "\n"
            "# rain-deploy:generated:etherscan:begin\n" "STALE\n" "# rain-deploy:generated:etherscan:end\n";
        writeFixture(CONFIG_FIXTURE_ROOT, path, source);

        LibRainDeployConfig.writeNetworkConfig(vm, path, staged, singleRoster("alpha", 11));

        string memory written = vm.readFile(staged);
        string memory read = vm.readFile(path);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(CONFIG_FIXTURE_ROOT, true);

        assertEq(read, source);
        assertEq(
            written,
            "[profile.default]\n" "src = \"src\"\n" "\n" "# rain-deploy:generated:rpc_endpoints:begin\n"
            "[rpc_endpoints]\n" 'alpha = "${ALPHA_RPC_URL}"\n' "# rain-deploy:generated:rpc_endpoints:end\n" "\n"
            "# rain-deploy:generated:etherscan:begin\n" "[etherscan]\n"
            'alpha = { key = "${CI_DEPLOY_ALPHA_ETHERSCAN_API_KEY}", chain = 11 }\n'
            "# rain-deploy:generated:etherscan:end\n"
        );
    }

    /// PROPERTY: the `.env.example` writer replaces its block and nothing else,
    /// and leaves what it read where it was.
    function testWriteEnvExampleWritesTheBlock() external {
        resetFixtures(ENV_FIXTURE_ROOT);
        string memory path = string.concat(ENV_FIXTURE_ROOT, "/.env.example");
        string memory staged = string.concat(ENV_FIXTURE_ROOT, "/staged.env.example");
        string memory source = "# prose\n" "# rain-deploy:generated:env:begin\n" "STALE=1\n"
            "# rain-deploy:generated:env:end\n" "HAND_WRITTEN=1\n";
        writeFixture(ENV_FIXTURE_ROOT, path, source);

        LibRainDeployConfig.writeEnvExample(vm, path, staged, singleRoster("alpha", 11));

        string memory written = vm.readFile(staged);
        string memory read = vm.readFile(path);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(ENV_FIXTURE_ROOT, true);

        assertEq(read, source);
        assertEq(
            written,
            "# prose\n" "# rain-deploy:generated:env:begin\n" "ALPHA_RPC_URL=https://one\n"
            "# rain-deploy:generated:env:end\n" "HAND_WRITTEN=1\n"
        );
    }

    /// PROPERTY: the writer names the FILE it was pointed at when that file
    /// carries no markers, rather than the file it would have been pointed at
    /// by default.
    function testWriteNetworkConfigWithoutMarkersReverts() external {
        resetFixtures(NO_MARKERS_FIXTURE_ROOT);
        string memory path = string.concat(NO_MARKERS_FIXTURE_ROOT, "/foundry.toml");
        string memory staged = string.concat(NO_MARKERS_FIXTURE_ROOT, "/staged-foundry.toml");
        writeFixture(NO_MARKERS_FIXTURE_ROOT, path, "[profile.default]\n");

        vm.expectRevert(abi.encodeWithSelector(GeneratedBlockMalformed.selector, path, "rpc_endpoints"));
        this.externalWriteNetworkConfig(path, staged, singleRoster("alpha", 11));

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(NO_MARKERS_FIXTURE_ROOT, true);
    }

    /// PROPERTY: a staged file is named EXACTLY as the file it will be
    /// installed over, and sits under the staging directory of the root it was
    /// generated for.
    ///
    /// `script/build.sh` copies each staged file onto the file of the same name
    /// at the root, so the name is the whole of the mapping between the two.
    function testStagedPathsAreNamedAsTheFilesTheyInstallOver() external pure {
        assertEq(LibRainDeployConfig.configPath("."), "./foundry.toml");
        assertEq(LibRainDeployConfig.envExamplePath("."), "./.env.example");
        assertEq(LibRainDeployConfig.stagedDir("."), "./.staged-config");
        assertEq(LibRainDeployConfig.stagedPath(".", LibRainDeployConfig.CONFIG_NAME), "./.staged-config/foundry.toml");
        assertEq(
            LibRainDeployConfig.stagedPath(".", LibRainDeployConfig.ENV_EXAMPLE_NAME), "./.staged-config/.env.example"
        );
    }

    /// PROPERTY: staging puts BOTH generated files in the staging directory and
    /// changes neither of the files it read.
    function testWriteStagedConfigStagesBothFiles() external {
        resetFixtures(STAGED_FIXTURE_ROOT);
        string memory configSource = "# rain-deploy:generated:rpc_endpoints:begin\n" "STALE\n"
            "# rain-deploy:generated:rpc_endpoints:end\n" "# rain-deploy:generated:etherscan:begin\n" "STALE\n"
            "# rain-deploy:generated:etherscan:end\n";
        string memory envSource = "# rain-deploy:generated:env:begin\n" "STALE=1\n" "# rain-deploy:generated:env:end\n";
        writeFixture(STAGED_FIXTURE_ROOT, LibRainDeployConfig.configPath(STAGED_FIXTURE_ROOT), configSource);
        writeFixture(STAGED_FIXTURE_ROOT, LibRainDeployConfig.envExamplePath(STAGED_FIXTURE_ROOT), envSource);

        LibRainDeployConfig.writeStagedConfig(
            vm, STAGED_FIXTURE_ROOT, LibRainDeployConfig.BUILD_HOOK_PATH, singleRoster("alpha", 11)
        );

        string memory stagedConfig =
            vm.readFile(LibRainDeployConfig.stagedPath(STAGED_FIXTURE_ROOT, LibRainDeployConfig.CONFIG_NAME));
        string memory stagedEnv =
            vm.readFile(LibRainDeployConfig.stagedPath(STAGED_FIXTURE_ROOT, LibRainDeployConfig.ENV_EXAMPLE_NAME));
        string memory readConfig = vm.readFile(LibRainDeployConfig.configPath(STAGED_FIXTURE_ROOT));
        string memory readEnv = vm.readFile(LibRainDeployConfig.envExamplePath(STAGED_FIXTURE_ROOT));
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(STAGED_FIXTURE_ROOT, true);

        assertEq(readConfig, configSource);
        assertEq(readEnv, envSource);
        assertEq(
            stagedConfig,
            "# rain-deploy:generated:rpc_endpoints:begin\n" "[rpc_endpoints]\n" 'alpha = "${ALPHA_RPC_URL}"\n'
            "# rain-deploy:generated:rpc_endpoints:end\n" "# rain-deploy:generated:etherscan:begin\n" "[etherscan]\n"
            'alpha = { key = "${CI_DEPLOY_ALPHA_ETHERSCAN_API_KEY}", chain = 11 }\n'
            "# rain-deploy:generated:etherscan:end\n"
        );
        assertEq(
            stagedEnv,
            "# rain-deploy:generated:env:begin\n" "ALPHA_RPC_URL=https://one\n" "# rain-deploy:generated:env:end\n"
        );
    }

    /// PROPERTY: a repo with no build hook is refused, naming the hook, and
    /// nothing is staged.
    ///
    /// The hook is the only thing that installs a staged file. Staging for a
    /// repo that has none writes the roster where nothing reads it while the
    /// config goes on saying whatever it said, and the build reports success —
    /// the silent green this whole mechanism exists to remove. Presence is what
    /// `rainix-copy-artifacts` conditions its own run of the hook on, so this
    /// is exactly the state in which the install would be skipped.
    function testWriteStagedConfigWithoutBuildHookReverts() external {
        resetFixtures(NO_HOOK_FIXTURE_ROOT);
        string memory missing = string.concat(NO_HOOK_FIXTURE_ROOT, "/build.sh");

        vm.expectRevert(abi.encodeWithSelector(BuildHookMissing.selector, missing));
        this.externalWriteStagedConfig(NO_HOOK_FIXTURE_ROOT, missing, singleRoster("alpha", 11));

        bool stagedAnything = vm.exists(LibRainDeployConfig.stagedDir(NO_HOOK_FIXTURE_ROOT));
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(NO_HOOK_FIXTURE_ROOT, true);

        assertFalse(stagedAnything);
    }
}
