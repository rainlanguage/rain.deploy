// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {LibEventLog} from "../../../src/lib/LibEventLog.sol";

/// Emits a two-event vocabulary, and one anonymous event that carries the
/// first event's signature hash as its first topic.
contract EventLogEmitter {
    event Deployed(address indexed sender, uint256 value);
    event Other(address indexed sender, uint256 value);
    event Anonymous(uint256 value) anonymous;
    event AnonymousTopic(bytes32 indexed topic, uint256 value) anonymous;

    function deployed(uint256 value) external {
        emit Deployed(msg.sender, value);
    }

    function other(uint256 value) external {
        emit Other(msg.sender, value);
    }

    function anonymousEmpty(uint256 value) external {
        emit Anonymous(value);
    }

    function anonymousWithTopic(bytes32 topic, uint256 value) external {
        emit AnonymousTopic(topic, value);
    }
}

/// @title LibEventLogTest
/// @notice Picking one emitter's event out of logs recorded from real
/// emissions.
contract LibEventLogTest is Test {
    EventLogEmitter internal a;
    EventLogEmitter internal b;

    function setUp() external {
        a = new EventLogEmitter();
        b = new EventLogEmitter();
    }

    /// `only` reached through a call, so `vm.expectRevert` has an external
    /// call to attach to.
    function externalOnly(Vm.Log[] memory logs, address emitter, bytes32 topic0) external pure returns (Vm.Log memory) {
        return LibEventLog.only(logs, emitter, topic0);
    }

    /// Only the given emitter's logs of the given event survive, in recorded
    /// order: the same event from another emitter, another event from the same
    /// emitter, and an anonymous event are all dropped.
    function testFilterKeysOnEmitterAndTopic() external {
        vm.recordLogs();
        b.deployed(1);
        a.other(2);
        a.deployed(3);
        a.anonymousEmpty(4);
        b.deployed(5);
        a.deployed(6);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        Vm.Log[] memory matches = LibEventLog.filter(logs, address(a), EventLogEmitter.Deployed.selector);
        assertEq(matches.length, 2);
        assertEq(matches[0].emitter, address(a));
        assertEq(abi.decode(matches[0].data, (uint256)), 3);
        assertEq(abi.decode(matches[1].data, (uint256)), 6);
    }

    /// An empty log list, and a list with no match, filter to nothing.
    function testFilterNoMatch() external {
        assertEq(LibEventLog.filter(new Vm.Log[](0), address(a), EventLogEmitter.Deployed.selector).length, 0);

        vm.recordLogs();
        a.other(1);
        b.deployed(2);
        a.anonymousEmpty(3);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(LibEventLog.filter(logs, address(a), EventLogEmitter.Deployed.selector).length, 0);
    }

    /// An anonymous event whose first indexed argument happens to equal the
    /// signature hash looks identical to the real event at the log level, so
    /// it does match: the finder keys on what the log carries, not on the
    /// source it came from.
    function testAnonymousWithMatchingFirstTopicMatches() external {
        vm.recordLogs();
        a.anonymousWithTopic(EventLogEmitter.Deployed.selector, 7);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(LibEventLog.filter(logs, address(a), EventLogEmitter.Deployed.selector).length, 1);
    }

    /// `only` returns the single match.
    function testOnlyReturnsSingleMatch() external {
        vm.recordLogs();
        b.deployed(1);
        a.other(2);
        a.deployed(3);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        Vm.Log memory log = LibEventLog.only(logs, address(a), EventLogEmitter.Deployed.selector);
        assertEq(log.emitter, address(a));
        assertEq(log.topics[0], EventLogEmitter.Deployed.selector);
        assertEq(log.topics[1], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(log.data, (uint256)), 3);
    }

    /// `only` refuses no match, even when the event exists on another emitter.
    function testOnlyRevertsWhenNotFound() external {
        vm.recordLogs();
        b.deployed(1);
        a.other(2);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        vm.expectRevert(
            abi.encodeWithSelector(LibEventLog.EventNotFound.selector, address(a), EventLogEmitter.Deployed.selector)
        );
        this.externalOnly(logs, address(a), EventLogEmitter.Deployed.selector);
    }

    /// `only` refuses several matches and says how many.
    function testOnlyRevertsWhenNotUnique() external {
        vm.recordLogs();
        a.deployed(1);
        b.deployed(2);
        a.deployed(3);
        a.deployed(4);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        vm.expectRevert(
            abi.encodeWithSelector(
                LibEventLog.EventNotUnique.selector, address(a), EventLogEmitter.Deployed.selector, uint256(3)
            )
        );
        this.externalOnly(logs, address(a), EventLogEmitter.Deployed.selector);
    }

    /// `filter` agrees with a direct count over fuzzed emissions.
    function testFilterCountFuzz(uint8[] memory script) external {
        vm.assume(script.length < 32);
        uint256 expected = 0;
        vm.recordLogs();
        for (uint256 i = 0; i < script.length; i++) {
            uint8 op = script[i] % 5;
            if (op == 0) {
                a.deployed(i);
                expected++;
            } else if (op == 1) {
                b.deployed(i);
            } else if (op == 2) {
                a.other(i);
            } else if (op == 3) {
                a.anonymousEmpty(i);
            } else {
                b.other(i);
            }
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log[] memory matches = LibEventLog.filter(logs, address(a), EventLogEmitter.Deployed.selector);
        assertEq(matches.length, expected);
        for (uint256 i = 0; i < matches.length; i++) {
            assertEq(matches[i].emitter, address(a));
            assertEq(matches[i].topics[0], EventLogEmitter.Deployed.selector);
        }
    }
}
