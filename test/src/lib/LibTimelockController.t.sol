// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibTimelockController} from "../../../src/lib/LibTimelockController.sol";

/// @title LibTimelockControllerTest
/// The frozen creation code against the dependency and production, the address
/// derivation against the real Zoltu factory, and the state assertion green on
/// the role model and red on each way out of it.
contract LibTimelockControllerTest is Test {
    /// A stand-in proposer. The role model only reads its role membership.
    address constant PROPOSER = address(0x5aFe00000000000000000000000000000000aAaa);

    /// A minimum delay for the local deploys.
    uint256 constant MIN_DELAY = 2 days;

    function callAssertTimelockState(address timelock, uint256 minDelay, address proposer, address[] memory cancellers)
        external
        view
    {
        LibTimelockController.assertTimelockState(timelock, minDelay, proposer, cancellers);
    }

    function noCancellers() internal pure returns (address[] memory) {
        return new address[](0);
    }

    /// Deploys `initCode` through the real Zoltu factory, as a deploy does.
    function deployZoltu(bytes memory initCode) internal returns (address) {
        LibRainDeploy.etchZoltuFactory(vm);
        return LibRainDeploy.deployZoltu(initCode);
    }

    function deployTimelock() internal returns (address) {
        return deployZoltu(LibTimelockController.timelockInitCode(MIN_DELAY, PROPOSER));
    }

    /// The frozen creation code and runtime code hash are the dependency as the
    /// `timelock` compiler profile compiles it.
    function testFrozenCodeIsTheCompiledDependency() external pure {
        assertEq(
            keccak256(LibTimelockController.TIMELOCK_CREATION_CODE), keccak256(type(TimelockController).creationCode)
        );
        assertEq(LibTimelockController.TIMELOCK_RUNTIME_CODEHASH, keccak256(type(TimelockController).runtimeCode));
    }

    /// The frozen creation code is the generation production carries: with a
    /// 48 hour delay and the ST0x token-owner Safes as proposer it derives the
    /// ST0x governance timelocks deployed on Base
    /// (https://basescan.org/address/0x48ba1371a78e6cc54157c63721756ab444510db3)
    /// and Ethereum
    /// (https://etherscan.io/address/0x831e4e1bb2b9a67c00b7d17f252a18a22cd0bd2b),
    /// as pinned in S01-Issuer/st0x.deploy `LibTimelockInvariants`.
    function testFrozenCodeDerivesProductionTimelocks() external pure {
        assertEq(
            LibTimelockController.expectedTimelockAddress(48 hours, 0xe70d821f3462a074e63b42d0AaC6523faAe1d611),
            0x48ba1371A78E6cC54157c63721756ab444510DB3
        );
        assertEq(
            LibTimelockController.expectedTimelockAddress(48 hours, 0x3840aeDaEc8e82f79d8F6a8F6ADCa271E13E0329),
            0x831E4e1bB2b9a67C00b7d17F252A18a22cd0bD2B
        );
    }

    /// The runtime code hash pin is what a deploy of the frozen code carries.
    function testDeployCarriesRuntimeCodehash() external {
        assertEq(deployTimelock().codehash, LibTimelockController.TIMELOCK_RUNTIME_CODEHASH);
    }

    /// The derived address is where the real Zoltu factory deploys.
    function testExpectedAddressIsWhereZoltuDeploys() external {
        assertEq(deployTimelock(), LibTimelockController.expectedTimelockAddress(MIN_DELAY, PROPOSER));
    }

    /// Both parameters are constructor arguments, so each moves the address.
    function testExpectedAddressVariesWithEachParameter() external pure {
        address base = LibTimelockController.expectedTimelockAddress(MIN_DELAY, PROPOSER);
        assertNotEq(base, LibTimelockController.expectedTimelockAddress(MIN_DELAY + 1, PROPOSER));
        assertNotEq(base, LibTimelockController.expectedTimelockAddress(MIN_DELAY, address(0xBEEF)));
    }

    /// The init code constructs the role model: the delay, the proposer as
    /// proposer and canceller, open execution and self-administration.
    function testInitCodeConstructsTheRoleModel() external {
        TimelockController timelock = TimelockController(payable(deployTimelock()));
        assertEq(timelock.getMinDelay(), MIN_DELAY);
        assertTrue(timelock.hasRole(LibTimelockController.PROPOSER_ROLE, PROPOSER));
        assertTrue(timelock.hasRole(LibTimelockController.CANCELLER_ROLE, PROPOSER));
        assertTrue(timelock.hasRole(LibTimelockController.EXECUTOR_ROLE, address(0)));
        assertTrue(timelock.hasRole(LibTimelockController.DEFAULT_ADMIN_ROLE, address(timelock)));
        assertFalse(timelock.hasRole(LibTimelockController.DEFAULT_ADMIN_ROLE, PROPOSER));
        assertFalse(timelock.hasRole(LibTimelockController.EXECUTOR_ROLE, PROPOSER));
        assertFalse(timelock.hasRole(LibTimelockController.DEFAULT_ADMIN_ROLE, LibRainDeploy.ZOLTU_FACTORY));
    }

    /// The role constants are the ones the timelock answers with.
    function testRoleConstantsMatchTheTimelock() external {
        TimelockController timelock = TimelockController(payable(deployTimelock()));
        assertEq(LibTimelockController.PROPOSER_ROLE, timelock.PROPOSER_ROLE());
        assertEq(LibTimelockController.EXECUTOR_ROLE, timelock.EXECUTOR_ROLE());
        assertEq(LibTimelockController.CANCELLER_ROLE, timelock.CANCELLER_ROLE());
        assertEq(LibTimelockController.DEFAULT_ADMIN_ROLE, timelock.DEFAULT_ADMIN_ROLE());
    }

    /// A fresh deploy is in the role model's state.
    function testAssertPassesOnFreshDeploy() external {
        LibTimelockController.assertTimelockState(deployTimelock(), MIN_DELAY, PROPOSER, noCancellers());
    }

    /// Every granted canceller is required to hold the role, and passes once it
    /// does.
    function testAssertRequiresEveryCanceller() external {
        address timelock = deployTimelock();
        address[] memory cancellers = new address[](2);
        cancellers[0] = address(0xCA01);
        cancellers[1] = address(0xCA02);

        vm.prank(timelock);
        IAccessControl(timelock).grantRole(LibTimelockController.CANCELLER_ROLE, cancellers[0]);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockMissingRole.selector,
                timelock,
                LibTimelockController.CANCELLER_ROLE,
                cancellers[1]
            )
        );
        this.callAssertTimelockState(timelock, MIN_DELAY, PROPOSER, cancellers);

        vm.prank(timelock);
        IAccessControl(timelock).grantRole(LibTimelockController.CANCELLER_ROLE, cancellers[1]);
        this.callAssertTimelockState(timelock, MIN_DELAY, PROPOSER, cancellers);
    }

    /// An account with no code is refused before anything is called on it.
    function testAssertRefusesNoCode() external {
        address missing = LibTimelockController.expectedTimelockAddress(MIN_DELAY, PROPOSER);
        vm.expectRevert(abi.encodeWithSelector(LibTimelockController.TimelockNotDeployed.selector, missing));
        this.callAssertTimelockState(missing, MIN_DELAY, PROPOSER, noCancellers());
    }

    /// Other code at the address is refused by the code hash.
    function testAssertRefusesOtherCode() external {
        address timelock = deployTimelock();
        vm.etch(timelock, hex"600160005260206000f3");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockCodehashMismatch.selector,
                timelock,
                LibTimelockController.TIMELOCK_RUNTIME_CODEHASH,
                timelock.codehash
            )
        );
        this.callAssertTimelockState(timelock, MIN_DELAY, PROPOSER, noCancellers());
    }

    /// The delay is storage, not code, so only the delay check sees a timelock
    /// holding another one.
    function testAssertRefusesOtherDelay() external {
        address timelock = deployTimelock();
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockMinDelayMismatch.selector, timelock, MIN_DELAY + 1, MIN_DELAY
            )
        );
        this.callAssertTimelockState(timelock, MIN_DELAY + 1, PROPOSER, noCancellers());
    }

    /// Each required grant missing is refused with its own `(role, account)`:
    /// the proposer's proposer and canceller roles, open execution, and
    /// self-administration last, because nothing can re-grant it once gone.
    function testAssertRefusesEveryMissingRole() external {
        address timelock = deployTimelock();
        bytes32[3] memory roles = [
            LibTimelockController.PROPOSER_ROLE, LibTimelockController.CANCELLER_ROLE, LibTimelockController.EXECUTOR_ROLE
        ];
        address[3] memory holders = [PROPOSER, PROPOSER, address(0)];
        for (uint256 i = 0; i < roles.length; i++) {
            vm.prank(timelock);
            IAccessControl(timelock).revokeRole(roles[i], holders[i]);
            vm.expectRevert(
                abi.encodeWithSelector(LibTimelockController.TimelockMissingRole.selector, timelock, roles[i], holders[i])
            );
            this.callAssertTimelockState(timelock, MIN_DELAY, PROPOSER, noCancellers());
            vm.prank(timelock);
            IAccessControl(timelock).grantRole(roles[i], holders[i]);
            this.callAssertTimelockState(timelock, MIN_DELAY, PROPOSER, noCancellers());
        }

        vm.prank(timelock);
        IAccessControl(timelock).revokeRole(LibTimelockController.DEFAULT_ADMIN_ROLE, timelock);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockMissingRole.selector,
                timelock,
                LibTimelockController.DEFAULT_ADMIN_ROLE,
                timelock
            )
        );
        this.callAssertTimelockState(timelock, MIN_DELAY, PROPOSER, noCancellers());
    }

    /// Each role that must stay closed is refused when opened to the zero
    /// address, and the state passes again once it is closed.
    function testAssertRefusesEveryOpenRole() external {
        address timelock = deployTimelock();
        bytes32[3] memory roles = [
            LibTimelockController.PROPOSER_ROLE,
            LibTimelockController.CANCELLER_ROLE,
            LibTimelockController.DEFAULT_ADMIN_ROLE
        ];
        for (uint256 i = 0; i < roles.length; i++) {
            vm.prank(timelock);
            IAccessControl(timelock).grantRole(roles[i], address(0));
            vm.expectRevert(
                abi.encodeWithSelector(
                    LibTimelockController.TimelockUnexpectedRole.selector, timelock, roles[i], address(0)
                )
            );
            this.callAssertTimelockState(timelock, MIN_DELAY, PROPOSER, noCancellers());
            vm.prank(timelock);
            IAccessControl(timelock).revokeRole(roles[i], address(0));
            this.callAssertTimelockState(timelock, MIN_DELAY, PROPOSER, noCancellers());
        }
    }

    /// A proposer holding root admin is refused: it could change roles without
    /// the delay. Constructed with the proposer as `admin`.
    function testAssertRefusesProposerAsAdmin() external {
        address[] memory proposers = new address[](1);
        proposers[0] = PROPOSER;
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        address timelock = deployZoltu(
            abi.encodePacked(
                LibTimelockController.TIMELOCK_CREATION_CODE, abi.encode(MIN_DELAY, proposers, executors, PROPOSER)
            )
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockUnexpectedRole.selector,
                timelock,
                LibTimelockController.DEFAULT_ADMIN_ROLE,
                PROPOSER
            )
        );
        this.callAssertTimelockState(timelock, MIN_DELAY, PROPOSER, noCancellers());
    }

    /// Open execution end to end: an account holding no role executes a matured
    /// operation and its effect lands, while that account can neither schedule
    /// nor cancel.
    function testAnyoneExecutesOnlyProposerSchedulesAndCancels() external {
        TimelockController timelock = TimelockController(payable(deployTimelock()));
        address anon = address(0xA904);
        bytes memory data = abi.encodeCall(IAccessControl.grantRole, (LibTimelockController.CANCELLER_ROLE, anon));
        bytes32 salt = keccak256("anyone-executes");
        bytes32 id = timelock.hashOperation(address(timelock), 0, data, bytes32(0), salt);

        vm.prank(anon);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, anon, LibTimelockController.PROPOSER_ROLE
            )
        );
        timelock.schedule(address(timelock), 0, data, bytes32(0), salt, MIN_DELAY);

        vm.prank(PROPOSER);
        timelock.schedule(address(timelock), 0, data, bytes32(0), salt, MIN_DELAY);

        vm.prank(anon);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, anon, LibTimelockController.CANCELLER_ROLE
            )
        );
        timelock.cancel(id);

        vm.warp(block.timestamp + MIN_DELAY);
        vm.prank(anon);
        timelock.execute(address(timelock), 0, data, bytes32(0), salt);
        assertTrue(timelock.isOperationDone(id));
        assertTrue(timelock.hasRole(LibTimelockController.CANCELLER_ROLE, anon));
    }
}
