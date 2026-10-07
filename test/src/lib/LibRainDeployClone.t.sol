// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    EIP1167_CREATION_CODE_PREFIX,
    EIP1167_CREATION_CODE_SUFFIX,
    LibICloneableFactoryV4
} from "rain-factory-0.1.30/src/lib/LibICloneableFactoryV4.sol";
import {ICloneableFactoryV4} from "rain-factory-0.1.30/src/interface/ICloneableFactoryV4.sol";
import {DeployCandidate} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {DeployDependency, LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {
    CLONE_ARTIFACT_PATH,
    CLONE_UNANCHORABLE_REASON,
    CloneDeploy,
    EIP1167_CREATION_CODE_PREFIX_LENGTH,
    LibRainDeployClone
} from "../../../src/lib/LibRainDeployClone.sol";
import {exampleCloneFactory, exampleCloneImplementation} from "../../abstract/ExampleCloneDeploys.sol";
import {MockCloneFactory} from "../../concrete/MockCloneFactory.sol";
import {MockCloneable} from "../../concrete/MockCloneable.sol";
import {MockMispredictingCloneFactory} from "../../concrete/MockMispredictingCloneFactory.sol";

/// @title LibRainDeployCloneTest
/// Tests for `LibRainDeployClone`. External wrappers are used for library
/// functions that need `vm.expectRevert` at the correct call depth.
///
/// Most of this needs no fork, and that is deliberate rather than a convenience.
/// The claims that matter are about a DERIVATION — where a clone lands, what
/// bytes sit there, what hash they have — and a real `MockCloneFactory` doing a
/// real `CREATE2` in a local EVM settles those more strictly than a fork does,
/// because the answer comes from the EVM rather than from a second copy of the
/// same arithmetic. The fork tests are the ones that are about the LOOP — many
/// networks, the skip, the broadcast window — which is the one thing a local EVM
/// cannot show.
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
    function localClone(address factory, address implementation) internal pure returns (CloneDeploy memory) {
        return CloneDeploy({
            suite: "local-clone", factory: factory, implementation: implementation, data: TEST_DATA, salt: TEST_SALT
        });
    }

    /// Puts the fixture's factory or implementation at its DECLARED Zoltu address
    /// on the selected fork, or confirms what is already there is it.
    ///
    /// A bare `deployZoltu` cannot be used, and the reason is a real property of
    /// this fixture rather than an inconvenience. `MockCloneFactory` is pure
    /// delegation into `LibICloneableFactoryV4`, which is also exactly how the
    /// factory `rain-factory-deploy` ships is written — and this repo compiles
    /// with `bytecode_hash = "none"` and `cbor_metadata = false`, so there is
    /// nothing left in the artifact to tell two identical sources apart. The
    /// Zoltu address is a pure function of the creation code, so the mock's
    /// declared address IS the production factory's, and the production factory
    /// is already deployed there on every network `rain-factory-deploy` has
    /// reached: measured at `0x12E8…Ac40` on both arbitrum and polygon, with the
    /// same code hash the mock's runtime code has.
    ///
    /// A second `CREATE2` at an occupied address is a `CreateCollision`, which
    /// consumes every unit of gas forwarded to it and surfaces as
    /// `DeployFailed(false, address(0))`.
    ///
    /// So: deploy where absent, and where present assert the code is the code
    /// the fixture derives its clone addresses from. The assertion is the point
    /// of the branch — skipping the deploy without it would let this test predict
    /// clone addresses against a factory it never checked, which is the one thing
    /// a clone has no source anchor to catch.
    /// @param creationCode The creation code whose Zoltu address is wanted.
    /// @param runtimeCode The runtime code that creation code leaves behind.
    /// @return The declared address, now holding that runtime code.
    function zoltuDeployOrAdopt(bytes memory creationCode, bytes memory runtimeCode) internal returns (address) {
        address declared = LibRainDeploy.zoltuAddress(creationCode);
        if (declared.code.length == 0) {
            assertEq(LibRainDeploy.deployZoltu(creationCode), declared, "zoltu deployed off its derived address");
        } else {
            assertEq(declared.codehash, keccak256(runtimeCode), "something else occupies the declared address");
        }
        return declared;
    }

    /// @param network The network name a refusal should carry.
    /// @param deployer The address to broadcast as.
    /// @param cloneData The `abi.encode`d `CloneDeploy`.
    /// @return The address the step deployed to.
    function externalCloneDeployStep(string memory network, address deployer, bytes memory cloneData)
        external
        returns (address)
    {
        return LibRainDeployClone.cloneDeployStep(vm, network, deployer, cloneData);
    }

    /// @param networks The networks to deploy to.
    /// @param deployer The address to broadcast as.
    /// @param clone The clone to deploy.
    /// @param expectedAddress The declared clone address.
    /// @param expectedCodeHash The declared clone code hash.
    /// @return deployedAddress The deployed clone address.
    /// @return forkIds The forks each network was deployed on.
    function externalCloneToNetworks(
        string[] memory networks,
        address deployer,
        CloneDeploy memory clone,
        address expectedAddress,
        bytes32 expectedCodeHash
    ) external returns (address deployedAddress, uint256[] memory forkIds) {
        return LibRainDeployClone.cloneToNetworks(
            vm, networks, deployer, clone, "", expectedAddress, expectedCodeHash, new DeployDependency[](0)
        );
    }

    /// @param networks The networks to deploy to.
    /// @param deployerPrivateKey The key to broadcast as.
    /// @param clone The clone to deploy.
    /// @param expectedAddress The declared clone address.
    /// @param expectedCodeHash The declared clone code hash.
    /// @return deployedAddress The deployed clone address.
    /// @return forkIds The forks each network was deployed on.
    function externalCloneAndBroadcast(
        string[] memory networks,
        uint256 deployerPrivateKey,
        CloneDeploy memory clone,
        address expectedAddress,
        bytes32 expectedCodeHash
    ) external returns (address deployedAddress, uint256[] memory forkIds) {
        return LibRainDeployClone.cloneAndBroadcast(
            vm, networks, deployerPrivateKey, clone, "", expectedAddress, expectedCodeHash, new DeployDependency[](0)
        );
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
        CloneDeploy memory clone = localClone(address(factory), address(implementation));

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
        CloneDeploy memory clone = CloneDeploy({
            suite: "local-clone",
            factory: address(factory),
            implementation: address(implementation),
            data: data,
            salt: salt
        });
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
            CloneDeploy({suite: "base", factory: factory, implementation: implementation, data: data, salt: salt})
        );

        // Each variant built fresh rather than by mutating a copy: assigning one
        // memory struct to another aliases it, so a mutated "copy" would move the
        // baseline too and every assertion here would compare a value with
        // itself.
        assertNotEq(
            LibRainDeployClone.cloneDeployedAddress(
                CloneDeploy({
                    suite: "base", factory: otherFactory, implementation: implementation, data: data, salt: salt
                })
            ),
            base,
            "factory"
        );
        assertNotEq(
            LibRainDeployClone.cloneDeployedAddress(
                CloneDeploy({
                    suite: "base", factory: factory, implementation: otherImplementation, data: data, salt: salt
                })
            ),
            base,
            "implementation"
        );
        assertNotEq(
            LibRainDeployClone.cloneDeployedAddress(
                CloneDeploy({
                    suite: "base", factory: factory, implementation: implementation, data: data, salt: otherSalt
                })
            ),
            base,
            "salt"
        );
        assertNotEq(
            LibRainDeployClone.cloneDeployedAddress(
                CloneDeploy({
                    suite: "base", factory: factory, implementation: implementation, data: otherData, salt: salt
                })
            ),
            base,
            "data"
        );
    }

    /// The suite key MUST NOT move the address. It names the clone in the
    /// declaration; it is not part of what gets deployed, and a derivation that
    /// hashed it in would make a rename a redeploy to a new address.
    function testCloneAddressIgnoresTheSuiteKey() external pure {
        CloneDeploy memory clone = localClone(exampleCloneFactory(), exampleCloneImplementation());
        address before = LibRainDeployClone.cloneDeployedAddress(clone);
        clone.suite = "renamed-clone";
        assertEq(LibRainDeployClone.cloneDeployedAddress(clone), before);
    }

    /// `cloneCandidate` MUST derive every field of the candidate from the clone,
    /// and MUST carry the standard unanchorable reason. Each field asserted
    /// against its own derivation, because the point of the builder is that a
    /// consumer no longer writes these five by hand.
    function testCloneCandidateDerivesEveryField() external pure {
        CloneDeploy memory clone = localClone(exampleCloneFactory(), exampleCloneImplementation());
        DeployCandidate memory candidate = LibRainDeployClone.cloneCandidate(clone);

        assertEq(candidate.snapshot.suite, clone.suite);
        assertEq(candidate.snapshot.creationCode, LibRainDeployClone.cloneCreationCode(clone.implementation));
        assertEq(candidate.snapshot.storedDeployedAddress, LibRainDeployClone.cloneDeployedAddress(clone));
        assertEq(candidate.snapshot.storedBytecodeHash, LibRainDeployClone.cloneDeployedCodehash(clone.implementation));
        assertEq(candidate.snapshot.storedRuntimeCode, LibRainDeployClone.cloneRuntimeCode(clone.implementation));
        assertEq(candidate.snapshot.artifactPath, CLONE_ARTIFACT_PATH);
        assertEq(candidate.snapshot.dependencies.length, 0);
        assertEq(candidate.unanchorableReason, CLONE_UNANCHORABLE_REASON);

        // The reason has to be NON-empty: an empty one is what says a candidate
        // IS anchorable, which would send the source anchor looking for an
        // artifact that cannot exist.
        assertNotEq(bytes(candidate.unanchorableReason).length, 0);
    }

    /// The recorded code hash MUST be the hash of the recorded runtime code, and
    /// the recorded address MUST be where the recorded creation code lands. The
    /// candidate's internal consistency, which the verification abstracts assume.
    function testCloneCandidateIsInternallyConsistent() external {
        MockCloneFactory factory = new MockCloneFactory();
        MockCloneable implementation = new MockCloneable();
        CloneDeploy memory clone = localClone(address(factory), address(implementation));
        DeployCandidate memory candidate = LibRainDeployClone.cloneCandidate(clone);

        assertEq(candidate.snapshot.storedBytecodeHash, keccak256(candidate.snapshot.storedRuntimeCode));
        address deployed = factory.cloneDeterministicOpenSalt(clone.implementation, clone.data, clone.salt);
        assertEq(deployed, candidate.snapshot.storedDeployedAddress);
        assertEq(deployed.codehash, candidate.snapshot.storedBytecodeHash);
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

    /// `cloneDeployStep` MUST refuse a network whose clone factory has no code,
    /// naming the network and the factory, BEFORE it broadcasts anything.
    function testCloneDeployStepMissingFactoryReverts() external {
        MockCloneable implementation = new MockCloneable();
        // An address with no code, which is what a factory not yet deployed to a
        // network looks like.
        CloneDeploy memory clone = localClone(address(uint160(0xF00D)), address(implementation));
        assertEq(clone.factory.code.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.MissingDependency.selector, LibRainDeploy.ARBITRUM_ONE, clone.factory)
        );
        this.externalCloneDeployStep(LibRainDeploy.ARBITRUM_ONE, address(this), abi.encode(clone));
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
        CloneDeploy memory clone = localClone(address(factory), address(implementation));

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
        CloneDeploy memory clone = localClone(address(factory), address(implementation));

        address deployed = this.externalCloneDeployStep(LibRainDeploy.ARBITRUM_ONE, address(this), abi.encode(clone));
        assertEq(deployed, LibRainDeployClone.cloneDeployedAddress(clone));
        assertEq(deployed.codehash, LibRainDeployClone.cloneDeployedCodehash(clone.implementation));
    }

    /// `cloneToNetworks` MUST refuse an empty network list rather than report a
    /// successful deploy to nowhere. Checked before any fork, so no RPC is
    /// touched.
    function testCloneToNetworksNoNetworksReverts() external {
        CloneDeploy memory clone = localClone(exampleCloneFactory(), exampleCloneImplementation());
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalCloneToNetworks(
            new string[](0), address(this), clone, LibRainDeployClone.cloneDeployedAddress(clone), bytes32(0)
        );
    }

    /// `cloneAndBroadcast` MUST make the same refusal, and MUST make it before
    /// remembering the key: an empty list is a misconfiguration, not a deploy.
    function testCloneAndBroadcastNoNetworksReverts() external {
        CloneDeploy memory clone = localClone(exampleCloneFactory(), exampleCloneImplementation());
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalCloneAndBroadcast(
            new string[](0), 1, clone, LibRainDeployClone.cloneDeployedAddress(clone), bytes32(0)
        );
    }

    /// `cloneToNetworks` MUST refuse a declared address that is not the one the
    /// clone derives, BEFORE any network is forked.
    ///
    /// This is the guard that stops a stale pin passing silently. Without it, a
    /// network already holding something else at the declared address takes the
    /// skip branch and the run reports success having deployed nothing. That it
    /// reverts here with no RPC configured is itself the proof that it runs
    /// before `createForks` — a guard inside the loop could not.
    function testCloneToNetworksStaleDeclaredAddressReverts() external {
        CloneDeploy memory clone = localClone(exampleCloneFactory(), exampleCloneImplementation());
        address derived = LibRainDeployClone.cloneDeployedAddress(clone);
        address stale = address(uint160(derived) + 1);

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.UnexpectedDeployedAddress.selector, stale, derived));
        this.externalCloneToNetworks(networks, address(this), clone, stale, bytes32(0));
    }

    /// The same guard on `cloneAndBroadcast`, which is the entry point a
    /// broadcast script actually calls.
    function testCloneAndBroadcastStaleDeclaredAddressReverts() external {
        CloneDeploy memory clone = localClone(exampleCloneFactory(), exampleCloneImplementation());
        address derived = LibRainDeployClone.cloneDeployedAddress(clone);
        address stale = address(uint160(derived) + 1);

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.UnexpectedDeployedAddress.selector, stale, derived));
        this.externalCloneAndBroadcast(networks, 1, clone, stale, bytes32(0));
    }

    /// `cloneToNetworks` MUST deploy the clone on a real network, and a RERUN
    /// MUST be a clean no-op that returns the same address.
    ///
    /// The idempotence the issue asks for: a re-dispatch after a partial rollout
    /// fills in only the networks still missing the clone. The factory and the
    /// implementation are deployed through ZOLTU so they land at the addresses
    /// the declaration derives, and all three are `makePersistent`-ed because
    /// `deployStepToNetworks` creates its OWN forks — without that, the fork the
    /// loop makes for itself would not have them.
    function testCloneToNetworksDeploysThenSkipsOnRerun() external {
        vm.makePersistent(address(this));
        vm.createSelectFork(LibRainDeploy.ARBITRUM_ONE);

        address factory = zoltuDeployOrAdopt(type(MockCloneFactory).creationCode, type(MockCloneFactory).runtimeCode);
        assertEq(factory, exampleCloneFactory(), "factory at its declared address");
        vm.makePersistent(factory);
        address implementation = zoltuDeployOrAdopt(type(MockCloneable).creationCode, type(MockCloneable).runtimeCode);
        assertEq(implementation, exampleCloneImplementation(), "implementation at its declared address");
        vm.makePersistent(implementation);

        CloneDeploy memory clone = localClone(factory, implementation);
        address expected = LibRainDeployClone.cloneDeployedAddress(clone);
        bytes32 expectedCodeHash = LibRainDeployClone.cloneDeployedCodehash(implementation);

        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;

        // The DEPLOY half of the claim has to be unconditional. A clone already
        // at the expected address would send both calls down the skip branch and
        // the test would pass having deployed nothing, measuring only that a
        // no-op is a no-op.
        assertEq(expected.code.length, 0, "the clone must not already be deployed");

        (address deployed,) = this.externalCloneToNetworks(networks, address(this), clone, expected, expectedCodeHash);
        assertEq(deployed, expected);
        assertEq(deployed.codehash, expectedCodeHash);
        assertEq(deployed.code, LibRainDeployClone.cloneRuntimeCode(implementation));

        // The rerun. The clone is already there, so the loop skips it — which is
        // the only reason a second run does not revert `CloneAddressOccupied`
        // out of the factory.
        vm.makePersistent(deployed);
        (address again,) = this.externalCloneToNetworks(networks, address(this), clone, expected, expectedCodeHash);
        assertEq(again, expected);
        assertEq(again.codehash, expectedCodeHash);
    }

    /// `cloneAndBroadcast` MUST put the clone at the same address on EVERY
    /// network in the list, which is the property the whole package exists for.
    ///
    /// Two networks, not one: a loop that stopped after the first would pass a
    /// single-network test, and "the same address on every network" is not a
    /// claim one network can support.
    function testCloneAndBroadcastReachesEveryNetwork() external {
        vm.makePersistent(address(this));

        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;

        CloneDeploy memory clone = localClone(exampleCloneFactory(), exampleCloneImplementation());
        address expected = LibRainDeployClone.cloneDeployedAddress(clone);
        bytes32 expectedCodeHash = LibRainDeployClone.cloneDeployedCodehash(exampleCloneImplementation());

        // The factory and the implementation have to be on BOTH, at the same
        // addresses, which is exactly the precondition `ICloneableFactoryV4`
        // names for a clone to be cross-network deterministic.
        for (uint256 i = 0; i < networks.length; i++) {
            vm.createSelectFork(networks[i]);
            address factory =
                zoltuDeployOrAdopt(type(MockCloneFactory).creationCode, type(MockCloneFactory).runtimeCode);
            assertEq(factory, exampleCloneFactory());
            address implementation =
                zoltuDeployOrAdopt(type(MockCloneable).creationCode, type(MockCloneable).runtimeCode);
            assertEq(implementation, exampleCloneImplementation());
            vm.makePersistent(factory);
            vm.makePersistent(implementation);
            // Per network, because "reaches every network" is a claim about a
            // deploy happening on each. A clone already at the address on either
            // one takes that network down the skip branch, and the code-hash
            // assertions below would still pass.
            assertEq(expected.code.length, 0, networks[i]);
        }

        (address deployed, uint256[] memory forkIds) =
            this.externalCloneAndBroadcast(networks, 1, clone, expected, expectedCodeHash);
        assertEq(deployed, expected);
        assertEq(forkIds.length, networks.length);

        // On each fork the loop used, the clone is there with the declared hash.
        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            assertEq(expected.codehash, expectedCodeHash, networks[i]);
        }
    }
}
