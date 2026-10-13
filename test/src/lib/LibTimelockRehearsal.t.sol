// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibTimelockController} from "../../../src/lib/LibTimelockController.sol";
import {LibTimelockRehearsal} from "../../../src/lib/LibTimelockRehearsal.sol";

/// @title LibTimelockRehearsalTest
/// The rehearsal run through a real timelock: schedule, cancel, schedule again,
/// execute after the delay, and refusal of the same salt afterwards.
contract LibTimelockRehearsalTest is Test {
    address constant PROPOSER = address(0x5aFe00000000000000000000000000000000aAaa);
    uint256 constant MIN_DELAY = 2 days;
    bytes32 constant SALT = keccak256("rehearsal");

    function deployTimelock() internal returns (TimelockController) {
        LibRainDeploy.etchZoltuFactory(vm);
        return
            TimelockController(
                payable(LibRainDeploy.deployZoltu(LibTimelockController.timelockInitCode(MIN_DELAY, PROPOSER)))
            );
    }

    function callAs(address caller, address target, bytes memory data) internal {
        vm.prank(caller);
        (bool success, bytes memory returnData) = target.call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
    }

    /// The payload is `updateDelay` to the delay given.
    function testPayloadIsUpdateDelay() external pure {
        assertEq(LibTimelockRehearsal.payload(MIN_DELAY), abi.encodeCall(TimelockController.updateDelay, (MIN_DELAY)));
    }

    /// The operation id is the one the timelock computes, for every input.
    function testOperationIdIsTheTimelocks(address timelock, uint256 minDelay, bytes32 salt) external {
        TimelockController deployed = deployTimelock();
        assertEq(
            LibTimelockRehearsal.operationId(timelock, minDelay, salt),
            deployed.hashOperation(timelock, 0, LibTimelockRehearsal.payload(minDelay), bytes32(0), salt)
        );
    }

    /// Schedule, cancel, schedule again, execute after the delay: the delay is
    /// unchanged, the operation is done, and the same salt cannot be scheduled
    /// again.
    function testRehearsalLifecycle() external {
        TimelockController timelock = deployTimelock();
        address target = address(timelock);
        bytes32 id = LibTimelockRehearsal.operationId(target, MIN_DELAY, SALT);
        bytes memory scheduleCall = LibTimelockRehearsal.scheduleCalldata(target, MIN_DELAY, SALT);

        callAs(PROPOSER, target, scheduleCall);
        assertTrue(timelock.isOperationPending(id));
        assertEq(timelock.getTimestamp(id), block.timestamp + MIN_DELAY);

        callAs(PROPOSER, target, LibTimelockRehearsal.cancelCalldata(target, MIN_DELAY, SALT));
        assertFalse(timelock.isOperation(id));

        callAs(PROPOSER, target, scheduleCall);
        assertTrue(timelock.isOperationPending(id));
        assertFalse(timelock.isOperationReady(id));

        vm.warp(block.timestamp + MIN_DELAY);
        timelock.execute(target, 0, LibTimelockRehearsal.payload(MIN_DELAY), bytes32(0), SALT);
        assertTrue(timelock.isOperationDone(id));
        assertEq(timelock.getMinDelay(), MIN_DELAY);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                bytes32(1 << uint8(TimelockController.OperationState.Unset))
            )
        );
        callAs(PROPOSER, target, scheduleCall);
    }

    /// Another salt is another operation.
    function testSaltSeparatesOperations() external pure {
        assertNotEq(
            LibTimelockRehearsal.operationId(address(1), MIN_DELAY, SALT),
            LibTimelockRehearsal.operationId(address(1), MIN_DELAY, keccak256("another"))
        );
    }
}
