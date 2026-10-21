// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";

import {LibSafe} from "../../src/lib/LibSafe.sol";
import {LibForkSafe} from "./LibForkSafe.sol";

/// @title LibLocalSafe
/// @notice A real Safe v1.4.1 on the local EVM, with no RPC: the pinned
/// runtime code of the canonical `SafeProxyFactory`, `SafeL2` singleton and
/// `MultiSendCallOnly` etched at their canonical addresses, then a proxy
/// created through that factory as `LibForkSafe` creates one on a fork. None
/// of the three has an immutable, so the etched code is the deployed code.
library LibLocalSafe {
    /// Etches the canonical contracts and creates a Safe with `owners` and
    /// `threshold`.
    /// @param vm The Vm to etch with.
    /// @param owners The owners.
    /// @param threshold The threshold.
    /// @return The Safe.
    function deploy(Vm vm, address[] memory owners, uint256 threshold) internal returns (Safe) {
        vm.etch(LibSafe.SAFE_V1_4_1_PROXY_FACTORY, LibSafe.SAFE_V1_4_1_PROXY_FACTORY_RUNTIME_CODE);
        vm.etch(LibSafe.SAFE_V1_4_1_L2_SINGLETON, LibSafe.SAFE_V1_4_1_L2_SINGLETON_RUNTIME_CODE);
        vm.etch(LibSafe.SAFE_V1_4_1_MULTI_SEND_CALL_ONLY, LibSafe.SAFE_V1_4_1_MULTI_SEND_CALL_ONLY_RUNTIME_CODE);
        return LibForkSafe.deploy(owners, threshold);
    }
}
