// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {
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

    /// @param path The config to write.
    /// @param networks The roster.
    /// @return The path written.
    function externalWriteNetworkConfig(string memory path, SupportedNetwork[] memory networks)
        external
        returns (string memory)
    {
        return LibRainDeployConfig.writeNetworkConfig(vm, path, networks);
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

    /// PROPERTY: the config writer replaces BOTH sections of the file it is
    /// pointed at, and nothing else in it.
    function testWriteNetworkConfigWritesBothSections() external {
        resetFixtures(CONFIG_FIXTURE_ROOT);
        string memory path = string.concat(CONFIG_FIXTURE_ROOT, "/foundry.toml");
        writeFixture(
            CONFIG_FIXTURE_ROOT,
            path,
            "[profile.default]\n" "src = \"src\"\n" "\n" "# rain-deploy:generated:rpc_endpoints:begin\n" "STALE\n"
            "# rain-deploy:generated:rpc_endpoints:end\n" "\n" "# rain-deploy:generated:etherscan:begin\n" "STALE\n"
            "# rain-deploy:generated:etherscan:end\n"
        );

        LibRainDeployConfig.writeNetworkConfig(vm, path, singleRoster("alpha", 11));

        string memory written = vm.readFile(path);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(CONFIG_FIXTURE_ROOT, true);

        assertEq(
            written,
            "[profile.default]\n" "src = \"src\"\n" "\n" "# rain-deploy:generated:rpc_endpoints:begin\n"
            "[rpc_endpoints]\n" 'alpha = "${ALPHA_RPC_URL}"\n' "# rain-deploy:generated:rpc_endpoints:end\n" "\n"
            "# rain-deploy:generated:etherscan:begin\n" "[etherscan]\n"
            'alpha = { key = "${CI_DEPLOY_ALPHA_ETHERSCAN_API_KEY}", chain = 11 }\n'
            "# rain-deploy:generated:etherscan:end\n"
        );
    }

    /// PROPERTY: the `.env.example` writer replaces its block and nothing else.
    function testWriteEnvExampleWritesTheBlock() external {
        resetFixtures(ENV_FIXTURE_ROOT);
        string memory path = string.concat(ENV_FIXTURE_ROOT, "/.env.example");
        writeFixture(
            ENV_FIXTURE_ROOT,
            path,
            "# prose\n" "# rain-deploy:generated:env:begin\n" "STALE=1\n" "# rain-deploy:generated:env:end\n"
            "HAND_WRITTEN=1\n"
        );

        LibRainDeployConfig.writeEnvExample(vm, path, singleRoster("alpha", 11));

        string memory written = vm.readFile(path);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(ENV_FIXTURE_ROOT, true);

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
        writeFixture(NO_MARKERS_FIXTURE_ROOT, path, "[profile.default]\n");

        vm.expectRevert(abi.encodeWithSelector(GeneratedBlockMalformed.selector, path, "rpc_endpoints"));
        this.externalWriteNetworkConfig(path, singleRoster("alpha", 11));

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(NO_MARKERS_FIXTURE_ROOT, true);
    }
}
