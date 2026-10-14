// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {LibRainDeploy} from "./LibRainDeploy.sol";
import {LibTimelockController} from "./LibTimelockController.sol";

/// @title LibTimelockControllerDeploy
/// @notice Deploys a `LibTimelockController` timelock on the selected fork, or
/// proves the one already there, as one step of a deploy script. A script
/// deploying to several networks creates every fork first, with
/// `LibRainDeploy.createForks`, and calls this once per selected fork; the
/// proposer is usually per chain, so each call names its own.
library LibTimelockControllerDeploy {
    /// Deploys the timelock for `(minDelay, proposer)` on the selected fork through the Zoltu
    /// factory, broadcasting as `deployer`, or skips the deploy where the timelock is already
    /// there, after holding it to `LibTimelockController.assertTimelockState` with no further
    /// cancellers.
    /// @param vm The Vm to broadcast with.
    /// @param network The selected fork's network name, for refusals to name.
    /// @param deployer The address the deploy is broadcast from.
    /// @param minDelay The minimum delay in seconds.
    /// @param proposer The sole proposer.
    /// @param expectedTimelock The address the caller expects the timelock at.
    /// @return The timelock address.
    function deployTimelock(
        Vm vm,
        string memory network,
        address deployer,
        uint256 minDelay,
        address proposer,
        address expectedTimelock
    ) internal returns (address) {
        bytes memory initCode = LibTimelockController.timelockInitCode(minDelay, proposer);
        address derived = LibRainDeploy.zoltuAddress(initCode);
        if (derived != expectedTimelock) {
            revert LibRainDeploy.UnexpectedDeployedAddress(expectedTimelock, derived);
        }

        address[] memory noCancellers = new address[](0);
        if (derived.code.length != 0) {
            LibTimelockController.assertTimelockState(derived, minDelay, proposer, noCancellers);
            console2.log(" - Timelock already deployed, skipping:", derived);
            return derived;
        }

        LibRainDeploy.checkZoltuFactory(network);

        vm.startBroadcast(deployer);
        address timelock = LibRainDeploy.deployZoltu(initCode);
        vm.stopBroadcast();
        if (timelock != derived) {
            revert LibRainDeploy.UnexpectedDeployedAddress(derived, timelock);
        }

        console2.log(" - Timelock:", timelock);
        console2.log(" - Min delay (seconds):", minDelay);
        console2.log(" - Proposer:", proposer);
        return timelock;
    }
}
