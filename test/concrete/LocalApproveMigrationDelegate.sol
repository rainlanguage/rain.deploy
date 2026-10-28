// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

import {ApproveMigrationDelegate} from "../../script/ApproveMigrationDelegate.sol";
import {ApproveRegistryDelegate} from "../../script/ApproveRegistryDelegate.sol";
import {LocalForkVm} from "./LocalForkVm.sol";

/// @title LocalApproveMigrationDelegate
/// @notice `ApproveMigrationDelegate` forking every network as the local EVM
/// through a `LocalForkVm`, whose broadcast is a no-op, so an approval `run()`
/// makes is signed by this contract.
contract LocalApproveMigrationDelegate is ApproveMigrationDelegate {
    /// The local fork seam.
    LocalForkVm public immutable iLocalForkVm = new LocalForkVm();

    /// @inheritdoc ApproveRegistryDelegate
    function forkVm() internal view override returns (Vm) {
        return Vm(address(iLocalForkVm));
    }

    /// The Vm `ApproveMigrationDelegate` itself forks with.
    /// @return The Vm.
    function baseForkVm() external view returns (Vm) {
        return super.forkVm();
    }

    /// Calls `run()` with this contract as `msg.sender`, the account the
    /// no-op broadcast leaves signing.
    /// @return The ids `run()` returns.
    function runAsItself() external returns (uint256[] memory) {
        return this.run();
    }
}
