// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {LibRoleHolders, RoleGrant} from "../../../src/lib/LibRoleHolders.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";

/// The `AccessControl` writes the tests drive on the fork.
interface IRoleGrantor {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function grantRole(bytes32 role, address account) external;
}

/// @title LibRoleHoldersRevokedForkTest
/// @notice Enumeration over a window of a live OpenZeppelin `AccessControl` on
/// Base whose only role logs are three revokes: block 50142042, where the
/// account below lost `DEPOSIT`, `WITHDRAW` and `CERTIFY` in one transaction
/// (0x8adb9081cb4eac003f18be3ede90ca05b52725481c183b0c5edac0cc0df75984). The
/// pairs and their order are read off that transaction's receipt; `hasRole`
/// for each flips from true at 50142041 to false at 50142042.
///
/// The window starts at the revoke rather than at creation on purpose: what is
/// driven here is the replay's view of pairs it saw revoked, not the full
/// membership.
contract LibRoleHoldersRevokedForkTest is Test {
    address constant ACL = 0x315b16faa6eE413faBCa877d3851B3818369f0cD;
    address constant REVOKED_ACCOUNT = 0x1c66D6708914C40239D54919320b4C48cAE3D1A9;
    /// The account that sent the revokes, so held the roles' admin then.
    address constant ROLE_ADMIN = 0xe70d821f3462a074e63b42d0AaC6523faAe1d611;
    uint256 constant REVOKE_BLOCK = 50142042;
    uint256 constant MAX_RANGE = 200;

    function setUp() external {
        vm.createSelectFork(LibRainDeploy.BASE, REVOKE_BLOCK);
    }

    function externalHoldersOf() external view returns (RoleGrant[] memory) {
        return LibRoleHolders.holdersOf(vm, ACL, REVOKE_BLOCK, MAX_RANGE);
    }

    function testRevokedPairsReplayAsNotHeld() external view {
        (RoleGrant[] memory pairs, bool[] memory held) = LibRoleHolders.replayPairs(
            ACL, LibRoleHolders.fetchRoleLogs(vm, ACL, REVOKE_BLOCK, REVOKE_BLOCK, MAX_RANGE)
        );
        bytes32[3] memory roles = [keccak256("DEPOSIT"), keccak256("WITHDRAW"), keccak256("CERTIFY")];
        assertEq(pairs.length, 3);
        for (uint256 i = 0; i < 3; i++) {
            assertEq(pairs[i].role, roles[i]);
            assertEq(pairs[i].grantee, REVOKED_ACCOUNT);
            assertFalse(held[i]);
        }
        assertEq(LibRoleHolders.holdersOf(vm, ACL, REVOKE_BLOCK, MAX_RANGE).length, 0);
    }

    /// A grant the fetched logs do not contain, of a pair the replay saw
    /// revoked, leaves the replay denying a pair the contract holds.
    function testReplayRevokedButStateHeld() external {
        vm.prank(ROLE_ADMIN);
        IRoleGrantor(ACL).grantRole(keccak256("WITHDRAW"), REVOKED_ACCOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRoleHolders.ReplayDisagreesWithState.selector, ACL, keccak256("WITHDRAW"), REVOKED_ACCOUNT, false
            )
        );
        this.externalHoldersOf();
    }
}
