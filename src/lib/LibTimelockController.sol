// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploy} from "./LibRainDeploy.sol";

/// @dev The reads `assertTimelockState` makes of an OpenZeppelin
/// `TimelockController`, declared here rather than imported so that importing
/// this library does not pull the dependency into the importer's compilation
/// unit: `foundry.toml` restricts that source to the `timelock` profile, and
/// every source sharing a unit with it is compiled under that profile too.
interface ITimelockControllerState {
    function getMinDelay() external view returns (uint256);
    // forge-lint: disable-next-line(mixed-case-function)
    function PROPOSER_ROLE() external view returns (bytes32);
    // forge-lint: disable-next-line(mixed-case-function)
    function EXECUTOR_ROLE() external view returns (bytes32);
    // forge-lint: disable-next-line(mixed-case-function)
    function CANCELLER_ROLE() external view returns (bytes32);
    // forge-lint: disable-next-line(mixed-case-function)
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
}

/// @title LibTimelockController
/// @notice A governance timelock as one audited artifact: an UNMODIFIED
/// OpenZeppelin `TimelockController`, deployed through the Zoltu factory from
/// the creation code of one code generation, constructed into one role model,
/// and asserted against that model.
///
/// A generation is the `CREATION_CODE` and `BYTECODE_HASH` of a
/// `TimelockController` code record. `script/Build.sol` generates the candidate
/// record, `src/generated/candidate/TimelockController.sol`, from the dependency
/// compiled under the `timelock` profile in `foundry.toml`, and every release
/// freezes it as `src/generated/<tag>/TimelockController.sol`. Every derived
/// address is a function of the creation code, so a compiler or dependency
/// change that regenerates the candidate moves every address. Timelocks stay on
/// the generation they were deployed from, so the caller imports that frozen
/// `src/generated/<tag>/` record, never the candidate, and passes it to every
/// function that derives or checks code, whatever rain-deploy version it imports.
///
/// The role model `timelockInitCode` builds and `assertTimelockState` pins:
/// - The proposer holds `PROPOSER_ROLE` and `CANCELLER_ROLE` (the constructor
///   grants both to every proposer): it schedules, and can veto during the
///   delay.
/// - `EXECUTOR_ROLE` is held by `address(0)`, which `onlyRoleOrOpenRole` reads
///   as open to every caller. Once the delay has run anyone may execute, so no
///   operator can censor a matured operation. `cancel` has no open-role path,
///   so vetoing stays privileged.
/// - The timelock holds `DEFAULT_ADMIN_ROLE` on itself and the constructor's
///   `admin` is `address(0)`: every role change goes through the delay, and
///   neither the deploy key nor the factory is ever granted anything.
/// - Every further canceller is granted later, through the delay, by a
///   scheduled `grantRole(CANCELLER_ROLE, canceller)`.
///
/// The minimum delay and the proposer are the deploy's parameters, and both are
/// constructor arguments, so each pair has its own deterministic address. The
/// addresses a consumer has deployed, per chain, are that consumer's to pin.
library LibTimelockController {
    /// The account at `timelock` has no code.
    /// @param timelock The address inspected.
    error TimelockNotDeployed(address timelock);

    /// The runtime code hash at `timelock` is not the generation's `BYTECODE_HASH`.
    /// @param timelock The address inspected.
    /// @param expected The generation's `BYTECODE_HASH`.
    /// @param actual The code hash observed.
    error TimelockCodehashMismatch(address timelock, bytes32 expected, bytes32 actual);

    /// `creationCode` deploys code whose hash is not the given `bytecodeHash`.
    /// @param bytecodeHash The hash given with the creation code.
    /// @param derived The hash of the code the creation code deploys.
    error TimelockGenerationMismatch(bytes32 bytecodeHash, bytes32 derived);

    /// The local deploy behind `checkTimelockGeneration` could not be reverted.
    /// @param snapshotId The snapshot that failed to revert.
    error TimelockGenerationSnapshotRevertFailed(uint256 snapshotId);

    /// `getMinDelay()` is not the expected minimum delay.
    /// @param timelock The timelock inspected.
    /// @param expected The expected minimum delay in seconds.
    /// @param actual The minimum delay the timelock reports.
    error TimelockMinDelayMismatch(address timelock, uint256 expected, uint256 actual);

    /// `account` does not hold `role`, which the role model requires it to.
    /// @param timelock The timelock inspected.
    /// @param role The role that must be held.
    /// @param account The account that must hold it.
    error TimelockMissingRole(address timelock, bytes32 role, address account);

    /// `account` holds `role`, which the role model forbids: the zero address
    /// holding a role other than `EXECUTOR_ROLE` (that role open to everyone),
    /// or the proposer holding `DEFAULT_ADMIN_ROLE` (instant role changes,
    /// bypassing the delay).
    /// @param timelock The timelock inspected.
    /// @param role The role that must not be held.
    /// @param account The account holding it.
    error TimelockUnexpectedRole(address timelock, bytes32 role, address account);

    /// The proposer is `address(0)`. The constructor would grant
    /// `PROPOSER_ROLE` to an account no caller can act as, so nobody could
    /// ever schedule on the timelock.
    error TimelockZeroProposer();

    /// The constructor arguments of the role model: `minDelay`, `proposer` as
    /// the sole proposer (and so a canceller), `address(0)` as the sole
    /// executor so execution is open, and `address(0)` as `admin` so the
    /// timelock administers itself from birth. Reverts with
    /// `TimelockZeroProposer` when `proposer` is `address(0)`.
    /// @param minDelay The minimum delay in seconds between `schedule` and
    /// `execute`.
    /// @param proposer The sole proposer.
    /// @return The ABI-encoded constructor arguments.
    function timelockConstructorArgs(uint256 minDelay, address proposer) internal pure returns (bytes memory) {
        if (proposer == address(0)) {
            revert TimelockZeroProposer();
        }
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        return abi.encode(minDelay, proposers, executors, address(0));
    }

    /// The creation code a timelock deploy broadcasts: `creationCode` with
    /// `timelockConstructorArgs(minDelay, proposer)` appended. Reverts with
    /// `TimelockZeroProposer` when `proposer` is `address(0)`.
    /// @param creationCode The generation's `CREATION_CODE`.
    /// @param minDelay The minimum delay in seconds between `schedule` and
    /// `execute`.
    /// @param proposer The sole proposer.
    /// @return The creation code including constructor arguments.
    function timelockInitCode(bytes memory creationCode, uint256 minDelay, address proposer)
        internal
        pure
        returns (bytes memory)
    {
        return bytes.concat(creationCode, timelockConstructorArgs(minDelay, proposer));
    }

    /// The address the Zoltu factory deploys `timelockInitCode(creationCode,
    /// minDelay, proposer)` to, which is the same on every network.
    /// @param creationCode The generation's `CREATION_CODE`.
    /// @param minDelay The minimum delay in seconds.
    /// @param proposer The sole proposer.
    /// @return The deterministic timelock address.
    function expectedTimelockAddress(bytes memory creationCode, uint256 minDelay, address proposer)
        internal
        pure
        returns (address)
    {
        return LibRainDeploy.zoltuAddress(timelockInitCode(creationCode, minDelay, proposer));
    }

    /// Reverts unless `creationCode`, deployed locally with these constructor arguments, produces code
    /// hashing to `bytecodeHash`; also reverts on a zero proposer or a creation code that does not deploy.
    /// The local deploy is reverted, but a broadcast would record it, so never call this inside one.
    /// @param vm The Vm to snapshot with.
    /// @param creationCode The generation's `CREATION_CODE`.
    /// @param bytecodeHash The generation's `BYTECODE_HASH`.
    /// @param minDelay The minimum delay in seconds.
    /// @param proposer The sole proposer.
    function checkTimelockGeneration(
        Vm vm,
        bytes memory creationCode,
        bytes32 bytecodeHash,
        uint256 minDelay,
        address proposer
    ) internal {
        bytes memory initCode = timelockInitCode(creationCode, minDelay, proposer);
        uint256 snapshotId = vm.snapshotState();
        address local;
        assembly ("memory-safe") {
            local := create(0, add(initCode, 0x20), mload(initCode))
        }
        if (local == address(0)) revert LibRainDeploy.DeployFailed(false, local);
        bytes32 derived = local.codehash;
        if (!vm.revertToState(snapshotId)) {
            revert TimelockGenerationSnapshotRevertFailed(snapshotId);
        }
        if (derived != bytecodeHash) {
            revert TimelockGenerationMismatch(bytecodeHash, derived);
        }
    }

    /// Reverts with a typed error unless `timelock` is in the role model's state:
    /// code with the hash `bytecodeHash`, `getMinDelay() == minDelay`,
    /// `proposer` holding `PROPOSER_ROLE` and `CANCELLER_ROLE` but not
    /// `DEFAULT_ADMIN_ROLE`, every one of `cancellers` holding `CANCELLER_ROLE`,
    /// the timelock holding `DEFAULT_ADMIN_ROLE` on itself, `EXECUTOR_ROLE` open,
    /// and `PROPOSER_ROLE`, `CANCELLER_ROLE` and `DEFAULT_ADMIN_ROLE` closed.
    ///
    /// The forbidden holders are checked by name, not by scan: a plain
    /// `AccessControl` cannot enumerate a role's members, so an account this
    /// does not name may hold a role without it being seen here.
    /// @param bytecodeHash The `BYTECODE_HASH` of the generation `timelock` was
    /// deployed from.
    /// @param timelock The timelock to check.
    /// @param minDelay The minimum delay in seconds it must report.
    /// @param proposer The proposer it was constructed with.
    /// @param cancellers The cancellers granted beyond the proposer, each of
    /// which must hold `CANCELLER_ROLE`. Empty when none has been granted.
    function assertTimelockState(
        bytes32 bytecodeHash,
        address timelock,
        uint256 minDelay,
        address proposer,
        address[] memory cancellers
    ) internal view {
        if (timelock.code.length == 0) revert TimelockNotDeployed(timelock);
        bytes32 actualCodehash = timelock.codehash;
        if (actualCodehash != bytecodeHash) {
            revert TimelockCodehashMismatch(timelock, bytecodeHash, actualCodehash);
        }

        ITimelockControllerState controller = ITimelockControllerState(timelock);
        uint256 actualMinDelay = controller.getMinDelay();
        if (actualMinDelay != minDelay) {
            revert TimelockMinDelayMismatch(timelock, minDelay, actualMinDelay);
        }

        // The role ids are read from the instance, so the check is against the
        // ids its code enforces.
        bytes32 proposerRole = controller.PROPOSER_ROLE();
        bytes32 executorRole = controller.EXECUTOR_ROLE();
        bytes32 cancellerRole = controller.CANCELLER_ROLE();
        bytes32 adminRole = controller.DEFAULT_ADMIN_ROLE();
        IAccessControl acl = IAccessControl(timelock);

        assertHasRole(acl, proposerRole, proposer);
        assertHasRole(acl, cancellerRole, proposer);
        for (uint256 i = 0; i < cancellers.length; i++) {
            assertHasRole(acl, cancellerRole, cancellers[i]);
        }
        assertHasRole(acl, adminRole, timelock);
        assertHasRole(acl, executorRole, address(0));

        assertNotHeld(acl, adminRole, proposer);
        assertNotHeld(acl, proposerRole, address(0));
        assertNotHeld(acl, cancellerRole, address(0));
        assertNotHeld(acl, adminRole, address(0));
    }

    /// Reverts `TimelockMissingRole` unless `account` holds `role` on `acl`.
    /// @param acl The timelock.
    /// @param role The role to check.
    /// @param account The account that must hold it.
    function assertHasRole(IAccessControl acl, bytes32 role, address account) internal view {
        if (!acl.hasRole(role, account)) {
            revert TimelockMissingRole(address(acl), role, account);
        }
    }

    /// Reverts `TimelockUnexpectedRole` if `account` holds `role` on `acl`.
    /// @param acl The timelock.
    /// @param role The role to check.
    /// @param account The account that must not hold it.
    function assertNotHeld(IAccessControl acl, bytes32 role, address account) internal view {
        if (acl.hasRole(role, account)) {
            revert TimelockUnexpectedRole(address(acl), role, account);
        }
    }
}
