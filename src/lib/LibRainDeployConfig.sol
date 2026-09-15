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
library LibRainDeployConfig {
    /// The repo-root `foundry.toml` the sections are written into. Relative, so
    /// it resolves against the project root of whatever runs the build — the
    /// consuming repo's own config rather than this package's.
    string constant CONFIG_PATH = "foundry.toml";

    /// The repo-root `.env.example` the endpoint variables are written into.
    string constant ENV_EXAMPLE_PATH = ".env.example";

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

    /// Writes both `foundry.toml` sections from the roster.
    ///
    /// `foundry.toml` is read by forge at startup and never re-read, so a
    /// script rewriting it does not move anything under itself. A TEST that
    /// reads it does race this, which is why nothing under `forge test` points
    /// this at the repo's own config.
    /// @param vm The Vm instance for file operations.
    /// @param path The config to write — `CONFIG_PATH` for a repo's own.
    /// @param networks The roster.
    /// @return The path written.
    function writeNetworkConfig(Vm vm, string memory path, SupportedNetwork[] memory networks)
        internal
        returns (string memory)
    {
        string memory content = vm.readFile(path);
        content = spliceBlock(vm, path, content, RPC_ENDPOINTS_BLOCK, rpcEndpointsSection(vm, networks));
        content = spliceBlock(vm, path, content, ETHERSCAN_BLOCK, etherscanSection(vm, networks));
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(path, content);
        return path;
    }

    /// Writes the `.env.example` endpoint block from the roster.
    /// @param vm The Vm instance for file operations.
    /// @param path The file to write — `ENV_EXAMPLE_PATH` for a repo's own.
    /// @param networks The roster.
    /// @return The path written.
    function writeEnvExample(Vm vm, string memory path, SupportedNetwork[] memory networks)
        internal
        returns (string memory)
    {
        string memory content = vm.readFile(path);
        content = spliceBlock(vm, path, content, ENV_BLOCK, envExampleSection(vm, networks));
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(path, content);
        return path;
    }
}
