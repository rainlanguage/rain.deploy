// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    EIP1167_CREATION_CODE_PREFIX,
    EIP1167_CREATION_CODE_SUFFIX,
    LibICloneableFactoryV4
} from "rain-factory-0.1.30/src/lib/LibICloneableFactoryV4.sol";
import {ICloneableFactoryV4} from "rain-factory-0.1.30/src/interface/ICloneableFactoryV4.sol";
import {Vm, VmSafe} from "forge-std-1.17.0/src/Vm.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    CLONE_ARTIFACT_PATH,
    CloneTarget,
    EIP1167_CREATION_CODE_PREFIX_LENGTH,
    LibRainDeployClone
} from "../../../src/lib/LibRainDeployClone.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {MockCloneFactory} from "../../concrete/MockCloneFactory.sol";
import {MockCloneable} from "../../concrete/MockCloneable.sol";
import {MockMispredictingCloneFactory} from "../../concrete/MockMispredictingCloneFactory.sol";
import {MockUncloneableMispredictingCloneFactory} from "../../concrete/MockUncloneableMispredictingCloneFactory.sol";

/// @title LibRainDeployCloneTest
/// Tests for `LibRainDeployClone`'s derivations and its deploy step.
contract LibRainDeployCloneTest is Test {
    /// A salt with bytes set across the whole word, so a derivation that
    /// truncated it or used only its low bytes would be caught. A small integer
    /// salt would survive both mistakes.
    bytes32 constant TEST_SALT = 0x1122334455667788990011223344556677889900112233445566778899001122;

    /// Init data that is neither empty nor a single word, so a digest that
    /// hashed a fixed length or forgot `keccak256(data)` entirely would be
    /// caught. `effectiveOpenSalt` hashes the data, so its LENGTH must matter.
    bytes constant TEST_DATA = hex"deadbeefcafe0102030405060708090a0b0c0d0e0f";

    /// A clone over a freshly deployed factory and implementation, so the
    /// derivations are checked against contracts that really exist here rather
    /// than against the fixture's Zoltu-derived addresses, which only hold code
    /// on a fork.
    /// @param factory The factory to clone through.
    /// @param implementation The implementation to clone.
    /// @return The clone declaration.
    function localClone(address factory, address implementation) internal pure returns (CloneTarget memory) {
        return CloneTarget({factory: factory, implementation: implementation, data: TEST_DATA, salt: TEST_SALT});
    }

    /// @param network The network name a refusal should carry.
    /// @param deployer The address to broadcast as.
    /// @param cloneData The `abi.encode`d `CloneTarget`.
    /// @return The address the step deployed to.
    function externalCloneDeployStep(string memory network, address deployer, bytes memory cloneData)
        external
        returns (address)
    {
        return LibRainDeployClone.cloneDeployStep(vm, network, deployer, cloneData);
    }

    /// `cloneCreationCode` MUST be the EIP-1167 standard's own bytes around the
    /// implementation address, asserted against `rain-factory`'s published
    /// prefix and suffix constants rather than against a hex literal repeated
    /// here. A literal would pass whatever this library happened to produce; the
    /// constants are what the deployed factory `CREATE2`s.
    function testCloneCreationCodeIsTheEIP1167Standard() external pure {
        bytes memory creationCode = LibRainDeployClone.cloneCreationCode(address(uint160(0xBEEF)));
        assertEq(
            creationCode,
            abi.encodePacked(EIP1167_CREATION_CODE_PREFIX, address(uint160(0xBEEF)), EIP1167_CREATION_CODE_SUFFIX)
        );
        // 20 prefix + 20 address + 15 suffix. Stated as a number as well as a
        // concatenation so a change to either constant has to be deliberate.
        assertEq(creationCode.length, 55);
    }

    /// `cloneRuntimeCode` MUST be the creation code with its deploy preamble cut
    /// off, which is what `CREATE2` leaves at the clone address.
    ///
    /// Asserted BOTH ways: as the slice, which is how the function is written,
    /// and independently as the standard's own bytes minus the ten-byte preamble.
    /// The slice alone would be a restatement of the implementation, and a wrong
    /// `EIP1167_CREATION_CODE_PREFIX_LENGTH` would satisfy it.
    function testCloneRuntimeCodeIsTheCreationCodeWithoutThePreamble() external pure {
        address implementation = address(uint160(0xBEEF));
        bytes memory creationCode = LibRainDeployClone.cloneCreationCode(implementation);
        bytes memory runtimeCode = LibRainDeployClone.cloneRuntimeCode(implementation);

        assertEq(runtimeCode.length, creationCode.length - EIP1167_CREATION_CODE_PREFIX_LENGTH);
        assertEq(runtimeCode.length, 45);

        // The independent derivation: the standard's prefix past the preamble,
        // then the address, then the shared suffix.
        bytes memory runtimePrefix =
            new bytes(EIP1167_CREATION_CODE_PREFIX.length - EIP1167_CREATION_CODE_PREFIX_LENGTH);
        for (uint256 i = 0; i < runtimePrefix.length; i++) {
            runtimePrefix[i] = EIP1167_CREATION_CODE_PREFIX[i + EIP1167_CREATION_CODE_PREFIX_LENGTH];
        }
        assertEq(runtimeCode, abi.encodePacked(runtimePrefix, implementation, EIP1167_CREATION_CODE_SUFFIX));

        // And the slice relationship, byte for byte.
        for (uint256 i = 0; i < runtimeCode.length; i++) {
            assertEq(runtimeCode[i], creationCode[i + EIP1167_CREATION_CODE_PREFIX_LENGTH]);
        }
    }

    /// The implementation address MUST be embedded in the runtime code, because
    /// that is what makes the recorded code hash say WHICH implementation a
    /// deployed clone delegates into — the claim `cloneCandidate`'s unanchorable
    /// reason makes.
    function testCloneRuntimeCodeEmbedsTheImplementation(address implementation) external pure {
        bytes memory runtimeCode = LibRainDeployClone.cloneRuntimeCode(implementation);
        bytes memory embedded = new bytes(20);
        for (uint256 i = 0; i < 20; i++) {
            embedded[i] = runtimeCode[i + (EIP1167_CREATION_CODE_PREFIX.length - EIP1167_CREATION_CODE_PREFIX_LENGTH)];
        }
        assertEq(embedded, abi.encodePacked(implementation));
    }

    /// `cloneDeployedCodehash` MUST be `keccak256` of the runtime code, and a
    /// different implementation MUST give a different hash — otherwise the
    /// recorded hash could not distinguish which implementation a clone
    /// delegates to.
    function testCloneDeployedCodehashIsKeccakOfTheRuntimeCode(address implementation, address other) external pure {
        vm.assume(implementation != other);
        assertEq(
            LibRainDeployClone.cloneDeployedCodehash(implementation),
            keccak256(LibRainDeployClone.cloneRuntimeCode(implementation))
        );
        assertNotEq(
            LibRainDeployClone.cloneDeployedCodehash(implementation), LibRainDeployClone.cloneDeployedCodehash(other)
        );
    }

    /// THE test this library exists to pass: a real factory, a real `CREATE2`, and
    /// the address, the runtime code and the code hash this package predicted
    /// without deploying anything.
    ///
    /// Every other check on a clone candidate is internal to the candidate — the
    /// recorded address is what the recorded creation code derives, the recorded
    /// hash is what it produces — so a consistent snapshot of the WRONG clone
    /// satisfies all of them. A clone has no source anchor to catch that. This is
    /// what replaces it: the EVM, not a second copy of the arithmetic, says where
    /// the clone went and what is there.
    function testCloneDerivationsMatchARealFactoryDeploy() external {
        MockCloneFactory factory = new MockCloneFactory();
        MockCloneable implementation = new MockCloneable();
        CloneTarget memory clone = localClone(address(factory), address(implementation));

        address predicted = LibRainDeployClone.cloneDeployedAddress(clone);
        assertEq(predicted.code.length, 0, "nothing at the predicted address before the deploy");

        address deployed = factory.cloneDeterministicOpenSalt(clone.implementation, clone.data, clone.salt);

        assertEq(deployed, predicted, "predicted address");
        assertEq(deployed.code, LibRainDeployClone.cloneRuntimeCode(clone.implementation), "runtime code");
        assertEq(deployed.codehash, LibRainDeployClone.cloneDeployedCodehash(clone.implementation), "code hash");

        // The clone really is a working proxy initialized with the declared
        // bytes, not merely 45 bytes at the right address. The open salt commits
        // to `data`, so a clone holding different data would be at a different
        // address — reading it back is how the test sees which one it got.
        assertTrue(MockCloneable(deployed).sInitialized());
        assertEq(MockCloneable(deployed).sInitData(), TEST_DATA);
    }

    /// The factory MUST agree with this package about where the clone goes. The
    /// same agreement `cloneDeployStep` checks per network, asserted here against
    /// a real factory so the step's guard is known to be comparing two things
    /// that CAN agree.
    function testCloneDeployedAddressMatchesTheFactoryPrediction(bytes32 salt, bytes memory data) external {
        MockCloneFactory factory = new MockCloneFactory();
        MockCloneable implementation = new MockCloneable();
        CloneTarget memory clone =
            CloneTarget({factory: address(factory), implementation: address(implementation), data: data, salt: salt});
        assertEq(
            LibRainDeployClone.cloneDeployedAddress(clone),
            factory.predictDeterministicAddressOpenSalt(address(implementation), data, salt)
        );
    }

    /// Each of the four inputs MUST move the clone address. A derivation that
    /// dropped any one of them would put two different clones at one address, and
    /// whichever was deployed second would be refused forever.
    function testCloneAddressMovesWithEveryInput(
        address factory,
        address otherFactory,
        address implementation,
        address otherImplementation,
        bytes32 salt,
        bytes32 otherSalt,
        bytes memory data,
        bytes memory otherData
    ) external pure {
        vm.assume(factory != otherFactory);
        vm.assume(implementation != otherImplementation);
        vm.assume(salt != otherSalt);
        vm.assume(keccak256(data) != keccak256(otherData));

        address base = LibRainDeployClone.cloneDeployedAddress(
            CloneTarget({factory: factory, implementation: implementation, data: data, salt: salt})
        );

        // Each variant built fresh rather than by mutating a copy: assigning one
        // memory struct to another aliases it, so a mutated "copy" would move the
        // baseline too and every assertion here would compare a value with
        // itself.
        assertNotEq(
            LibRainDeployClone.cloneDeployedAddress(
                CloneTarget({factory: otherFactory, implementation: implementation, data: data, salt: salt})
            ),
            base,
            "factory"
        );
        assertNotEq(
            LibRainDeployClone.cloneDeployedAddress(
                CloneTarget({factory: factory, implementation: otherImplementation, data: data, salt: salt})
            ),
            base,
            "implementation"
        );
        assertNotEq(
            LibRainDeployClone.cloneDeployedAddress(
                CloneTarget({factory: factory, implementation: implementation, data: data, salt: otherSalt})
            ),
            base,
            "salt"
        );
        assertNotEq(
            LibRainDeployClone.cloneDeployedAddress(
                CloneTarget({factory: factory, implementation: implementation, data: otherData, salt: salt})
            ),
            base,
            "data"
        );
    }

    /// `CLONE_ARTIFACT_PATH` MUST be shaped `<path>.sol:<Name>` so
    /// `checkedCandidateSuites` admits it, and MUST resolve to NO artifact so the
    /// unanchorable claim is true. Both halves, because either alone is useless:
    /// a path that does not qualify is refused outright, and one that resolves is
    /// refused by `CandidateSourceCompiles`.
    function testCloneArtifactPathIsQualifiedAndResolvesToNothing() external view {
        bytes memory path = bytes(CLONE_ARTIFACT_PATH);
        bool qualified = false;
        for (uint256 j = 0; j + 5 <= path.length; j++) {
            if (path[j] == "." && path[j + 1] == "s" && path[j + 2] == "o" && path[j + 3] == "l" && path[j + 4] == ":")
            {
                qualified = true;
                break;
            }
        }
        assertTrue(qualified, "CLONE_ARTIFACT_PATH must be `<path>.sol:<Name>`");

        // No repo compiles an EIP-1167 proxy, so this must not resolve. A
        // `getCode` that succeeded would mean the clone candidate was anchored to
        // some namesake artifact.
        try vm.getCode(CLONE_ARTIFACT_PATH) returns (bytes memory) {
            revert("CLONE_ARTIFACT_PATH must resolve to no artifact");
        } catch {}
    }

    /// `cloneDeployStep` MUST refuse a factory that does not predict the address
    /// this package derives, naming the network, the factory and both addresses —
    /// and MUST do it before the broadcast, because a clone at an address nobody
    /// declared cannot be taken back.
    ///
    /// The mock disagrees by ONE, the smallest representable margin, so a guard
    /// with any tolerance in it fails this test.
    function testCloneDeployStepPredictionMismatchReverts() external {
        MockMispredictingCloneFactory factory = new MockMispredictingCloneFactory();
        MockCloneable implementation = new MockCloneable();
        CloneTarget memory clone = localClone(address(factory), address(implementation));

        address expected = LibRainDeployClone.cloneDeployedAddress(clone);
        address predicted = factory.predictDeterministicAddressOpenSalt(clone.implementation, clone.data, clone.salt);
        assertEq(predicted, address(uint160(expected) + 1), "the mock must disagree by exactly one");

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployClone.CloneFactoryPredictionMismatch.selector,
                LibRainDeploy.ARBITRUM_ONE,
                address(factory),
                expected,
                predicted
            )
        );
        this.externalCloneDeployStep(LibRainDeploy.ARBITRUM_ONE, address(this), abi.encode(clone));

        // Nothing was deployed: the refusal came before the broadcast window.
        assertEq(expected.code.length, 0);
        assertEq(predicted.code.length, 0);
    }

    /// A correct factory MUST get past the prediction guard. The negative test
    /// above would pass against a guard that refused EVERY factory, so the
    /// positive case is what says the guard admits agreement.
    function testCloneDeployStepAcceptsAnAgreeingFactory() external {
        MockCloneFactory factory = new MockCloneFactory();
        MockCloneable implementation = new MockCloneable();
        CloneTarget memory clone = localClone(address(factory), address(implementation));

        address deployed = this.externalCloneDeployStep(LibRainDeploy.ARBITRUM_ONE, address(this), abi.encode(clone));
        assertEq(deployed, LibRainDeployClone.cloneDeployedAddress(clone));
        assertEq(deployed.codehash, LibRainDeployClone.cloneDeployedCodehash(clone.implementation));
    }

    /// `cloneDeployStep` MUST return the address the factory's clone call
    /// reports, not the address it predicted. The shared loop compares that
    /// return against the declared address, so a factory that predicts one
    /// address and clones to another is refused as `UnexpectedDeployedAddress`
    /// naming where the clone actually went.
    function testCloneDeployStepReturnsWhereTheFactoryCloned() external {
        MockCloneFactory factory = new MockCloneFactory();
        MockCloneable implementation = new MockCloneable();
        CloneTarget memory clone = localClone(address(factory), address(implementation));
        address elsewhere = address(uint160(LibRainDeployClone.cloneDeployedAddress(clone)) + 1);
        vm.mockCall(
            address(factory),
            abi.encodeWithSelector(ICloneableFactoryV4.cloneDeterministicOpenSalt.selector),
            abi.encode(elsewhere)
        );

        address deployed = this.externalCloneDeployStep(LibRainDeploy.ARBITRUM_ONE, address(this), abi.encode(clone));
        assertEq(deployed, elsewhere);
    }

    /// The clone call MUST be broadcast as the deployer the step is handed —
    /// the address whose key `rememberDeployer` put in the wallet. Broadcast as
    /// any other sender, a real run would sign with a key the deployer never
    /// authorised, or fail to sign at all.
    function testCloneDeployStepBroadcastsAsTheDeployer() external {
        MockCloneFactory factory = new MockCloneFactory();
        MockCloneable implementation = new MockCloneable();
        CloneTarget memory clone = localClone(address(factory), address(implementation));
        address deployer = address(0xD3910E8);

        vm.startStateDiffRecording();
        this.externalCloneDeployStep(LibRainDeploy.ARBITRUM_ONE, deployer, abi.encode(clone));
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        uint256 cloneCalls = 0;
        for (uint256 i = 0; i < accesses.length; i++) {
            if (accesses[i].account == address(factory) && accesses[i].kind == VmSafe.AccountAccessKind.Call) {
                assertEq(accesses[i].accessor, deployer, "clone call not sent by the deployer");
                cloneCalls++;
            }
        }
        assertEq(cloneCalls, 1);
    }

    /// `cloneDeployStep` MUST refuse a mispredicting factory BEFORE it opens the
    /// broadcast window. A claim about ORDER, not about which error comes back.
    ///
    /// The mismatch test above cannot make it. Its refusal reverts the whole
    /// external call, so a clone a step had already broadcast is rolled back with
    /// it and `code.length == 0` afterwards is true whether the guard ran first or
    /// last — the assertion reads as a proof of order and is not one. A factory
    /// that CANNOT clone is what makes the order observable: reaching the
    /// broadcast window is an error of its own, so the mismatch coming back
    /// instead is proof nothing was broadcast.
    ///
    /// Which matters because a clone at an address nobody declared cannot be taken
    /// back — `CREATE2` through a factory is permanent on whatever chain the
    /// dispatch reached.
    function testCloneDeployStepRefusesThePredictionBeforeBroadcasting() external {
        MockUncloneableMispredictingCloneFactory factory = new MockUncloneableMispredictingCloneFactory();
        MockCloneable implementation = new MockCloneable();
        CloneTarget memory clone = localClone(address(factory), address(implementation));

        address expected = LibRainDeployClone.cloneDeployedAddress(clone);
        address predicted = factory.predictDeterministicAddressOpenSalt(clone.implementation, clone.data, clone.salt);
        assertEq(predicted, address(uint160(expected) + 1), "the mock must disagree by exactly one");

        // Stated rather than assumed: reaching this factory's clone path is an
        // error, which is the entire mechanism of the assertion below.
        vm.expectRevert(MockUncloneableMispredictingCloneFactory.CloneWasReached.selector);
        factory.cloneDeterministicOpenSalt(clone.implementation, clone.data, clone.salt);

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployClone.CloneFactoryPredictionMismatch.selector,
                LibRainDeploy.ARBITRUM_ONE,
                address(factory),
                expected,
                predicted
            )
        );
        this.externalCloneDeployStep(LibRainDeploy.ARBITRUM_ONE, address(this), abi.encode(clone));
    }
}
