// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {SafeProxyFactory} from "safe-global-safe-smart-account-1.4.1-3/contracts/proxies/SafeProxyFactory.sol";

/// @title LibForkSafe
/// @notice Creates a real Safe v1.4.1 on a fork of a chain that has the
/// canonical v1.4.1 deployments, so tests run the Safe's own hashing,
/// signature checking and execution rather than a model of them.
library LibForkSafe {
    /// The canonical Safe v1.4.1 `SafeL2` singleton.
    address internal constant SAFE_L2_SINGLETON_1_4_1 = 0x29fcB43b46531BcA003ddC8FCB67FFE91900C762;

    /// The canonical Safe v1.4.1 `SafeProxyFactory`.
    SafeProxyFactory internal constant SAFE_PROXY_FACTORY_1_4_1 =
        SafeProxyFactory(0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67);

    /// A new Safe proxy with `owners` and `threshold`, no modules, no
    /// fallback handler.
    /// @param owners The owners.
    /// @param threshold The threshold.
    /// @return The Safe.
    function deploy(address[] memory owners, uint256 threshold) internal returns (Safe) {
        bytes memory setup = abi.encodeCall(
            Safe.setup, (owners, threshold, address(0), "", address(0), address(0), 0, payable(address(0)))
        );
        address proxy = address(
            SAFE_PROXY_FACTORY_1_4_1.createProxyWithNonce(
                SAFE_L2_SINGLETON_1_4_1, setup, uint256(keccak256(abi.encode(owners, threshold)))
            )
        );
        return Safe(payable(proxy));
    }
}
