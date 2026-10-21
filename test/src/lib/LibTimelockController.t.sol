// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibTimelockController} from "../../../src/lib/LibTimelockController.sol";
import {BYTECODE_HASH, CREATION_CODE, RUNTIME_CODE} from "../../../src/generated/candidate/TimelockController.sol";
import {CREATION_CODE as CREATION_CODE_0_1_18} from "../../../src/generated/0_1_18/TimelockController.sol";
import {CREATION_CODE as CREATION_CODE_0_1_19} from "../../../src/generated/0_1_19/TimelockController.sol";
import {CREATION_CODE as CREATION_CODE_0_1_20} from "../../../src/generated/0_1_20/TimelockController.sol";
import {MockTimelockControllerGeneration} from "../../concrete/MockTimelockControllerGeneration.sol";
import {MockTimelockControllerImmutableGeneration} from "../../concrete/MockTimelockControllerImmutableGeneration.sol";
import {MockSnapshotDeletingCreation} from "../../concrete/MockSnapshotDeletingCreation.sol";

/// @dev The ST0x token-owner Safe on Base, the production timelock's proposer.
address constant ST0X_BASE_TOKEN_OWNER_SAFE = 0xe70d821f3462a074e63b42d0AaC6523faAe1d611;

/// @dev The ST0x governance timelock on Base
/// (https://basescan.org/address/0x48ba1371a78e6cc54157c63721756ab444510db3).
address constant ST0X_BASE_TIMELOCK = 0x48ba1371A78E6cC54157c63721756ab444510DB3;

/// @dev The ST0x token-owner Safe on Ethereum, the production timelock's proposer.
address constant ST0X_ETHEREUM_TOKEN_OWNER_SAFE = 0x3840aeDaEc8e82f79d8F6a8F6ADCa271E13E0329;

/// @dev The ST0x governance timelock on Ethereum
/// (https://etherscan.io/address/0x831e4e1bb2b9a67c00b7d17f252a18a22cd0bd2b).
address constant ST0X_ETHEREUM_TIMELOCK = 0x831E4e1bB2b9a67C00b7d17F252A18a22cd0bD2B;

/// @dev The ST0x governance timelocks' minimum delay.
uint256 constant ST0X_TIMELOCK_MIN_DELAY = 48 hours;

