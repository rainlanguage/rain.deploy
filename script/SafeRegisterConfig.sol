// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";

import {RegistryDeploySuites} from "../src/abstract/RegistryDeploySuites.sol";
import {SafeBundleScript} from "../src/abstract/SafeBundleScript.sol";
import {LibConfigRegistryRegister} from "../src/lib/LibConfigRegistryRegister.sol";
import {LibConfigRegistrySafeRegister} from "../src/lib/LibConfigRegistrySafeRegister.sol";
import {LibRainDeploy, SupportedNetwork} from "../src/lib/LibRainDeploy.sol";
import {SafeTx} from "../src/lib/LibSafeTx.sol";

/// @title SafeRegisterConfig
/// @notice Authors, per network, the Safe bundle in which the Safe
/// `CONFIG_SAFE_ADDRESS` binds `CONFIG_SAFE_NAME` to `CONFIG_SAFE_VALUE` under
/// `CONFIG_SAFE_AUTHORITY` in the `ConfigRegistry`: one
/// `registerV2(authority, name, value)` CALL from the Safe, which the authority
/// approved as its delegate for the name with `approveV2` on that network. It
/// acts on every network the declaration supports, or on the comma-separated
/// subset `CONFIG_SAFE_NETWORKS` names. The README's "Binding from a Safe"
/// section carries the commands and what the signers check.
///
/// Three entry points, each forking every selected network:
///
/// - `runOnNetworks()` refuses each network the bind cannot be authored on,
///   skips one already bound to the value, and on the rest runs the inherited
///   `SafeBundleScript.run()`: executes the bundle through the Safe's
///   `execTransaction` on the fork, requires the binding, writes the Safe
///   Transaction Builder JSON to `artifactPath()` and logs the `safeTxHash`.
/// - `verifyOnNetworks()` holds each unbound network's artifact to the bundle
///   re-derived from live state, through the inherited `verify(jsonPath)`, and
///   logs the hash at the live nonce: the check made just before signing.
/// - `verify()` is the confirmed check once the Safes have executed: the name
///   resolves to the value under the authority on every selected network,
///   and the authority and the Safe are each the same account on every one.
///
/// The inherited `run()` and `verify(jsonPath)` act on the network the loop
/// selected and refuse `NoNetworkSelected` when called directly. Nothing here
/// broadcasts: the owners sign and execute in the Safe wallet.
contract SafeRegisterConfig is RegistryDeploySuites, SafeBundleScript {
    /// The environment variable holding the authority to bind under: the
    /// account consumers resolve the name under, which approved the Safe.
    string constant AUTHORITY_VAR = "CONFIG_SAFE_AUTHORITY";

    /// The environment variable holding the name, as a consumer writes it
    /// before hashing.
    string constant NAME_VAR = "CONFIG_SAFE_NAME";

    /// The environment variable holding the value, as `0x`-prefixed hex of its
    /// ABI encoding.
    string constant VALUE_VAR = "CONFIG_SAFE_VALUE";

    /// The environment variable holding the Safe that executes the bind.
    string constant SAFE_VAR = "CONFIG_SAFE_ADDRESS";

    /// The environment variable narrowing the networks, comma separated.
    string constant NETWORKS_VAR = "CONFIG_SAFE_NETWORKS";

    /// Thrown when a `SafeBundleScript` hook runs outside the network loop,
    /// which is what sets the network it acts on.
    error NoNetworkSelected();

    /// The network the loop selected, its chain id zero outside the loop.
    SupportedNetwork internal sNetwork;

    /// The networks to act on: `CONFIG_SAFE_NETWORKS` if set, otherwise every
    /// network the declaration supports.
    /// @return The network names, as `[rpc_endpoints]` aliases.
    function selectedNetworks() internal view returns (string[] memory) {
        return vm.envOr(NETWORKS_VAR, ",", supportedNetworks());
    }

    /// The Vm the entry points fork and select with.
    /// @return The cheatcodes.
    function forkVm() internal view virtual returns (Vm) {
        return vm;
    }

    /// The authority, from the environment.
    /// @return The authority.
    function authority() internal view returns (address) {
        return vm.envAddress(AUTHORITY_VAR);
    }

    /// The name as a consumer writes it, from the environment.
    /// @return The name.
    function name() internal view returns (string memory) {
        return vm.envString(NAME_VAR);
    }

    /// The value, from the environment.
    /// @return The ABI-encoded value.
    function value() internal view returns (bytes memory) {
        return vm.envBytes(VALUE_VAR);
    }

    /// The network the loop selected.
    /// @return Its catalogue entry.
    function network() internal view returns (SupportedNetwork memory) {
        if (sNetwork.chainId == 0) revert NoNetworkSelected();
        return sNetwork;
    }

    /// @inheritdoc SafeBundleScript
    function safe() internal view override returns (Safe) {
        return Safe(payable(vm.envAddress(SAFE_VAR)));
    }

    /// @inheritdoc SafeBundleScript
    function preflight() internal view override {
        LibConfigRegistrySafeRegister.checkSafe(
            vm, network(), safe(), authority(), LibConfigRegistryRegister.nameHash(name())
        );
    }

    /// @inheritdoc SafeBundleScript
    function authorBundle() internal view override returns (SafeTx[] memory) {
        return LibConfigRegistrySafeRegister.bundle(authority(), LibConfigRegistryRegister.nameHash(name()), value());
    }

    /// @inheritdoc SafeBundleScript
    function assertPostState() internal view override {
        LibConfigRegistryRegister.checkRegisteredOnSelectedChain(
            vm, network(), authority(), LibConfigRegistryRegister.nameHash(name()), value()
        );
    }

    /// @inheritdoc SafeBundleScript
    function artifactPath() internal view override returns (string memory) {
        return LibConfigRegistrySafeRegister.artifactPath(name(), network().name);
    }

    /// @inheritdoc SafeBundleScript
    function bundleName() internal pure override returns (string memory) {
        return "ConfigRegistry registerV2";
    }

    /// Refuses the inputs, forks every selected network, and on each refuses
    /// what `preflight` refuses, then logs the current binding and what the
    /// run does to it.
    /// @return The networks' catalogue entries.
    /// @return The fork of each.
    /// @return Whether each is already bound to the value.
    function selectAndCheck() internal returns (SupportedNetwork[] memory, uint256[] memory, bool[] memory) {
        string[] memory selected = selectedNetworks();
        (bytes32 hashed, SupportedNetwork[] memory networks, string memory record) = LibConfigRegistryRegister.checkInputs(
            vm, selected, supportedNetworks(), address(safe()), authority(), name(), value()
        );
        console2.log(record);
        uint256[] memory forkIds = LibRainDeploy.createForks(forkVm(), selected);
        bool[] memory bound = new bool[](networks.length);
        for (uint256 i = 0; i < networks.length; i++) {
            forkVm().selectFork(forkIds[i]);
            sNetwork = networks[i];
            preflight();
            (bytes memory current, uint256 registeredAt) =
                LibConfigRegistryRegister.currentBinding(authority(), hashed);
            console2.log(
                LibConfigRegistryRegister.describeNetwork(
                    vm, networks[i].name, networks[i].chainId, current, registeredAt, value()
                )
            );
            bound[i] = keccak256(current) == keccak256(value());
        }
        delete sNetwork;
        return (networks, forkIds, bound);
    }

    /// Authors the bundle on every selected network not already bound to the
    /// value, and removes any artifact left at a bound one's path.
    /// @return Each network's `safeTxHash` at the Safe's nonce before
    /// execution, zero where it skipped.
    function runOnNetworks() external returns (bytes32[] memory) {
        (SupportedNetwork[] memory networks, uint256[] memory forkIds, bool[] memory bound) = selectAndCheck();
        bytes32[] memory hashes = new bytes32[](networks.length);
        vm.createDir(LibConfigRegistrySafeRegister.artifactDir(name()), true);
        for (uint256 i = 0; i < networks.length; i++) {
            forkVm().selectFork(forkIds[i]);
            sNetwork = networks[i];
            if (bound[i]) {
                string memory path = artifactPath();
                if (vm.exists(path)) vm.removeFile(path);
            } else {
                hashes[i] = this.run();
            }
        }
        delete sNetwork;
        return hashes;
    }

    /// Holds the artifact of every selected network not already bound to the
    /// value to the bundle re-derived from live state.
    /// @return Each network's `safeTxHash` at the Safe's live nonce, zero where
    /// it skipped.
    function verifyOnNetworks() external returns (bytes32[] memory) {
        (SupportedNetwork[] memory networks, uint256[] memory forkIds, bool[] memory bound) = selectAndCheck();
        bytes32[] memory hashes = new bytes32[](networks.length);
        for (uint256 i = 0; i < networks.length; i++) {
            forkVm().selectFork(forkIds[i]);
            sNetwork = networks[i];
            if (!bound[i]) {
                console2.log(string.concat("Network: ", networks[i].name));
                hashes[i] = this.verify(artifactPath());
            }
        }
        delete sNetwork;
        return hashes;
    }

    /// Reads every selected network fresh and reverts unless the name resolves
    /// to the value under the authority on each, and the authority and the
    /// Safe are each the same account on every one.
    function verify() external {
        address[] memory accounts = new address[](2);
        accounts[0] = authority();
        accounts[1] = address(safe());
        LibConfigRegistryRegister.checkRegisteredOnNetworks(
            forkVm(), selectedNetworks(), supportedNetworks(), authority(), name(), value(), accounts
        );
    }
}
