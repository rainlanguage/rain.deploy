// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.16.2/src/Vm.sol";
import {SupportedNetwork} from "./LibRainDeploy.sol";

/// Thrown when the file a generated block is written into does not carry that
/// block's markers exactly once each, the begin before the end. Refused rather
/// than appended: a file with no markers is a file whose config is hand
/// written, and appending a second copy of a section to a TOML file is a
/// duplicate key error at the next forge startup.
/// @param path The file the block was to be written into.
/// @param name The block name, as it appears in the markers.
error GeneratedBlockMalformed(string path, string name);

/// Thrown when a roster entry states no chain id. A generated `[etherscan]`
/// entry states `chain` from this field and nothing else, and `chain = 0` is an
/// entry `--verify` resolves to no chain at all — so the roster cannot be
/// silent about it.
/// @param network The roster entry with no chain id.
error NoChainId(string network);

/// Thrown when the roster is empty. Both sections would be generated with no
/// entries, which is a repo that deploys nowhere and verifies nothing while
/// every check that reads them stays green.
error EmptyRoster();

/// Thrown when the repo has no `script/build.sh`. That hook is the only thing
/// that moves a staged config into place, so without it the generated blocks
/// are written somewhere nothing reads, `foundry.toml` never changes, and `Git
/// is clean` passes a tree whose config has drifted from the roster it pins —
/// the silent green this whole mechanism exists to remove.
/// @param path The hook that was looked for.
error BuildHookMissing(string path);