/// @title LibTimelockControllerTest
/// The snapshot against the dependency, the frozen generation against
/// production, the address derivation against the real Zoltu factory, and the
/// state assertion green on the role model and red on each way out of it.
contract LibTimelockControllerTest is Test {
    /// A stand-in proposer. The role model only reads its role membership.
    address constant PROPOSER = address(0x5aFe00000000000000000000000000000000aAaa);

    /// A minimum delay for the local deploys.
    uint256 constant MIN_DELAY = 2 days;

    function callAssertTimelockState(
        bytes32 bytecodeHash,
        address timelock,
        uint256 minDelay,
        address proposer,
        address[] memory cancellers
    ) external view {
        LibTimelockController.assertTimelockState(bytecodeHash, timelock, minDelay, proposer, cancellers);
    }

    function callTimelockInitCode(bytes memory creationCode, uint256 minDelay, address proposer)
        external
        pure
        returns (bytes memory)
    {
        return LibTimelockController.timelockInitCode(creationCode, minDelay, proposer);
    }

    function callExpectedTimelockAddress(bytes memory creationCode, uint256 minDelay, address proposer)
        external
        pure
        returns (address)
    {
        return LibTimelockController.expectedTimelockAddress(creationCode, minDelay, proposer);
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
        return deployZoltu(LibTimelockController.timelockInitCode(CREATION_CODE, MIN_DELAY, PROPOSER));
    }

    /// The snapshot's creation and runtime code are the dependency as the
    /// `timelock` compiler profile compiles it, and its hash is the runtime
    /// code's.
    function testSnapshotIsTheCompiledDependency() external pure {
        assertEq(keccak256(CREATION_CODE), keccak256(type(TimelockController).creationCode));
        assertEq(keccak256(RUNTIME_CODE), keccak256(type(TimelockController).runtimeCode));
        assertEq(BYTECODE_HASH, keccak256(RUNTIME_CODE));
    }

    /// `creationCode`, with the ST0x delay and token-owner Safes as proposer,
    /// MUST derive the ST0x governance timelocks.
    /// @param creationCode The timelock generation's creation code.
    function assertDerivesProductionTimelocks(bytes memory creationCode) internal pure {
        assertEq(
            LibTimelockController.expectedTimelockAddress(
                creationCode, ST0X_TIMELOCK_MIN_DELAY, ST0X_BASE_TOKEN_OWNER_SAFE
            ),
            ST0X_BASE_TIMELOCK
        );
        assertEq(
            LibTimelockController.expectedTimelockAddress(
                creationCode, ST0X_TIMELOCK_MIN_DELAY, ST0X_ETHEREUM_TOKEN_OWNER_SAFE
            ),
            ST0X_ETHEREUM_TIMELOCK
        );
    }

    /// The frozen 0_1_18 generation is the one production carries, as pinned
    /// in S01-Issuer/st0x.deploy `LibTimelockInvariants`.
    function testFrozenCodeDerivesProductionTimelocks() external pure {
        assertDerivesProductionTimelocks(CREATION_CODE_0_1_18);
    }

    /// The frozen 0_1_19 generation freezes the same generation as 0_1_18, so
    /// it derives the same production timelocks.
    function testFrozen0119CodeDerivesProductionTimelocks() external pure {
        assertDerivesProductionTimelocks(CREATION_CODE_0_1_19);
    }

    /// The frozen 0_1_20 generation freezes the same generation as 0_1_18, so
    /// it derives the same production timelocks.
    function testFrozen0120CodeDerivesProductionTimelocks() external pure {
        assertDerivesProductionTimelocks(CREATION_CODE_0_1_20);
    }

    /// A deploy with arguments other than the snapshot's reference deploy carries
    /// the recorded runtime code and hash: the runtime code does not depend on
    /// the constructor arguments.
    function testDeployCarriesRecordedRuntimeCode() external {
        address timelock = deployTimelock();
        assertEq(timelock.codehash, BYTECODE_HASH);
        assertEq(keccak256(timelock.code), keccak256(RUNTIME_CODE));
    }

    /// The derived address is where the real Zoltu factory deploys.
    function testExpectedAddressIsWhereZoltuDeploys() external {
        assertEq(deployTimelock(), LibTimelockController.expectedTimelockAddress(CREATION_CODE, MIN_DELAY, PROPOSER));
    }

    /// The generation is the init code's prefix and both other parameters are
    /// constructor arguments, so each moves the address.
    function testExpectedAddressVariesWithEachParameter() external pure {
        address base = LibTimelockController.expectedTimelockAddress(CREATION_CODE, MIN_DELAY, PROPOSER);
        assertNotEq(
            base,
            LibTimelockController.expectedTimelockAddress(
                type(MockTimelockControllerGeneration).creationCode, MIN_DELAY, PROPOSER
            )
        );
        assertNotEq(base, LibTimelockController.expectedTimelockAddress(CREATION_CODE, MIN_DELAY + 1, PROPOSER));
        assertNotEq(base, LibTimelockController.expectedTimelockAddress(CREATION_CODE, MIN_DELAY, address(0xBEEF)));
    }

    /// Each generation's init code is its own creation code with the same
    /// constructor arguments appended, and deploys at the address derived from
    /// it.
    function testEachGenerationDeploysAtItsOwnAddress() external {
        bytes memory other = type(MockTimelockControllerGeneration).creationCode;
        bytes memory args = LibTimelockController.timelockConstructorArgs(MIN_DELAY, PROPOSER);
        assertEq(
            LibTimelockController.timelockInitCode(CREATION_CODE, MIN_DELAY, PROPOSER),
            abi.encodePacked(CREATION_CODE, args)
        );
        assertEq(LibTimelockController.timelockInitCode(other, MIN_DELAY, PROPOSER), abi.encodePacked(other, args));

        address recorded = deployTimelock();
        address otherTimelock = deployZoltu(LibTimelockController.timelockInitCode(other, MIN_DELAY, PROPOSER));
        assertEq(recorded, LibTimelockController.expectedTimelockAddress(CREATION_CODE, MIN_DELAY, PROPOSER));
        assertEq(otherTimelock, LibTimelockController.expectedTimelockAddress(other, MIN_DELAY, PROPOSER));
        assertNotEq(recorded, otherTimelock);
    }

    function externalCheckTimelockGeneration(bytes memory creationCode, bytes32 bytecodeHash) external {
        LibTimelockController.checkTimelockGeneration(vm, creationCode, bytecodeHash, MIN_DELAY, PROPOSER);
    }

    /// Each generation's creation code matches its own hash and no other, and the check leaves nothing deployed.
    function testCheckTimelockGenerationMatchesOnlyItsOwnHash() external {
        bytes memory mockCode = type(MockTimelockControllerGeneration).creationCode;
        bytes32 mockHash = keccak256(type(MockTimelockControllerGeneration).runtimeCode);
        address at = LibTimelockController.expectedTimelockAddress(CREATION_CODE, MIN_DELAY, PROPOSER);
        uint64 nonce = vm.getNonce(address(this));

        this.externalCheckTimelockGeneration(CREATION_CODE, BYTECODE_HASH);
        this.externalCheckTimelockGeneration(mockCode, mockHash);
        assertEq(at.code.length, 0);
        assertEq(LibRainDeploy.ZOLTU_FACTORY.code.length, 0);
        assertEq(vm.getNonce(address(this)), nonce);
        assertEq(vm.computeCreateAddress(address(this), nonce).code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(LibTimelockController.TimelockGenerationMismatch.selector, mockHash, BYTECODE_HASH)
        );
        this.externalCheckTimelockGeneration(CREATION_CODE, mockHash);

        vm.expectRevert(
            abi.encodeWithSelector(LibTimelockController.TimelockGenerationMismatch.selector, BYTECODE_HASH, mockHash)
        );
        this.externalCheckTimelockGeneration(mockCode, BYTECODE_HASH);
    }

    /// A timelock already at the address does not change what the check derives.
    function testCheckTimelockGenerationIgnoresCodeAlreadyAtTheAddress() external {
        address at = LibTimelockController.expectedTimelockAddress(CREATION_CODE, MIN_DELAY, PROPOSER);
        vm.etch(at, type(MockTimelockControllerGeneration).runtimeCode);
        this.externalCheckTimelockGeneration(CREATION_CODE, BYTECODE_HASH);
        assertEq(at.codehash, keccak256(type(MockTimelockControllerGeneration).runtimeCode));
    }

    /// The check derives the hash from the given constructor arguments, which a generation's code can embed.
    function testCheckTimelockGenerationDeploysWithTheGivenArguments() external {
        bytes memory code = type(MockTimelockControllerImmutableGeneration).creationCode;
        bytes32 hashAtMinDelay = deployZoltu(LibTimelockController.timelockInitCode(code, MIN_DELAY, PROPOSER)).codehash;
        bytes32 hashAtOtherDelay =
            deployZoltu(LibTimelockController.timelockInitCode(code, MIN_DELAY + 1, PROPOSER)).codehash;
        assertNotEq(hashAtMinDelay, hashAtOtherDelay);

        this.externalCheckTimelockGeneration(code, hashAtMinDelay);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockGenerationMismatch.selector, hashAtOtherDelay, hashAtMinDelay
            )
        );
        this.externalCheckTimelockGeneration(code, hashAtOtherDelay);
    }

    /// A creation code that does not deploy is refused as a failed deploy.
    function testCheckTimelockGenerationRefusesCreationCodeThatDoesNotDeploy() external {
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.DeployFailed.selector, false, address(0)));
        this.externalCheckTimelockGeneration(hex"60006000fd", BYTECODE_HASH);
    }

    /// A local deploy that cannot be reverted is refused rather than left in place.
    function testCheckTimelockGenerationRefusesALocalDeployThatCannotBeReverted() external {
        uint256 checkSnapshotId = vm.snapshotState() + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockGenerationSnapshotRevertFailed.selector, checkSnapshotId
            )
        );
        this.externalCheckTimelockGeneration(type(MockSnapshotDeletingCreation).creationCode, BYTECODE_HASH);
    }

    /// A timelock passes against the generation it was deployed from and is
    /// refused by code hash against any other, whichever generation it is.
    function testAssertHoldsATimelockToItsOwnGeneration() external {
        bytes32 otherHash = keccak256(type(MockTimelockControllerGeneration).runtimeCode);
        assertNotEq(otherHash, BYTECODE_HASH);
        address recorded = deployTimelock();
        address otherTimelock = deployZoltu(
            LibTimelockController.timelockInitCode(
                type(MockTimelockControllerGeneration).creationCode, MIN_DELAY, PROPOSER
            )
        );
        assertEq(otherTimelock.codehash, otherHash);

        this.callAssertTimelockState(BYTECODE_HASH, recorded, MIN_DELAY, PROPOSER, noCancellers());
        this.callAssertTimelockState(otherHash, otherTimelock, MIN_DELAY, PROPOSER, noCancellers());

        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockCodehashMismatch.selector, recorded, otherHash, BYTECODE_HASH
            )
        );
        this.callAssertTimelockState(otherHash, recorded, MIN_DELAY, PROPOSER, noCancellers());
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockCodehashMismatch.selector, otherTimelock, BYTECODE_HASH, otherHash
            )
        );
        this.callAssertTimelockState(BYTECODE_HASH, otherTimelock, MIN_DELAY, PROPOSER, noCancellers());
    }

    /// A zero proposer is refused: nobody could ever schedule on the timelock.
    function testInitCodeRefusesZeroProposer(uint256 minDelay) external {
        vm.expectRevert(abi.encodeWithSelector(LibTimelockController.TimelockZeroProposer.selector));
        this.callTimelockInitCode(CREATION_CODE, minDelay, address(0));
    }

    /// The address derivation refuses a zero proposer, as the init code does.
    function testExpectedAddressRefusesZeroProposer(uint256 minDelay) external {
        vm.expectRevert(abi.encodeWithSelector(LibTimelockController.TimelockZeroProposer.selector));
        this.callExpectedTimelockAddress(CREATION_CODE, minDelay, address(0));
    }

    /// The init code constructs the role model: the delay, the proposer as
    /// proposer and canceller, open execution and self-administration.
    function testInitCodeConstructsTheRoleModel() external {
        TimelockController timelock = TimelockController(payable(deployTimelock()));
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        assertEq(timelock.getMinDelay(), MIN_DELAY);
        assertTrue(timelock.hasRole(proposerRole, PROPOSER));
        assertTrue(timelock.hasRole(cancellerRole, PROPOSER));
        assertTrue(timelock.hasRole(executorRole, address(0)));
        assertTrue(timelock.hasRole(adminRole, address(timelock)));
        assertFalse(timelock.hasRole(adminRole, PROPOSER));
        assertFalse(timelock.hasRole(executorRole, PROPOSER));
        assertFalse(timelock.hasRole(adminRole, LibRainDeploy.ZOLTU_FACTORY));
    }

    /// A fresh deploy is in the role model's state.
    function testAssertPassesOnFreshDeploy() external {
        LibTimelockController.assertTimelockState(BYTECODE_HASH, deployTimelock(), MIN_DELAY, PROPOSER, noCancellers());
    }

    /// Every granted canceller is required to hold the role, and passes once it
    /// does.
    function testAssertRequiresEveryCanceller() external {
        address timelock = deployTimelock();
        bytes32 cancellerRole = TimelockController(payable(timelock)).CANCELLER_ROLE();
        address[] memory cancellers = new address[](2);
        cancellers[0] = address(0xCA01);
        cancellers[1] = address(0xCA02);

        vm.prank(timelock);
        IAccessControl(timelock).grantRole(cancellerRole, cancellers[0]);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockMissingRole.selector, timelock, cancellerRole, cancellers[1]
            )
        );
        this.callAssertTimelockState(BYTECODE_HASH, timelock, MIN_DELAY, PROPOSER, cancellers);

        vm.prank(timelock);
        IAccessControl(timelock).grantRole(cancellerRole, cancellers[1]);
        this.callAssertTimelockState(BYTECODE_HASH, timelock, MIN_DELAY, PROPOSER, cancellers);
    }

    /// The first listed canceller is checked as well as the later ones.
    function testAssertRequiresTheFirstCanceller() external {
        address timelock = deployTimelock();
        bytes32 cancellerRole = TimelockController(payable(timelock)).CANCELLER_ROLE();
        address[] memory cancellers = new address[](2);
        cancellers[0] = address(0xCA01);
        cancellers[1] = address(0xCA02);

        vm.prank(timelock);
        IAccessControl(timelock).grantRole(cancellerRole, cancellers[1]);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockMissingRole.selector, timelock, cancellerRole, cancellers[0]
            )
        );
        this.callAssertTimelockState(BYTECODE_HASH, timelock, MIN_DELAY, PROPOSER, cancellers);
    }

    /// An account with no code is refused before anything is called on it.
    function testAssertRefusesNoCode() external {
        address missing = LibTimelockController.expectedTimelockAddress(CREATION_CODE, MIN_DELAY, PROPOSER);
        vm.expectRevert(abi.encodeWithSelector(LibTimelockController.TimelockNotDeployed.selector, missing));
        this.callAssertTimelockState(BYTECODE_HASH, missing, MIN_DELAY, PROPOSER, noCancellers());
    }

    /// Other code at the address is refused by the code hash.
    function testAssertRefusesOtherCode() external {
        address timelock = deployTimelock();
        vm.etch(timelock, hex"600160005260206000f3");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockCodehashMismatch.selector, timelock, BYTECODE_HASH, timelock.codehash
            )
        );
        this.callAssertTimelockState(BYTECODE_HASH, timelock, MIN_DELAY, PROPOSER, noCancellers());
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
        this.callAssertTimelockState(BYTECODE_HASH, timelock, MIN_DELAY + 1, PROPOSER, noCancellers());
    }

    /// Each required grant missing is refused with its own `(role, account)`:
    /// the proposer's proposer and canceller roles, open execution, and
    /// self-administration last, because nothing can re-grant it once gone.
    function testAssertRefusesEveryMissingRole() external {
        address timelock = deployTimelock();
        TimelockController controller = TimelockController(payable(timelock));
        bytes32 proposerRole = controller.PROPOSER_ROLE();
        bytes32 cancellerRole = controller.CANCELLER_ROLE();
        bytes32 executorRole = controller.EXECUTOR_ROLE();
        bytes32 adminRole = controller.DEFAULT_ADMIN_ROLE();
        bytes32[3] memory roles = [proposerRole, cancellerRole, executorRole];
        address[3] memory holders = [PROPOSER, PROPOSER, address(0)];
        for (uint256 i = 0; i < roles.length; i++) {
            vm.prank(timelock);
            IAccessControl(timelock).revokeRole(roles[i], holders[i]);
            vm.expectRevert(
                abi.encodeWithSelector(
                    LibTimelockController.TimelockMissingRole.selector, timelock, roles[i], holders[i]
                )
            );
            this.callAssertTimelockState(BYTECODE_HASH, timelock, MIN_DELAY, PROPOSER, noCancellers());
            vm.prank(timelock);
            IAccessControl(timelock).grantRole(roles[i], holders[i]);
            this.callAssertTimelockState(BYTECODE_HASH, timelock, MIN_DELAY, PROPOSER, noCancellers());
        }

        vm.prank(timelock);
        IAccessControl(timelock).revokeRole(adminRole, timelock);
        vm.expectRevert(
            abi.encodeWithSelector(LibTimelockController.TimelockMissingRole.selector, timelock, adminRole, timelock)
        );
        this.callAssertTimelockState(BYTECODE_HASH, timelock, MIN_DELAY, PROPOSER, noCancellers());
    }

    /// Each role that must stay closed is refused when opened to the zero
    /// address, and the state passes again once it is closed.
    function testAssertRefusesEveryOpenRole() external {
        address timelock = deployTimelock();
        TimelockController controller = TimelockController(payable(timelock));
        bytes32 proposerRole = controller.PROPOSER_ROLE();
        bytes32 cancellerRole = controller.CANCELLER_ROLE();
        bytes32 adminRole = controller.DEFAULT_ADMIN_ROLE();
        bytes32[3] memory roles = [proposerRole, cancellerRole, adminRole];
        for (uint256 i = 0; i < roles.length; i++) {
            vm.prank(timelock);
            IAccessControl(timelock).grantRole(roles[i], address(0));
            vm.expectRevert(
                abi.encodeWithSelector(
                    LibTimelockController.TimelockUnexpectedRole.selector, timelock, roles[i], address(0)
                )
            );
            this.callAssertTimelockState(BYTECODE_HASH, timelock, MIN_DELAY, PROPOSER, noCancellers());
            vm.prank(timelock);
            IAccessControl(timelock).revokeRole(roles[i], address(0));
            this.callAssertTimelockState(BYTECODE_HASH, timelock, MIN_DELAY, PROPOSER, noCancellers());
        }
    }

    /// A proposer holding root admin is refused: it could change roles without
    /// the delay. Constructed with the proposer as `admin`.
    function testAssertRefusesProposerAsAdmin() external {
        address[] memory proposers = new address[](1);
        proposers[0] = PROPOSER;
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        address timelock =
            deployZoltu(abi.encodePacked(CREATION_CODE, abi.encode(MIN_DELAY, proposers, executors, PROPOSER)));
        bytes32 adminRole = TimelockController(payable(timelock)).DEFAULT_ADMIN_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(LibTimelockController.TimelockUnexpectedRole.selector, timelock, adminRole, PROPOSER)
        );
        this.callAssertTimelockState(BYTECODE_HASH, timelock, MIN_DELAY, PROPOSER, noCancellers());
    }

    /// Open execution end to end: an account holding no role executes a matured
    /// operation and its effect lands, while that account can neither schedule
    /// nor cancel.
    function testAnyoneExecutesOnlyProposerSchedulesAndCancels() external {
        TimelockController timelock = TimelockController(payable(deployTimelock()));
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        address anon = address(0xA904);
        bytes memory data = abi.encodeCall(IAccessControl.grantRole, (cancellerRole, anon));
        bytes32 salt = keccak256("anyone-executes");
        bytes32 id = timelock.hashOperation(address(timelock), 0, data, bytes32(0), salt);

        vm.prank(anon);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, anon, proposerRole)
        );
        timelock.schedule(address(timelock), 0, data, bytes32(0), salt, MIN_DELAY);

        vm.prank(PROPOSER);
        timelock.schedule(address(timelock), 0, data, bytes32(0), salt, MIN_DELAY);

        vm.prank(anon);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, anon, cancellerRole)
        );
        timelock.cancel(id);

        vm.warp(block.timestamp + MIN_DELAY);
        vm.prank(anon);
        timelock.execute(address(timelock), 0, data, bytes32(0), salt);
        assertTrue(timelock.isOperationDone(id));
        assertTrue(timelock.hasRole(cancellerRole, anon));
    }
}
