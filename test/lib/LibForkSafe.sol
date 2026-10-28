// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.5.0/contracts/Safe.sol";
import {SafeProxyFactory} from "safe-global-safe-smart-account-1.5.0/contracts/proxies/SafeProxyFactory.sol";
import {LibSafe} from "../../src/lib/LibSafe.sol";

/// @title LibForkSafe
/// @notice Creates a real Safe v1.4.1 on a fork of a chain that has the
/// canonical v1.4.1 deployments, so tests run the Safe's own hashing,
/// signature checking and execution rather than a model of them.
library LibForkSafe {
    /// A new Safe proxy on the canonical v1.4.1 `SafeL2` singleton, created
    /// through the canonical v1.4.1 `SafeProxyFactory`, with `owners` and
    /// `threshold`, no modules, no fallback handler.
    /// @param owners The owners.
    /// @param threshold The threshold.
    /// @return The Safe.
    function deploy(address[] memory owners, uint256 threshold) internal returns (Safe) {
        bytes memory setup = abi.encodeCall(
            Safe.setup, (owners, threshold, address(0), "", address(0), address(0), 0, payable(address(0)))
        );
        address proxy = address(
            SafeProxyFactory(LibSafe.SAFE_V1_4_1_PROXY_FACTORY)
                .createProxyWithNonce(
                    LibSafe.SAFE_V1_4_1_L2_SINGLETON, setup, uint256(keccak256(abi.encode(owners, threshold)))
                )
        );
        return Safe(payable(proxy));
    }
}
