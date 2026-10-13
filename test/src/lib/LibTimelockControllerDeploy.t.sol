// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibTimelockController} from "../../../src/lib/LibTimelockController.sol";
import {LibTimelockControllerDeploy} from "../../../src/lib/LibTimelockControllerDeploy.sol";

/// @title LibTimelockControllerDeployTest
/// The deploy step on a local chain with the real Zoltu factory etched: a fresh
/// deploy, the skip over an existing timelock, and each refusal.
contract LibTimelockControllerDeployTest is Test {
    address constant PROPOSER = address(0x5aFe00000000000000000000000000000000aAaa);
    address constant DEPLOYER = address(0xDE91010E5);
    uint256 constant MIN_DELAY = 2 days;

    function callDeployTimelock(address deployer, uint256 minDelay, address proposer, address expectedTimelock)
        external
        returns (address)
    {
        return LibTimelockControllerDeploy.deployTimelock(vm, "local", deployer, minDelay, proposer, expectedTimelock);
    }

    function expected() internal pure returns (address) {
        return LibTimelockController.expectedTimelockAddress(MIN_DELAY, PROPOSER);
    }

    /// A fresh deploy lands at the expected address in the role model's state,
    /// and the deploy key holds no role on it.
    function testFreshDeploy() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address timelock = this.callDeployTimelock(DEPLOYER, MIN_DELAY, PROPOSER, expected());
        assertEq(timelock, expected());
        LibTimelockController.assertTimelockState(timelock, MIN_DELAY, PROPOSER, new address[](0));
        bytes32[4] memory roles = [
            LibTimelockController.PROPOSER_ROLE,
            LibTimelockController.CANCELLER_ROLE,
            LibTimelockController.EXECUTOR_ROLE,
            LibTimelockController.DEFAULT_ADMIN_ROLE
        ];
        for (uint256 i = 0; i < roles.length; i++) {
            assertFalse(IAccessControl(timelock).hasRole(roles[i], DEPLOYER));
        }
    }

    /// The deploy is broadcast from `deployer`: the factory call is recorded as
    /// sent by it.
    function testFreshDeployBroadcastsFromDeployer() external {
        LibRainDeploy.etchZoltuFactory(vm);
        vm.expectCall(LibRainDeploy.ZOLTU_FACTORY, LibTimelockController.timelockInitCode(MIN_DELAY, PROPOSER));
        uint256 nonceBefore = vm.getNonce(DEPLOYER);
        this.callDeployTimelock(DEPLOYER, MIN_DELAY, PROPOSER, expected());
        assertEq(vm.getNonce(DEPLOYER), nonceBefore + 1);
    }

    /// A timelock already at the address is proven and not redeployed, so a
    /// rerun needs no factory.
    function testExistingTimelockIsSkipped() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address timelock = LibRainDeploy.deployZoltu(LibTimelockController.timelockInitCode(MIN_DELAY, PROPOSER));
        vm.etch(LibRainDeploy.ZOLTU_FACTORY, "");
        uint256 nonceBefore = vm.getNonce(DEPLOYER);
        assertEq(this.callDeployTimelock(DEPLOYER, MIN_DELAY, PROPOSER, expected()), timelock);
        assertEq(vm.getNonce(DEPLOYER), nonceBefore);
    }

    /// A timelock already at the address that has left the role model is
    /// refused, not skipped.
    function testExistingTimelockOutOfStateIsRefused() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address timelock = LibRainDeploy.deployZoltu(LibTimelockController.timelockInitCode(MIN_DELAY, PROPOSER));
        vm.prank(timelock);
        IAccessControl(timelock).grantRole(LibTimelockController.PROPOSER_ROLE, address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockUnexpectedRole.selector,
                timelock,
                LibTimelockController.PROPOSER_ROLE,
                address(0)
            )
        );
        this.callDeployTimelock(DEPLOYER, MIN_DELAY, PROPOSER, expected());
    }

    /// An expected address the parameters do not derive is refused before the
    /// chain is read, whatever is at either address.
    function testOtherExpectedAddressIsRefused() external {
        address other = LibTimelockController.expectedTimelockAddress(MIN_DELAY, address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.UnexpectedDeployedAddress.selector, other, expected()));
        this.callDeployTimelock(DEPLOYER, MIN_DELAY, PROPOSER, other);
    }

    /// The zero address as the expected address is refused like any other.
    function testZeroExpectedAddressIsRefused() external {
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.UnexpectedDeployedAddress.selector, address(0), expected())
        );
        this.callDeployTimelock(DEPLOYER, MIN_DELAY, PROPOSER, address(0));
    }

    /// A fresh deploy without the factory is refused.
    function testMissingFactoryIsRefused() external {
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.MissingDependency.selector, "local", LibRainDeploy.ZOLTU_FACTORY)
        );
        this.callDeployTimelock(DEPLOYER, MIN_DELAY, PROPOSER, expected());
    }

    /// A fresh deploy through other code at the factory address is refused.
    function testOtherFactoryCodeIsRefused() external {
        bytes memory other = hex"600160005260206000f3";
        vm.etch(LibRainDeploy.ZOLTU_FACTORY, other);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.DependencyChanged.selector,
                "local",
                LibRainDeploy.ZOLTU_FACTORY,
                LibRainDeploy.ZOLTU_FACTORY_CODEHASH,
                keccak256(other)
            )
        );
        this.callDeployTimelock(DEPLOYER, MIN_DELAY, PROPOSER, expected());
    }
}
