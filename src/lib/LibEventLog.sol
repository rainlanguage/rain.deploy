// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

/// @title LibEventLog
/// @notice Picks one contract's event out of the logs `vm.getRecordedLogs()`
/// returned, keyed on the emitter AND the event's signature topic.
///
/// Both keys, because either alone is a different event. Another contract
/// emitting the same signature (a nested deployer, a token it mints) is not
/// the event the caller is reading, and the same contract's other events are
/// not either; a log with no topics at all is an anonymous event and never
/// matches.
library LibEventLog {
    /// Thrown by `only` when no log matches.
    /// @param emitter The emitter searched for.
    /// @param topic0 The signature topic searched for.
    error EventNotFound(address emitter, bytes32 topic0);

    /// Thrown by `only` when more than one log matches. Reading the first or
    /// the last of them would pick one silently, so the caller that expects
    /// exactly one hears that it got several.
    /// @param emitter The emitter searched for.
    /// @param topic0 The signature topic searched for.
    /// @param count How many logs matched.
    error EventNotUnique(address emitter, bytes32 topic0, uint256 count);

    /// Every log from `emitter` whose first topic is `topic0`, in the order
    /// they were recorded.
    /// @param logs The recorded logs.
    /// @param emitter The contract the event must come from.
    /// @param topic0 The event's signature hash.
    /// @return matches The matching logs; empty when none match.
    function filter(Vm.Log[] memory logs, address emitter, bytes32 topic0)
        internal
        pure
        returns (Vm.Log[] memory matches)
    {
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (isMatch(logs[i], emitter, topic0)) {
                count++;
            }
        }
        matches = new Vm.Log[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (isMatch(logs[i], emitter, topic0)) {
                matches[j] = logs[i];
                j++;
            }
        }
    }

    /// The one log from `emitter` whose first topic is `topic0`.
    /// @param logs The recorded logs.
    /// @param emitter The contract the event must come from.
    /// @param topic0 The event's signature hash.
    /// @return log The single match.
    function only(Vm.Log[] memory logs, address emitter, bytes32 topic0) internal pure returns (Vm.Log memory log) {
        Vm.Log[] memory matches = filter(logs, emitter, topic0);
        if (matches.length == 0) {
            revert EventNotFound(emitter, topic0);
        }
        if (matches.length > 1) {
            revert EventNotUnique(emitter, topic0, matches.length);
        }
        log = matches[0];
    }

    /// Whether `log` came from `emitter` and carries `topic0` as its
    /// signature topic.
    /// @param log The log.
    /// @param emitter The contract the event must come from.
    /// @param topic0 The event's signature hash.
    /// @return Whether it matches.
    function isMatch(Vm.Log memory log, address emitter, bytes32 topic0) internal pure returns (bool) {
        return log.emitter == emitter && log.topics.length > 0 && log.topics[0] == topic0;
    }
}
