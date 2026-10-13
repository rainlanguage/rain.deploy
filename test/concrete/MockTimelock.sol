// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {ITimelockOperationState} from "../../src/lib/LibTimelockOperations.sol";

/// @title MockTimelock
/// Emits OpenZeppelin `TimelockController`'s `CallScheduled` event and answers
/// its operation-state reads from timestamps set directly, with OZ's encoding:
/// 0 unset or cancelled, 1 done, anything above pending.
contract MockTimelock is ITimelockOperationState {
    /// OpenZeppelin `TimelockController.CallScheduled`, declared as OZ declares
    /// it.
    event CallScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data,
        bytes32 predecessor,
        uint256 delay
    );

    mapping(bytes32 => uint256) internal sTimestamps;

    /// Emit one `CallScheduled`.
    function emitScheduled(
        bytes32 id,
        uint256 index,
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        uint256 delay
    ) external {
        emit CallScheduled(id, index, target, value, data, predecessor, delay);
    }

    /// Set the stored timestamp for `id`.
    function setTimestamp(bytes32 id, uint256 timestamp) external {
        sTimestamps[id] = timestamp;
    }

    /// @inheritdoc ITimelockOperationState
    function isOperationPending(bytes32 id) external view returns (bool) {
        return sTimestamps[id] > 1;
    }

    /// @inheritdoc ITimelockOperationState
    function getTimestamp(bytes32 id) external view returns (uint256) {
        return sTimestamps[id];
    }
}
