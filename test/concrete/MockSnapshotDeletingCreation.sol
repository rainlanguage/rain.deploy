// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

/// @title MockSnapshotDeletingCreation
/// A creation code whose constructor deletes every state snapshot.
contract MockSnapshotDeletingCreation {
    constructor() {
        Vm(address(uint160(uint256(keccak256("hevm cheat code"))))).deleteStateSnapshots();
    }
}
