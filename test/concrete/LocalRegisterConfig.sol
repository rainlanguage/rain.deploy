// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";

import {RegisterConfig} from "../../script/RegisterConfig.sol";
import {LocalForkVm} from "./LocalForkVm.sol";

/// @title LocalRegisterConfig
/// @notice `RegisterConfig` forking every network as the local EVM through a
/// `LocalForkVm`, whose broadcast is a no-op that records the account it was
/// started from, so a bind `run()` makes is signed by this contract.
contract LocalRegisterConfig is RegisterConfig {
    /// The local fork seam.
    LocalForkVm public immutable iLocalForkVm = new LocalForkVm();

    /// @inheritdoc RegisterConfig
    function forkVm() internal view override returns (Vm) {
        return Vm(address(iLocalForkVm));
    }

    /// The Vm `RegisterConfig` itself forks with.
    /// @return The Vm.
    function baseForkVm() external view returns (Vm) {
        return super.forkVm();
    }
}
