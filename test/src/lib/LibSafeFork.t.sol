// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {LibSafeFork} from "../../../src/lib/LibSafeFork.sol";
import {SafeTx} from "../../../src/lib/LibSafeTx.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1/contracts/Safe.sol";
import {OwnerManager} from "safe-global-safe-smart-account-1.4.1/contracts/base/OwnerManager.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1/contracts/common/Enum.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibForkSafe} from "../../lib/LibForkSafe.sol";
import {MockCallRecorder} from "../../concrete/MockCallRecorder.sol";
import {MockDriftingBeacon} from "../../concrete/MockDriftingBeacon.sol";
import {MockSafe} from "../../concrete/MockSafe.sol";

/// @title LibSafeForkTest
/// @notice Runs against real Safe v1.4.1 proxies created on a Base fork, so
/// the Safe's own hashing, `checkSignatures` and MultiSend execution are the
/// oracle. `MockSafe` stands in only for outcomes a real Safe never produces.
contract LibSafeForkTest is Test {
    function externalSimulateCall(Safe safe, address target, bytes memory data) external {
        LibSafeFork.simulateCall(vm, safe, target, data);
    }

    function externalExecute(Safe safe, SafeTx memory txn) external {
        LibSafeFork.execute(vm, safe, txn);
    }

    function externalExecuteBundle(Safe safe, SafeTx[] memory txs) external {
        LibSafeFork.executeBundle(vm, safe, txs);
    }

    function externalSimulateNPlus1(Safe safe, address target, bytes memory data) external {
        LibSafeFork.simulateNPlus1(vm, safe, target, data);
    }

    function externalSimulateThresholdNPlus1(Safe safe, uint256 priorThreshold) external {
        LibSafeFork.simulateThresholdNPlus1(vm, safe, priorThreshold);
    }

    function externalSimulateBeaconNPlus1(Safe safe, UpgradeableBeacon beacon) external {
        LibSafeFork.simulateBeaconNPlus1(vm, safe, beacon);
    }

    function owners(uint256 count) internal returns (address[] memory) {
        address[] memory list = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            list[i] = makeAddr(string.concat("owner", vm.toString(i)));
        }
        return list;
    }

    function forkSafe(uint256 ownerCount, uint256 threshold) internal returns (Safe) {
        vm.createSelectFork(LibRainDeploy.BASE);
        return LibForkSafe.deploy(owners(ownerCount), threshold);
    }

    function approved(Safe safe, address owner, bytes32 hash) internal view returns (bool) {
        return safe.approvedHashes(owner, hash) == 1;
    }

    function mockSafe(MockSafe.Mode mode, uint256 threshold, bytes memory reason) internal returns (Safe) {
        return Safe(payable(address(new MockSafe(mode, owners(threshold), threshold, reason))));
    }

    /// A simulated self-call changes the Safe's state as the Safe, without
    /// consuming a nonce.
    function testSimulateCallSelf() external {
        Safe safe = forkSafe(3, 2);
        uint256 nonce = safe.nonce();
        LibSafeFork.simulateCall(vm, safe, address(safe), abi.encodeCall(OwnerManager.changeThreshold, (3)));
        assertEq(safe.getThreshold(), 3);
        assertEq(safe.nonce(), nonce);
    }

    /// A simulated external call arrives from the Safe, with its calldata.
    function testSimulateCallExternal() external {
        Safe safe = forkSafe(1, 1);
        MockCallRecorder recorder = new MockCallRecorder();
        LibSafeFork.simulateCall(vm, safe, address(recorder), hex"c0ffee");
        assertEq(recorder.callCount(), 1);
        assertEq(recorder.calls(0).caller, address(safe));
        assertEq(recorder.calls(0).data, hex"c0ffee");
    }

    /// A simulated call's revert reaches the caller unchanged.
    function testSimulateCallBubblesRevert() external {
        Safe safe = forkSafe(1, 1);
        MockCallRecorder recorder = new MockCallRecorder();
        vm.expectRevert(MockCallRecorder.Refused.selector);
        this.externalSimulateCall(safe, address(recorder), "revert");
    }

    /// `approve` has exactly the first `count` owners, in owner order, approve
    /// the hash.
    function testApprove() external {
        Safe safe = forkSafe(3, 2);
        bytes32 hash = keccak256("hash");
        address[] memory approvers = LibSafeFork.approve(vm, safe, hash, 2);
        address[] memory list = safe.getOwners();
        assertEq(approvers.length, 2);
        assertEq(approvers[0], list[0]);
        assertEq(approvers[1], list[1]);
        assertTrue(approved(safe, list[0], hash));
        assertTrue(approved(safe, list[1], hash));
        assertFalse(approved(safe, list[2], hash));
    }

    /// `execute` runs the transaction through `checkSignatures` at the live
    /// nonce: the call comes from the Safe and one nonce is consumed.
    function testExecute() external {
        Safe safe = forkSafe(3, 2);
        MockCallRecorder recorder = new MockCallRecorder();
        vm.deal(address(safe), 5);
        uint256 nonce = safe.nonce();
        LibSafeFork.execute(
            vm, safe, SafeTx({to: address(recorder), value: 5, data: hex"01", operation: Enum.Operation.Call})
        );
        assertEq(safe.nonce(), nonce + 1);
        assertEq(recorder.callCount(), 1);
        assertEq(recorder.calls(0).caller, address(safe));
        assertEq(recorder.calls(0).value, 5);
        assertEq(recorder.calls(0).data, hex"01");
    }

    /// A transaction whose inner call fails does not execute.
    function testExecuteInnerRevert() external {
        Safe safe = forkSafe(2, 2);
        MockCallRecorder recorder = new MockCallRecorder();
        vm.expectRevert(bytes("GS013"));
        this.externalExecute(
            safe, SafeTx({to: address(recorder), value: 0, data: "revert", operation: Enum.Operation.Call})
        );
    }

    /// `execute` reverts when the Safe reports failure.
    function testExecuteReportedFailure() external {
        Safe safe = mockSafe(MockSafe.Mode.ReturnFalse, 2, "");
        vm.expectRevert(abi.encodeWithSelector(LibSafeFork.ExecFailed.selector, address(safe)));
        this.externalExecute(safe, SafeTx({to: address(1), value: 0, data: "", operation: Enum.Operation.Call}));
    }

    /// A bundle runs through the real `MultiSendCallOnly` as one transaction:
    /// every entry, in order, called by the Safe with its value and data, at
    /// one nonce.
    function testExecuteBundle() external {
        Safe safe = forkSafe(3, 2);
        MockCallRecorder a = new MockCallRecorder();
        MockCallRecorder b = new MockCallRecorder();
        vm.deal(address(safe), 10);
        SafeTx[] memory txs = new SafeTx[](3);
        txs[0] = SafeTx({to: address(a), value: 3, data: hex"aa", operation: Enum.Operation.Call});
        txs[1] = SafeTx({to: address(b), value: 0, data: hex"bbbb", operation: Enum.Operation.Call});
        txs[2] = SafeTx({to: address(a), value: 7, data: hex"cc", operation: Enum.Operation.Call});
        uint256 nonce = safe.nonce();
        LibSafeFork.executeBundle(vm, safe, txs);
        assertEq(safe.nonce(), nonce + 1);
        assertEq(a.callCount(), 2);
        assertEq(b.callCount(), 1);
        assertEq(a.calls(0).caller, address(safe));
        assertEq(a.calls(0).value, 3);
        assertEq(a.calls(0).data, hex"aa");
        assertEq(b.calls(0).caller, address(safe));
        assertEq(b.calls(0).data, hex"bbbb");
        assertEq(a.calls(1).value, 7);
        assertEq(a.calls(1).data, hex"cc");
        assertEq(address(safe).balance, 0);
    }

    /// One failing entry fails the whole bundle.
    function testExecuteBundleAtomic() external {
        Safe safe = forkSafe(2, 2);
        MockCallRecorder recorder = new MockCallRecorder();
        SafeTx[] memory txs = new SafeTx[](2);
        txs[0] = SafeTx({to: address(recorder), value: 0, data: hex"aa", operation: Enum.Operation.Call});
        txs[1] = SafeTx({to: address(recorder), value: 0, data: "revert", operation: Enum.Operation.Call});
        vm.expectRevert(bytes("GS013"));
        this.externalExecuteBundle(safe, txs);
    }

    /// n+1 executes the follow-up at the full threshold, for every threshold
    /// including 1, where the undersigned attempt carries no signatures.
    function testSimulateNPlus1(uint8 ownerCount, uint8 threshold) external {
        ownerCount = uint8(bound(ownerCount, 1, 6));
        threshold = uint8(bound(threshold, 1, ownerCount));
        Safe safe = forkSafe(ownerCount, threshold);
        MockCallRecorder recorder = new MockCallRecorder();
        uint256 nonce = safe.nonce();
        LibSafeFork.simulateNPlus1(vm, safe, address(recorder), hex"5e");
        assertEq(safe.nonce(), nonce + 1, "one execution");
        assertEq(recorder.callCount(), 1);
        assertEq(recorder.calls(0).caller, address(safe));
        assertEq(recorder.calls(0).data, hex"5e");
    }

    /// A Safe that accepts an undersigned follow-up fails n+1.
    function testSimulateNPlus1UndersignedAccepted() external {
        Safe safe = mockSafe(MockSafe.Mode.AcceptAll, 2, "");
        vm.expectRevert(abi.encodeWithSelector(LibSafeFork.UndersignedAccepted.selector, address(safe), 2));
        this.externalSimulateNPlus1(safe, address(1), "");
    }

    /// An undersigned follow-up rejected for any reason but `GS020` fails n+1.
    function testSimulateNPlus1UnexpectedRevert() external {
        bytes memory reason = abi.encodeWithSignature("Error(string)", "GS026");
        Safe safe = mockSafe(MockSafe.Mode.OtherRevert, 2, reason);
        vm.expectRevert(abi.encodeWithSelector(LibSafeFork.UndersignedUnexpectedRevert.selector, reason));
        this.externalSimulateNPlus1(safe, address(1), "");
    }

    /// A fully signed follow-up the Safe reports as failed fails n+1.
    function testSimulateNPlus1ReportedFailure() external {
        Safe safe = mockSafe(MockSafe.Mode.ReturnFalse, 2, "");
        vm.expectRevert(abi.encodeWithSelector(LibSafeFork.ExecFailed.selector, address(safe)));
        this.externalSimulateNPlus1(safe, address(1), "");
    }

    /// A follow-up whose inner call fails fails n+1.
    function testSimulateNPlus1InnerRevert() external {
        Safe safe = forkSafe(2, 2);
        MockCallRecorder recorder = new MockCallRecorder();
        vm.expectRevert(bytes("GS013"));
        this.externalSimulateNPlus1(safe, address(recorder), "revert");
    }

    /// After a threshold change, n+1 proves it reversible and reverses it.
    function testSimulateThresholdNPlus1() external {
        Safe safe = forkSafe(3, 2);
        LibSafeFork.simulateCall(vm, safe, address(safe), abi.encodeCall(OwnerManager.changeThreshold, (3)));
        LibSafeFork.simulateThresholdNPlus1(vm, safe, 2);
        assertEq(safe.getThreshold(), 2);
    }

    /// A threshold the follow-up did not restore fails n+1.
    function testSimulateThresholdNPlus1NotRestored() external {
        Safe safe = mockSafe(MockSafe.Mode.Gate, 2, "");
        vm.expectRevert(abi.encodeWithSelector(LibSafeFork.ThresholdNotRestored.selector, 1, 2));
        this.externalSimulateThresholdNPlus1(safe, 1);
    }

    /// How many `Upgraded` events `beacon` emitted in `logs`.
    function upgradedCount(Vm.Log[] memory logs, address beacon) internal pure returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == beacon && logs[i].topics[0] == UpgradeableBeacon.Upgraded.selector) count++;
        }
        return count;
    }

    /// The owning Safe re-points its beacon at the same implementation through
    /// a signed execution.
    function testSimulateBeaconNPlus1() external {
        Safe safe = forkSafe(3, 2);
        address implementation = address(new MockCallRecorder());
        UpgradeableBeacon beacon = new UpgradeableBeacon(implementation, address(safe));
        vm.recordLogs();
        LibSafeFork.simulateBeaconNPlus1(vm, safe, beacon);
        assertEq(upgradedCount(vm.getRecordedLogs(), address(beacon)), 1);
        assertEq(beacon.implementation(), implementation);
    }

    /// A beacon the Safe does not own fails n+1.
    function testSimulateBeaconNPlus1NotOwner() external {
        Safe safe = forkSafe(2, 2);
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(new MockCallRecorder()), address(this));
        vm.expectRevert(bytes("GS013"));
        this.externalSimulateBeaconNPlus1(safe, beacon);
    }

    /// A beacon whose implementation moved fails n+1.
    function testSimulateBeaconNPlus1Moved() external {
        Safe safe = forkSafe(2, 2);
        address implementation = address(new MockCallRecorder());
        MockDriftingBeacon beacon = new MockDriftingBeacon(implementation, address(safe));
        vm.expectRevert(
            abi.encodeWithSelector(LibSafeFork.BeaconImplementationMoved.selector, implementation, address(beacon))
        );
        this.externalSimulateBeaconNPlus1(safe, beacon);
    }
}
