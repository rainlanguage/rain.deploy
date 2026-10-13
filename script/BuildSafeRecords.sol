// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {LibFs} from "rain-sol-codegen-0.1.39/src/lib/LibFs.sol";
import {LibCodeGen} from "rain-sol-codegen-0.1.39/src/lib/LibCodeGen.sol";
import {SafeProxyFactory} from "safe-global-safe-smart-account-1.4.1-3/contracts/proxies/SafeProxyFactory.sol";

import {LibRainDeploy} from "../src/lib/LibRainDeploy.sol";
import {LibSafe} from "../src/lib/LibSafe.sol";

/// @title BuildSafeRecords
/// @notice Generates `src/generated/safe_v1_4_1/` and
/// `src/generated/safe_v1_3_0/`: the runtime code of the canonical Safe
/// contracts `LibSafe` pins, read from a Base fork. Each record holds
/// `BYTECODE_HASH` and `RUNTIME_CODE`.
///
/// Safe compiled these contracts itself, so the chain is the only source of
/// their runtime code: a local build of the package does not reproduce the
/// bytecode. That is also why this is not part of `script/Build.sol`, which
/// runs with no RPC. `LibSafeTest` holds the committed records to the code on
/// every supported network.
///
/// A proxy's code does not depend on its singleton or its address, so the two
/// proxy records are read from proxies this script creates through each
/// factory on the fork.
///
/// Run with `forge script ./script/BuildSafeRecords.sol` and a reachable
/// `BASE_RPC_URL`.
contract BuildSafeRecords is Script {
    /// The tag directory of the v1.4.1 records.
    string constant V1_4_1_TAG = "safe_v1_4_1";

    /// The tag directory of the v1.3.0 proxy record.
    string constant V1_3_0_TAG = "safe_v1_3_0";

    /// The salt nonce of the proxies created to read proxy code from. No
    /// initializer is passed, so nothing about the proxy but its address
    /// depends on it.
    uint256 constant PROXY_SALT_NONCE = uint256(keccak256("rain.deploy.safe.record.proxy"));

    /// The licence of the Safe contracts whose code the records carry, as
    /// `safe-smart-account` v1.4.1 declares it.
    string constant SAFE_SPDX_LICENSE_IDENTIFIER = "LGPL-3.0-only";

    /// The copyright holder of the Safe contracts whose code the records carry.
    string constant SAFE_COPYRIGHT_TEXT = "Copyright (c) Safe Ecosystem Foundation";

    function run() external {
        vm.createSelectFork(LibRainDeploy.BASE);

        writeRecord(LibSafe.SAFE_V1_4_1_PROXY_FACTORY, V1_4_1_TAG, "SafeProxyFactory");
        writeRecord(LibSafe.SAFE_V1_4_1_L1_SINGLETON, V1_4_1_TAG, "Safe");
        writeRecord(LibSafe.SAFE_V1_4_1_L2_SINGLETON, V1_4_1_TAG, "SafeL2");
        writeRecord(LibSafe.SAFE_V1_4_1_TO_L2_SETUP, V1_4_1_TAG, "SafeToL2Setup");
        writeRecord(LibSafe.SAFE_V1_4_1_COMPATIBILITY_FALLBACK_HANDLER, V1_4_1_TAG, "CompatibilityFallbackHandler");
        writeRecord(LibSafe.SAFE_V1_4_1_MULTI_SEND_CALL_ONLY, V1_4_1_TAG, "MultiSendCallOnly");
        writeRecord(createProxy(LibSafe.SAFE_V1_4_1_PROXY_FACTORY), V1_4_1_TAG, "SafeProxy");
        writeRecord(createProxy(LibSafe.SAFE_V1_3_0_PROXY_FACTORY), V1_3_0_TAG, "GnosisSafeProxy");
    }

    /// A proxy `factory` creates on the v1.4.1 L1 singleton, with no
    /// initializer.
    /// @param factory The proxy factory.
    /// @return The proxy.
    function createProxy(address factory) internal returns (address) {
        address proxy = address(
            SafeProxyFactory(factory).createProxyWithNonce(LibSafe.SAFE_V1_4_1_L1_SINGLETON, "", PROXY_SALT_NONCE)
        );
        return proxy;
    }

    /// Writes `src/generated/<tag>/<contractName>.sol` from the code at
    /// `instance`.
    /// @param instance The account whose code is recorded.
    /// @param tag The record directory.
    /// @param contractName The record's file name.
    function writeRecord(address instance, string memory tag, string memory contractName) internal {
        LibFs.buildFileForTaggedContract(
            vm,
            instance,
            tag,
            contractName,
            SAFE_SPDX_LICENSE_IDENTIFIER,
            SAFE_COPYRIGHT_TEXT,
            LibCodeGen.bytesConstantString(
                vm, "/// @dev The runtime bytecode of the contract.", "RUNTIME_CODE", instance.code
            )
        );
    }
}
