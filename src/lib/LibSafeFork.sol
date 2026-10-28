// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {Safe} from "safe-global-safe-smart-account-1.5.0/contracts/Safe.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.5.0/contracts/base/OwnerManager.sol";
import {Enum} from "safe-global-safe-smart-account-1.5.0/contracts/common/Enum.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibSafeTx, SafeTx} from "./LibSafeTx.sol";

/// @title LibSafeFork
/// @notice Runs Safe transactions on a fork the way owners would on chain,
/// with owner approvals sourced from `approveHash` under `vm.prank` instead
/// of private keys, so the Safe's real `checkSignatures` path runs. For
/// dry-running a bundle before it is signed and proving the state it leaves
/// is not a dead end.
library LibSafeFork {
    /// `execTransaction` returned false.
    /// @param safe The executing Safe.
    error ExecFailed(address safe);

    /// The n+1 follow-up was accepted with one signature fewer than the
    /// threshold.
    /// @param safe The Safe.
    /// @param threshold The Safe's threshold.
    error UndersignedAccepted(address safe, uint256 threshold);

    /// The undersigned n+1 follow-up reverted, but not with `GS020`.
    /// @param reason The revert data.
    error UndersignedUnexpectedRevert(bytes reason);

    /// The threshold n+1 follow-up did not restore the prior threshold.
    /// @param expected The prior threshold.
    /// @param actual The threshold after the follow-up.
    error ThresholdNotRestored(uint256 expected, uint256 actual);

    /// The beacon n+1 follow-up moved the beacon's implementation.
    /// @param expected The implementation before the follow-up.
    /// @param actual The implementation after it.
    error BeaconImplementationMoved(address expected, address actual);

    /// The `GS020` ("signatures data too short") revert data.
    function gs020() internal pure returns (bytes memory) {
        return abi.encodeWithSignature("Error(string)", "GS020");
    }

    /// Call `target` with `data` as `safe`, as the inner call of an executed
    /// Safe transaction would, bubbling any revert. The nonce does not move.
    /// @param vm The Vm, for `prank`.
    /// @param safe The Safe the call comes from.
    /// @param target The destination; `address(safe)` for a self-call.
    /// @param data The calldata.
    function simulateCall(Vm vm, Safe safe, address target, bytes memory data) internal {
        vm.prank(address(safe));
        // slither-disable-next-line low-level-calls
        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }

    /// Have the first `count` owners of `safe`, in its owner order, approve
    /// `safeTxHash`.
    /// @param vm The Vm, for `prank`.
    /// @param safe The Safe.
    /// @param safeTxHash The hash to approve.
    /// @param count How many owners approve.
    /// @return The approving owners.
    function approve(Vm vm, Safe safe, bytes32 safeTxHash, uint256 count) internal returns (address[] memory) {
        address[] memory owners = safe.getOwners();
        address[] memory approvers = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            approvers[i] = owners[i];
            vm.prank(owners[i]);
            safe.approveHash(safeTxHash);
        }
        return approvers;
    }

    /// `execTransaction` of `txn` with no gas refund.
    /// @param safe The executing Safe.
    /// @param txn The transaction.
    /// @param signatures The signature blob.
    /// @return Whether the Safe reports success.
    function exec(Safe safe, SafeTx memory txn, bytes memory signatures) internal returns (bool) {
        return safe.execTransaction(
            txn.to, txn.value, txn.data, txn.operation, 0, 0, 0, address(0), payable(address(0)), signatures
        );
    }

    /// Execute `txn` from `safe` at its live nonce, approved by its first
    /// `threshold` owners. Reverts `ExecFailed` if the Safe reports failure.
    /// @param vm The Vm, for `prank`.
    /// @param safe The executing Safe.
    /// @param txn The transaction.
    function execute(Vm vm, Safe safe, SafeTx memory txn) internal {
        bytes32 hash = LibSafeTx.safeTxHash(safe, txn, safe.nonce());
        address[] memory approvers = approve(vm, safe, hash, safe.getThreshold());
        if (!exec(safe, txn, LibSafeTx.approvedHashSignatures(approvers))) revert ExecFailed(address(safe));
    }

    /// Execute the bundle `txs` from `safe` as one `MultiSendCallOnly`
    /// DELEGATECALL at its live nonce, as the Safe UI does. Every inner call is
    /// made by the Safe itself.
    /// @param vm The Vm, for `prank`.
    /// @param safe The executing Safe.
    /// @param txs The bundle. Every entry MUST be a CALL.
    function executeBundle(Vm vm, Safe safe, SafeTx[] memory txs) internal {
        execute(vm, safe, LibSafeTx.multiSendTx(txs));
    }

    /// Prove `safe` can still act: a CALL of `data` to `target` at the live
    /// nonce is rejected with `GS020` when one approval short of the threshold,
    /// then executes with the full threshold. Says nothing about the call's
    /// effect, which the caller checks.
    /// @param vm The Vm, for `prank`.
    /// @param safe The Safe.
    /// @param target The follow-up's destination; `address(safe)` for a
    /// self-call.
    /// @param data The follow-up's calldata.
    function simulateNPlus1(Vm vm, Safe safe, address target, bytes memory data) internal {
        SafeTx memory followup = SafeTx({to: target, value: 0, data: data, operation: Enum.Operation.Call});
        uint256 threshold = safe.getThreshold();
        address[] memory approvers = approve(vm, safe, LibSafeTx.safeTxHash(safe, followup, safe.nonce()), threshold);

        address[] memory short = new address[](threshold - 1);
        for (uint256 i = 0; i < short.length; i++) {
            short[i] = approvers[i];
        }
        // Any return means the undersigned follow-up was accepted, whatever it
        // reports, so the value is not read.
        //slither-disable-next-line unused-return
        try safe.execTransaction(
            followup.to,
            followup.value,
            followup.data,
            followup.operation,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            LibSafeTx.approvedHashSignatures(short)
        ) returns (
            bool
        ) {
            revert UndersignedAccepted(address(safe), threshold);
        } catch (bytes memory reason) {
            if (keccak256(reason) != keccak256(gs020())) revert UndersignedUnexpectedRevert(reason);
        }

        if (!exec(safe, followup, LibSafeTx.approvedHashSignatures(approvers))) revert ExecFailed(address(safe));
    }

    /// `simulateNPlus1` with `changeThreshold(priorThreshold)` as the
    /// follow-up, after a threshold change: proves the new threshold can be
    /// reverted. Reverts `ThresholdNotRestored` unless it is.
    /// @param vm The Vm, for `prank`.
    /// @param safe The Safe.
    /// @param priorThreshold The threshold before the change.
    function simulateThresholdNPlus1(Vm vm, Safe safe, uint256 priorThreshold) internal {
        simulateNPlus1(vm, safe, address(safe), abi.encodeCall(OwnerManager.changeThreshold, (priorThreshold)));
        uint256 threshold = safe.getThreshold();
        if (threshold != priorThreshold) revert ThresholdNotRestored(priorThreshold, threshold);
    }

    /// `simulateNPlus1` with `upgradeTo(<current implementation>)` on `beacon`
    /// as the follow-up: proves `safe` can act on a beacon it owns, without
    /// moving it. Reverts `BeaconImplementationMoved` if it moved.
    /// @param vm The Vm, for `prank`.
    /// @param safe The Safe that owns `beacon`.
    /// @param beacon The beacon.
    function simulateBeaconNPlus1(Vm vm, Safe safe, UpgradeableBeacon beacon) internal {
        address implementation = beacon.implementation();
        simulateNPlus1(vm, safe, address(beacon), abi.encodeCall(UpgradeableBeacon.upgradeTo, (implementation)));
        address implementationAfter = beacon.implementation();
        if (implementationAfter != implementation) {
            revert BeaconImplementationMoved(implementation, implementationAfter);
        }
    }
}
