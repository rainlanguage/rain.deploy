// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {RainDeployVerify} from "../../../src/abstract/RainDeployVerify.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {RainDeployVerifySnapshot} from "../../../src/abstract/RainDeployVerifySnapshot.sol";

/// @title RainDeployVerifyTest
/// @notice `RainDeployVerify` is the whole of the verification binding: a repo
/// binds this one contract and gets the chain half and the snapshot half, so a
/// check added to either reaches every consumer on a version bump with no
/// downstream edit. A half that stopped being inherited would take that
/// promise with it for every repo at once.
///
/// ## Losing a half is the one defect no other test can report
///
/// Both halves deliver their checks as test FUNCTIONS on whatever contract
/// binds them. Drop a parent and those functions are simply not there any
/// more - and a suite cannot fail on a test that no longer exists. Every
/// consumer binding goes on passing, with fewer assertions than it declares,
/// and the count is the only thing that moved. That is true of the chain half
/// on a machine with RPC credentials and true of the snapshot half everywhere,
/// so no run of any consumer's tests is evidence about it.
///
/// The inheritance is therefore asserted where it is a TYPE rather than a run.
/// The widenings below are the assertion: a contract converts to each of its
/// bases and to nothing else, so they compile while `RainDeployVerify` is the
/// union and stop compiling the moment it is not. That turns dropping a half
/// into a build failure, which is the loudest signal available for a change
/// whose whole nature is that it removes the things that would have been loud.
///
/// This contract binds neither half itself. Binding one would inherit its test
/// functions here, which is a second place they run rather than anything said
/// about the union, and binding the chain half would put an RPC endpoint per
/// supported network behind a statement about a type.
contract RainDeployVerifyTest is Test {
    /// A `RainDeployVerify` binding MUST be a `RainDeployVerifyChain` and a
    /// `RainDeployVerifySnapshot`, both at once.
    function testRainDeployVerifyIsBothHalves() external pure {
        // Never called and never deployed. The conversions are the subject, so
        // the only thing this needs of the address is that it is one value the
        // three references can be compared at.
        RainDeployVerify binding = RainDeployVerify(address(uint160(1)));

        RainDeployVerifyChain chainHalf = binding;
        RainDeployVerifySnapshot snapshotHalf = binding;

        assertEq(address(chainHalf), address(binding), "the chain half is not bound");
        assertEq(address(snapshotHalf), address(binding), "the snapshot half is not bound");
    }
}
