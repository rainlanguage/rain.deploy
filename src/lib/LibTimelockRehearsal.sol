// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";

/// @title LibTimelockRehearsal
/// @notice The rehearsal operation of a timelock: the one operation the
/// schedule, cancel and execute steps of a rehearsal all derive from, so their
/// operation ids cannot drift apart.
///
/// The operation is `timelock.updateDelay(minDelay)` on the timelock itself,
/// with `minDelay` the delay it already holds. Executed, it changes nothing.
/// `updateDelay` reverts unless the timelock calls it, so it can only run
/// through the full schedule, delay and execute loop. And it targets nothing
/// but the timelock, so an abandoned rehearsal touches no governed contract.
///
/// One salt is one rehearsal. `TimelockController` never forgets an executed
/// operation, so once it has executed the same `(minDelay, salt)` can never be
/// scheduled on that timelock again; `cancel` clears a pending one, which is
/// what lets a rehearsal cancel and then schedule again. Another rehearsal
/// after an execution needs another salt.
library LibTimelockRehearsal {
    /// The no-op call.
    /// @param minDelay The delay the timelock already holds.
    /// @return The `updateDelay` calldata.
    function payload(uint256 minDelay) internal pure returns (bytes memory) {
        return abi.encodeCall(TimelockController.updateDelay, (minDelay));
    }

    /// The rehearsal's operation id on `timelock`, computed as
    /// `TimelockController.hashOperation` computes it, without a call.
    /// @param timelock The timelock.
    /// @param minDelay The delay the timelock already holds.
    /// @param salt The rehearsal's salt.
    /// @return The operation id.
    function operationId(address timelock, uint256 minDelay, bytes32 salt) internal pure returns (bytes32) {
        return keccak256(abi.encode(timelock, uint256(0), payload(minDelay), bytes32(0), salt));
    }

    /// Calldata for a proposer to schedule the rehearsal with the minimum delay.
    /// @param timelock The timelock.
    /// @param minDelay The delay the timelock already holds.
    /// @param salt The rehearsal's salt.
    /// @return The `schedule` calldata.
    function scheduleCalldata(address timelock, uint256 minDelay, bytes32 salt) internal pure returns (bytes memory) {
        return
            abi.encodeCall(TimelockController.schedule, (timelock, 0, payload(minDelay), bytes32(0), salt, minDelay));
    }

    /// Calldata for a canceller to cancel the pending rehearsal.
    /// @param timelock The timelock.
    /// @param minDelay The delay the timelock already holds.
    /// @param salt The rehearsal's salt.
    /// @return The `cancel` calldata.
    function cancelCalldata(address timelock, uint256 minDelay, bytes32 salt) internal pure returns (bytes memory) {
        return abi.encodeCall(TimelockController.cancel, (operationId(timelock, minDelay, salt)));
    }
}