/// @title LibRainDeployConfig
/// @notice Writes the network config a deploy repo cannot state twice: the
/// `[rpc_endpoints]` and `[etherscan]` sections of `foundry.toml`, and the
/// `<NAME>_RPC_URL` lines of `.env.example`, all of them from
/// `LibRainDeploy.supportedNetworkConfigs()`.
///
/// Generated rather than compared. A comparison keeps both statements and
/// checks them, so the prose around them drifts silently and every assertion is
/// one somebody has to have thought of; generation leaves one statement, and
/// the enforcement is `Git is clean` — the same mechanism already holding
/// `src/generated/` and `src/lib/`.
///
/// Delimited rather than whole-file, because everything else in `foundry.toml`
/// is hand written and a `.env.example` carries prose a generator has no way to
/// know. Each block is replaced between its markers and nothing outside them is
/// read or moved.
///
/// ## Why the generated files are staged rather than written
///
/// Foundry REFUSES every filesystem cheatcode write to the project root's own
/// `foundry.toml` — "vm.writeFile: access to `foundry.toml` is not allowed" —
/// and it is not an `fs_permissions` miss: the guard is on the path, so no
/// grant and no spelling of the path gets past it. Reads are allowed, which is
/// the whole reason this is possible at all.
///
/// So the spliced file is written to `<root>/.staged-config/` and installed by
/// `script/build.sh`, the hook rainix's `rainix-copy-artifacts` runs — outside
/// any devshell, after `forge script ./script/Build.sol` and before the `git
/// diff` that fails a stale tree. FFI is the other way to reach a shell from a
/// script, and is not taken: the invocation that matters passes no `--ffi`, and
/// granting it there would hand FFI to every consumer's build.
///
/// `.env.example` is staged too, though foundry would allow that one written
/// directly. One mechanism, so which file foundry happens to guard is not
/// something the design depends on.
///
/// Staging also removes the hazard the direct write carried: nothing under
/// `forge test` can race a rewrite of the config every other test reads,
/// because nothing rewrites it at all.
library LibRainDeployConfig {
    /// The project root, which is what a relative path resolves against — the
    /// CONSUMING repo's root rather than this package's.
    string constant CONFIG_ROOT = ".";

    /// The config whose sections are generated, as it is named under the root.
    string constant CONFIG_NAME = "foundry.toml";

    /// The file the endpoint variables are generated into, as it is named under
    /// the root.
    string constant ENV_EXAMPLE_NAME = ".env.example";

    /// The directory under the root that a generated file is staged in. Git
    /// ignored: `script/build.sh` removes it once it has installed what is in
    /// it, and a run that failed between the two must not leave a tracked file
    /// behind.
    string constant STAGED_DIR_NAME = ".staged-config";

    /// The hook that installs what was staged. Matched exactly, because that is
    /// the path `rainix-copy-artifacts` conditions its own step on.
    string constant BUILD_HOOK_PATH = "script/build.sh";

    /// The `[rpc_endpoints]` block, as it is named in its markers.
    string constant RPC_ENDPOINTS_BLOCK = "rpc_endpoints";

    /// The `[etherscan]` block, as it is named in its markers.
    string constant ETHERSCAN_BLOCK = "etherscan";

    /// The `.env.example` endpoint block, as it is named in its markers.
    string constant ENV_BLOCK = "env";

    /// What both markers start with. A `#` comment in TOML and in a dotenv
    /// file alike, so one marker shape serves both.
    string constant MARKER_PREFIX = "# rain-deploy:generated:";

    /// The line a generated block starts after.
    /// @param name The block name.
    /// @return The begin marker, including the newline it ends the line with.
    function beginMarker(string memory name) internal pure returns (string memory) {
        return string.concat(MARKER_PREFIX, name, ":begin\n");
    }

    /// The line a generated block ends before.
    /// @param name The block name.
    /// @return The end marker, without a newline: whatever followed it stays.
    function endMarker(string memory name) internal pure returns (string memory) {
        return string.concat(MARKER_PREFIX, name, ":end");
    }

    /// The environment variable a network's `[rpc_endpoints]` alias
    /// interpolates, and the one `.env.example` declares.
    /// @param vm The Vm instance, for the case conversion only.
    /// @param network The network name.
    /// @return The variable name.
    function rpcUrlVar(Vm vm, string memory network) internal pure returns (string memory) {
        return string.concat(vm.toUppercase(network), "_RPC_URL");
    }

    /// The environment variable a network's `[etherscan]` entry interpolates
    /// its key from. `rainix-manual-sol-artifacts` exports exactly these names.
    /// @param vm The Vm instance, for the case conversion only.
    /// @param network The network name.
    /// @return The variable name.
    function etherscanKeyVar(Vm vm, string memory network) internal pure returns (string memory) {
        return string.concat("CI_DEPLOY_", vm.toUppercase(network), "_ETHERSCAN_API_KEY");
    }

    /// The `[rpc_endpoints]` section, header and all.
    /// @param vm The Vm instance, for the case conversion only.
    /// @param networks The roster.
    /// @return The section text, newline terminated.
    function rpcEndpointsSection(Vm vm, SupportedNetwork[] memory networks) internal pure returns (string memory) {
        if (networks.length == 0) {
            revert EmptyRoster();
        }
        string memory section = "[rpc_endpoints]\n";
        for (uint256 i = 0; i < networks.length; i++) {
            section = string.concat(section, networks[i].name, ' = "${', rpcUrlVar(vm, networks[i].name), '}"', "\n");
        }
        return section;
    }

    /// The `[etherscan]` section, header and all.
    ///
    /// Every entry states `chain`, and `url` as well wherever the roster gives
    /// one. That is foundry's own condition for an entry it can resolve — "At
    /// least one of `url` or `chain` must be present for Etherscan config with
    /// unknown alias" is raised while resolving the SECTION, so one entry that
    /// cannot be resolved takes verification down for every network in it and
    /// not only its own. Stating the chain an alias already resolves to
    /// resolves it to the same chain, so stating it on all of them cannot go
    /// wrong when foundry adds or renames an alias.
    /// @param vm The Vm instance, for the case conversion and `chain`.
    /// @param networks The roster.
    /// @return The section text, newline terminated.
    function etherscanSection(Vm vm, SupportedNetwork[] memory networks) internal pure returns (string memory) {
        if (networks.length == 0) {
            revert EmptyRoster();
        }
        string memory section = "[etherscan]\n";
        for (uint256 i = 0; i < networks.length; i++) {
            if (networks[i].chainId == 0) {
                revert NoChainId(networks[i].name);
            }
            string memory entry = string.concat(
                networks[i].name,
                ' = { key = "${',
                etherscanKeyVar(vm, networks[i].name),
                '}", chain = ',
                vm.toString(networks[i].chainId)
            );
            if (bytes(networks[i].explorerUrl).length > 0) {
                entry = string.concat(entry, ', url = "', networks[i].explorerUrl, '"');
            }
            section = string.concat(section, entry, " }\n");
        }
        return section;
    }

    /// The `<NAME>_RPC_URL` lines of `.env.example`.
    /// @param vm The Vm instance, for the case conversion only.
    /// @param networks The roster.
    /// @return The block text, newline terminated.
    function envExampleSection(Vm vm, SupportedNetwork[] memory networks) internal pure returns (string memory) {
        if (networks.length == 0) {
            revert EmptyRoster();
        }
        string memory section = "";
        for (uint256 i = 0; i < networks.length; i++) {
            section = string.concat(section, rpcUrlVar(vm, networks[i].name), "=", networks[i].defaultRpcUrl, "\n");
        }
        return section;
    }

    /// Replaces whatever sits between a block's markers with `body`, leaving
    /// the markers and everything outside them where they are.
    ///
    /// Both markers MUST appear exactly once, the begin before the end. Two
    /// begin markers is a file with two claims about where the block is and no
    /// rule for choosing between them that does not silently keep one of the
    /// copies; none at all is a file nothing here has ever written, which is
    /// what a consumer that has not adopted this looks like.
    /// @param vm The Vm instance, for the string search only.
    /// @param path The file the content came from, for the error only.
    /// @param content The whole file.
    /// @param name The block name.
    /// @param body The block's new content, newline terminated.
    /// @return The whole file, with the block replaced.
    function spliceBlock(Vm vm, string memory path, string memory content, string memory name, string memory body)
        internal
        pure
        returns (string memory)
    {
        string memory begin = beginMarker(name);
        string memory end = endMarker(name);

        // `split` yields one more part than there are occurrences of the
        // delimiter, so this counts them rather than finding the first and
        // hoping it is the only one.
        string[] memory beginParts = vm.split(content, begin);
        if (beginParts.length != 2) {
            revert GeneratedBlockMalformed(path, name);
        }
        string[] memory endParts = vm.split(beginParts[1], end);
        if (endParts.length != 2) {
            revert GeneratedBlockMalformed(path, name);
        }
        // An end marker BEFORE the begin marker is still in the prefix, and
        // splicing would move it to the other side of the block.
        if (vm.contains(beginParts[0], end)) {
            revert GeneratedBlockMalformed(path, name);
        }
        return string.concat(beginParts[0], begin, body, end, endParts[1]);
    }

    /// The config under a root.
    /// @param root The project root.
    /// @return The path.
    function configPath(string memory root) internal pure returns (string memory) {
        return string.concat(root, "/", CONFIG_NAME);
    }

    /// The `.env.example` under a root.
    /// @param root The project root.
    /// @return The path.
    function envExamplePath(string memory root) internal pure returns (string memory) {
        return string.concat(root, "/", ENV_EXAMPLE_NAME);
    }

    /// The staging directory under a root.
    /// @param root The project root.
    /// @return The path.
    function stagedDir(string memory root) internal pure returns (string memory) {
        return string.concat(root, "/", STAGED_DIR_NAME);
    }

    /// Where a generated file is staged, named as it will be installed.
    /// `script/build.sh` copies by name, so a staged file lands on the file of
    /// the same name under the root and nowhere else.
    /// @param root The project root.
    /// @param name The file name under the root.
    /// @return The path.
    function stagedPath(string memory root, string memory name) internal pure returns (string memory) {
        return string.concat(stagedDir(root), "/", name);
    }

    /// Splices both `foundry.toml` sections from the roster, reading one file
    /// and writing another.
    /// @param vm The Vm instance for file operations.
    /// @param path The config to read.
    /// @param staged Where to write the spliced result.
    /// @param networks The roster.
    function writeNetworkConfig(Vm vm, string memory path, string memory staged, SupportedNetwork[] memory networks)
        internal
    {
        string memory content = vm.readFile(path);
        content = spliceBlock(vm, path, content, RPC_ENDPOINTS_BLOCK, rpcEndpointsSection(vm, networks));
        content = spliceBlock(vm, path, content, ETHERSCAN_BLOCK, etherscanSection(vm, networks));
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(staged, content);
    }

    /// Splices the `.env.example` endpoint block from the roster, reading one
    /// file and writing another.
    /// @param vm The Vm instance for file operations.
    /// @param path The `.env.example` to read.
    /// @param staged Where to write the spliced result.
    /// @param networks The roster.
    function writeEnvExample(Vm vm, string memory path, string memory staged, SupportedNetwork[] memory networks)
        internal
    {
        string memory content = vm.readFile(path);
        content = spliceBlock(vm, path, content, ENV_BLOCK, envExampleSection(vm, networks));
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(staged, content);
    }

    /// Stages every generated config file under a root, for the build hook to
    /// install.
    ///
    /// Refuses a repo with no hook. Nothing else moves a staged file into
    /// place, so generating for a repo that has none writes the roster to a
    /// directory nothing reads while the config it is meant to hold goes on
    /// saying whatever it said — green, from a build that regenerated nothing.
    /// Presence is the same condition `rainix-copy-artifacts` runs the hook on,
    /// so this is exactly the state in which the install would be skipped.
    /// @param vm The Vm instance for file operations.
    /// @param root The project root.
    /// @param hookPath The hook that installs what this stages.
    /// @param networks The roster.
    function writeStagedConfig(Vm vm, string memory root, string memory hookPath, SupportedNetwork[] memory networks)
        internal
    {
        if (!vm.exists(hookPath)) {
            revert BuildHookMissing(hookPath);
        }
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(stagedDir(root), true);
        writeNetworkConfig(vm, configPath(root), stagedPath(root, CONFIG_NAME), networks);
        writeEnvExample(vm, envExamplePath(root), stagedPath(root, ENV_EXAMPLE_NAME), networks);
    }
}
