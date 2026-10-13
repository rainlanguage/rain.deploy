// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";

import {LibSafeTx, SafeTx} from "../lib/LibSafeTx.sol";
import {LibSafeFork} from "../lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "../lib/LibSafeTxBuilderJson.sol";

/// @title SafeBundleScript
/// @notice A Safe bundle script, with the authoring and the verification
/// inherited rather than rewritten per script. A script supplies the bundle and
/// the state it must leave; this supplies the rest:
///
/// - `run()` authors the bundle for the Safe on the selected fork: refuses an
///   unauthorable state (`preflight`), builds the transactions
///   (`authorBundle`), simulates each one as the Safe, requires the state the
///   bundle exists to produce (`assertPostState`), writes the Safe Transaction
///   Builder JSON to `artifactPath()` and logs the MultiSend `safeTxHash` at the
///   Safe's current nonce — the hash the signers' devices show.
/// - `verify(jsonPath)` re-derives the bundle from live state and refuses an
///   artifact whose transactions, chain or Safe differ from it, then logs the
///   hash at the live nonce.
///
/// Both entry points derive the bundle through the SAME hooks, so the artifact
/// a signer loads and the bundle `verify` holds it to cannot drift apart.
///
/// A script is the hooks and nothing else:
///
/// ```solidity
/// contract GrantRole is SafeBundleScript {
///     function safe() internal view override returns (Safe) { ... }
///     function preflight() internal view override { ... }
///     function authorBundle() internal view override returns (SafeTx[] memory) { ... }
///     function assertPostState() internal view override { ... }
///     function artifactPath() internal view override returns (string memory) { ... }
///     function bundleName() internal pure override returns (string memory) { ... }
/// }
/// ```
abstract contract SafeBundleScript is Script {
    /// The Safe that executes the bundle on the selected chain.
    /// @return The Safe.
    function safe() internal view virtual returns (Safe);

    /// Reverts unless the selected chain is in a state the bundle can be
    /// authored against: the migration has not already run, its prerequisites
    /// have, the Safe holds what the bundle spends.
    function preflight() internal view virtual;

    /// The bundle's transactions, every one a CALL, derived from live state.
    /// @return The transactions, in execution order.
    function authorBundle() internal view virtual returns (SafeTx[] memory);

    /// Reverts unless the selected fork, after the simulated bundle, is in the
    /// state the bundle exists to produce.
    function assertPostState() internal view virtual;

    /// Where `run()` writes the Safe Transaction Builder JSON.
    /// @return The path.
    function artifactPath() internal view virtual returns (string memory);

    /// The bundle's name, written to the JSON's `meta.name`.
    /// @return The name.
    function bundleName() internal pure virtual returns (string memory);

    /// Authors the bundle on the selected fork, simulates it as the Safe,
    /// requires its post-state, writes the artifact and logs its hash.
    function run() external {
        preflight();
        SafeTx[] memory txs = authorBundle();
        Safe bundleSafe = safe();
        uint256 nonce = bundleSafe.nonce();
        bytes32 bundleSafeTxHash = LibSafeTx.multiSendSafeTxHash(bundleSafe, txs, nonce);
        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeFork.simulateCall(vm, bundleSafe, txs[i].to, txs[i].data);
        }
        assertPostState();
        string memory json = LibSafeTxBuilderJson.toJson(vm, address(bundleSafe), block.chainid, bundleName(), txs);
        vm.writeFile(artifactPath(), json);
        console2.log("Safe:", address(bundleSafe));
        console2.log("Chain:", block.chainid);
        console2.log("Nonce:", nonce);
        console2.log("Transactions:", txs.length);
        console2.log("Bundle MultiSend SafeTxHash:", vm.toString(bundleSafeTxHash));
        console2.log("Artifact:", artifactPath());
    }

    /// Re-derives the bundle from live state and refuses an artifact that
    /// differs from it in its transactions, its chain or its Safe, then logs the
    /// hash at the live nonce.
    /// @param jsonPath The artifact to check.
    function verify(string calldata jsonPath) external view {
        preflight();
        SafeTx[] memory expected = authorBundle();
        Safe bundleSafe = safe();
        LibSafeTxBuilderJson.requireMatches(vm, vm.readFile(jsonPath), address(bundleSafe), expected);
        console2.log("Artifact verified against live state.");
        console2.log(
            "Bundle MultiSend SafeTxHash:",
            vm.toString(LibSafeTx.multiSendSafeTxHash(bundleSafe, expected, bundleSafe.nonce()))
        );
    }
}
