// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibTimelockController} from "../../../src/lib/LibTimelockController.sol";
import {LibTimelockControllerDeploy} from "../../../src/lib/LibTimelockControllerDeploy.sol";
import {BYTECODE_HASH, CREATION_CODE} from "../../../src/generated/candidate/TimelockController.sol";
import {MockTimelockControllerGeneration} from "../../concrete/MockTimelockControllerGeneration.sol";

/// @title LibTimelockControllerDeployTest
/// The deploy step on a local chain with the real Zoltu factory etched: a fresh
/// deploy, the skip over an existing timelock, and each refusal.
contract LibTimelockControllerDeployTest is Test {
    address constant PROPOSER = address(0x5aFe00000000000000000000000000000000aAaa);
    address constant DEPLOYER = address(0xDE91010E5);
    uint256 constant MIN_DELAY = 2 days;

    function callDeployTimelock(
        address deployer,
        bytes memory creationCode,
        bytes32 bytecodeHash,
        uint256 minDelay,
        address proposer,
        address expectedTimelock
    ) external returns (address) {
        return LibTimelockControllerDeploy.deployTimelock(
            vm, "local", deployer, creationCode, bytecodeHash, minDelay, proposer, expectedTimelock
        );
    }

    function expected() internal pure returns (address) {
        return LibTimelockController.expectedTimelockAddress(CREATION_CODE, MIN_DELAY, PROPOSER);
    }

    /// A fresh deploy lands at the expected address in the role model's state,
    /// and the deploy key holds no role on it.
    function testFreshDeploy() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address timelock =
            this.callDeployTimelock(DEPLOYER, CREATION_CODE, BYTECODE_HASH, MIN_DELAY, PROPOSER, expected());
        assertEq(timelock, expected());
        LibTimelockController.assertTimelockState(BYTECODE_HASH, timelock, MIN_DELAY, PROPOSER, new address[](0));
        TimelockController controller = TimelockController(payable(timelock));
        bytes32[4] memory roles = [
            controller.PROPOSER_ROLE(),
            controller.CANCELLER_ROLE(),
            controller.EXECUTOR_ROLE(),
            controller.DEFAULT_ADMIN_ROLE()
        ];
        for (uint256 i = 0; i < roles.length; i++) {
            assertFalse(IAccessControl(timelock).hasRole(roles[i], DEPLOYER));
        }
    }

    /// The deploy is broadcast from `deployer`: the factory call is recorded as
    /// sent by it.
    function testFreshDeployBroadcastsFromDeployer() external {
        LibRainDeploy.etchZoltuFactory(vm);
        vm.expectCall(
            LibRainDeploy.ZOLTU_FACTORY, LibTimelockController.timelockInitCode(CREATION_CODE, MIN_DELAY, PROPOSER)
        );
        uint256 nonceBefore = vm.getNonce(DEPLOYER);
        this.callDeployTimelock(DEPLOYER, CREATION_CODE, BYTECODE_HASH, MIN_DELAY, PROPOSER, expected());
        assertEq(vm.getNonce(DEPLOYER), nonceBefore + 1);
    }

    /// A timelock already at the address is proven and not redeployed, so a
    /// rerun needs no factory.
    function testExistingTimelockIsSkipped() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address timelock =
            LibRainDeploy.deployZoltu(LibTimelockController.timelockInitCode(CREATION_CODE, MIN_DELAY, PROPOSER));
        vm.etch(LibRainDeploy.ZOLTU_FACTORY, "");
        uint256 nonceBefore = vm.getNonce(DEPLOYER);
        assertEq(
            this.callDeployTimelock(DEPLOYER, CREATION_CODE, BYTECODE_HASH, MIN_DELAY, PROPOSER, expected()), timelock
        );
        assertEq(vm.getNonce(DEPLOYER), nonceBefore);
    }

    /// A fresh deploy deploys the generation it is given, at that generation's
    /// address.
    function testFreshDeployIsTheGivenGeneration() external {
        LibRainDeploy.etchZoltuFactory(vm);
        bytes memory creationCode = type(MockTimelockControllerGeneration).creationCode;
        bytes32 bytecodeHash = keccak256(type(MockTimelockControllerGeneration).runtimeCode);
        address derived = LibTimelockController.expectedTimelockAddress(creationCode, MIN_DELAY, PROPOSER);
        assertNotEq(derived, expected());
        address timelock = this.callDeployTimelock(DEPLOYER, creationCode, bytecodeHash, MIN_DELAY, PROPOSER, derived);
        assertEq(timelock, derived);
        assertEq(timelock.codehash, bytecodeHash);
        assertEq(expected().code.length, 0);
    }

    /// A creation code given with another generation's code hash is refused before anything is broadcast.
    function testMismatchedGenerationIsRefusedBeforeBroadcast() external {
        LibRainDeploy.etchZoltuFactory(vm);
        bytes32 otherHash = keccak256(type(MockTimelockControllerGeneration).runtimeCode);
        vm.expectRevert(
            abi.encodeWithSelector(LibTimelockController.TimelockGenerationMismatch.selector, otherHash, BYTECODE_HASH)
        );
        this.callDeployTimelock(DEPLOYER, CREATION_CODE, otherHash, MIN_DELAY, PROPOSER, expected());
    }

    /// A rerun over an already deployed timelock is refused the same way.
    function testMismatchedGenerationIsRefusedOverAnExistingTimelock() external {
        LibRainDeploy.etchZoltuFactory(vm);
        LibRainDeploy.deployZoltu(LibTimelockController.timelockInitCode(CREATION_CODE, MIN_DELAY, PROPOSER));
        bytes32 otherHash = keccak256(type(MockTimelockControllerGeneration).runtimeCode);
        vm.expectRevert(
            abi.encodeWithSelector(LibTimelockController.TimelockGenerationMismatch.selector, otherHash, BYTECODE_HASH)
        );
        this.callDeployTimelock(DEPLOYER, CREATION_CODE, otherHash, MIN_DELAY, PROPOSER, expected());
    }

    /// Other code at the timelock's address is refused, not skipped, even with a matching pair.
    function testOtherCodeAtTheAddressIsRefused() external {
        LibRainDeploy.etchZoltuFactory(vm);
        vm.etch(expected(), type(MockTimelockControllerGeneration).runtimeCode);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockCodehashMismatch.selector,
                expected(),
                BYTECODE_HASH,
                keccak256(type(MockTimelockControllerGeneration).runtimeCode)
            )
        );
        this.callDeployTimelock(DEPLOYER, CREATION_CODE, BYTECODE_HASH, MIN_DELAY, PROPOSER, expected());
    }

    /// A timelock already at the address that has left the role model is
    /// refused, not skipped.
    function testExistingTimelockOutOfStateIsRefused() external {
        LibRainDeploy.etchZoltuFactory(vm);
        address timelock =
            LibRainDeploy.deployZoltu(LibTimelockController.timelockInitCode(CREATION_CODE, MIN_DELAY, PROPOSER));
        bytes32 proposerRole = TimelockController(payable(timelock)).PROPOSER_ROLE();
        vm.prank(timelock);
        IAccessControl(timelock).grantRole(proposerRole, address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockUnexpectedRole.selector, timelock, proposerRole, address(0)
            )
        );
        this.callDeployTimelock(DEPLOYER, CREATION_CODE, BYTECODE_HASH, MIN_DELAY, PROPOSER, expected());
    }

    /// An expected address the parameters do not derive is refused before the
    /// chain is read, whatever is at either address.
    function testOtherExpectedAddressIsRefused() external {
        address other = LibTimelockController.expectedTimelockAddress(CREATION_CODE, MIN_DELAY, address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.UnexpectedDeployedAddress.selector, other, expected()));
        this.callDeployTimelock(DEPLOYER, CREATION_CODE, BYTECODE_HASH, MIN_DELAY, PROPOSER, other);
    }

    /// The zero address as the expected address is refused like any other.
    function testZeroExpectedAddressIsRefused() external {
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.UnexpectedDeployedAddress.selector, address(0), expected())
        );
        this.callDeployTimelock(DEPLOYER, CREATION_CODE, BYTECODE_HASH, MIN_DELAY, PROPOSER, address(0));
    }

    /// A zero proposer is refused with its own error, before the expected
    /// address is compared or the chain is read.
    function testZeroProposerIsRefused() external {
        LibRainDeploy.etchZoltuFactory(vm);
        vm.expectRevert(abi.encodeWithSelector(LibTimelockController.TimelockZeroProposer.selector));
        this.callDeployTimelock(DEPLOYER, CREATION_CODE, BYTECODE_HASH, MIN_DELAY, address(0), expected());
    }

    /// A fresh deploy without the factory is refused.
    function testMissingFactoryIsRefused() external {
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.MissingDependency.selector, "local", LibRainDeploy.ZOLTU_FACTORY)
        );
        this.callDeployTimelock(DEPLOYER, CREATION_CODE, BYTECODE_HASH, MIN_DELAY, PROPOSER, expected());
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
        this.callDeployTimelock(DEPLOYER, CREATION_CODE, BYTECODE_HASH, MIN_DELAY, PROPOSER, expected());
    }
}
