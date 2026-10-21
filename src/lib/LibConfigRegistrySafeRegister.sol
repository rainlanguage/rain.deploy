// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";

import {LibConfigRegistryDeploy} from "./LibConfigRegistryDeploy.sol";
import {LibConfigRegistryRegister} from "./LibConfigRegistryRegister.sol";
import {SupportedNetwork} from "./LibRainDeploy.sol";
import {LibSafe} from "./LibSafe.sol";
import {SafeTx} from "./LibSafeTx.sol";

/// @title LibConfigRegistrySafeRegister
/// @notice A Safe delegate's side of `ConfigRegistry`: the one-transaction
/// Safe bundle that binds a name to a value under the authority that approved
/// the Safe, and the guards the bundle is authored behind.
/// `script/SafeRegisterConfig.sol` is the entry point and says how it is run.
///
/// The name, value and networks are taken and refused exactly as
/// `LibConfigRegistryRegister` takes them, and the bundle's one transaction is
/// its `registerCalldata`, so a Safe binds what a `RegisterConfig` run would
/// bind and a consumer resolves.
library LibConfigRegistrySafeRegister {
    /// Where every artifact is written: one directory per name, one file per
    /// network.
    string internal constant ARTIFACT_ROOT = "safe-bundles/config-registry";

    /// The directory a name's artifacts are written to.
    /// @param name The name as a consumer writes it, already held canonical,
    /// so it is a safe path segment.
    /// @return The directory.
    function artifactDir(string memory name) internal pure returns (string memory) {
        return string.concat(ARTIFACT_ROOT, "/", name);
    }

    /// The artifact of the bind of `name` on `network`.
    /// @param name The name as a consumer writes it.
    /// @param network The network's name.
    /// @return The path.
    function artifactPath(string memory name, string memory network) internal pure returns (string memory) {
        return string.concat(artifactDir(name), "/", network, ".json");
    }

    /// The bundle: one CALL to the pinned registry, value 0, with the
    /// `registerV2(authority, name, value)` calldata.
    /// @param authority The authority to bind under.
    /// @param name The hashed name.
    /// @param value The ABI-encoded value to bind it to.
    /// @return The bundle.
    function bundle(address authority, bytes32 name, bytes memory value) internal pure returns (SafeTx[] memory) {
        SafeTx[] memory txs = new SafeTx[](1);
        txs[0] = SafeTx({
            to: LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS,
            value: 0,
            data: LibConfigRegistryRegister.registerCalldata(authority, name, value),
            operation: Enum.Operation.Call
        });
        return txs;
    }

    /// Reverts unless the selected chain is the network's and holds the pinned
    /// registry (`LibConfigRegistryRegister.checkChain`), `safe` is a genuine
    /// Safe v1.4.1 there (`LibSafe.assertIdentity`), and `safe` is the
    /// authority or a delegate the authority approved there for `name`
    /// (`LibConfigRegistryRegister.checkSender`).
    /// @param vm The Vm the chain id is read through.
    /// @param network The catalogue entry of the selected chain.
    /// @param safe The Safe that executes the bind.
    /// @param authority The authority to bind under.
    /// @param name The hashed name.
    function checkSafe(Vm vm, SupportedNetwork memory network, Safe safe, address authority, bytes32 name)
        internal
        view
    {
        LibConfigRegistryRegister.checkChain(vm, network);
        LibSafe.assertIdentity(safe);
        LibConfigRegistryRegister.checkSender(network, address(safe), authority, name);
    }
}
