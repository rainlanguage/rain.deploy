// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibResolvedReadFixture} from "../../lib/LibResolvedReadFixture.sol";
import {MockResolvedValues} from "../../concrete/MockResolvedValues.sol";
import {MockRevertingAnswerOwner} from "../../concrete/MockRevertingAnswerOwner.sol";
import {MockRawAnswerOwner} from "../../concrete/MockRawAnswerOwner.sol";
import {MockChainDependentOwner} from "../../concrete/MockChainDependentOwner.sol";

/// @title LibRainDeployResolvedValuesTest
/// Tests for `LibRainDeploy.checkResolvedValues` and its fork stages.
contract LibRainDeployResolvedValuesTest is Test {
    /// External wrapper so `vm.expectRevert` sees the library revert.
    /// @param network The network name, for the error only.
    /// @param target The deployed contract to read.
    /// @param readCalls The calldata of each read.
    /// @param expectedValues The bytes each read must answer.
    function externalCheckResolvedValues(
        string memory network,
        address target,
        bytes[] memory readCalls,
        bytes[] memory expectedValues
    ) external view {
        LibRainDeploy.checkResolvedValues(network, target, readCalls, expectedValues);
    }

    /// External wrapper so `vm.expectRevert` sees the library revert.
    /// @param networks The network names.
    /// @param forkIds The fork of each network, positionally paired.
    /// @param target The deployed contract to read.
    /// @param readCalls The calldata of each read.
    /// @param expectedValues The bytes each read must answer.
    function externalCheckResolvedValuesOnForks(
        string[] memory networks,
        uint256[] memory forkIds,
        address target,
        bytes[] memory readCalls,
        bytes[] memory expectedValues
    ) external {
        LibRainDeploy.checkResolvedValuesOnForks(vm, networks, forkIds, target, readCalls, expectedValues);
    }

    /// External wrapper so `vm.expectRevert` sees the library revert.
    /// @param networks The network names.
    /// @param target The deployed contract to read.
    /// @param readCalls The calldata of each read.
    /// @param expectedValues The bytes each read must answer.
    function externalCheckResolvedValuesOnNetworks(
        string[] memory networks,
        address target,
        bytes[] memory readCalls,
        bytes[] memory expectedValues
    ) external {
        LibRainDeploy.checkResolvedValuesOnNetworks(vm, networks, target, readCalls, expectedValues);
    }

    /// The reads of `MockResolvedValues`, in declaration order.
    /// @return The read call list.
    function valueReadCalls() internal pure returns (bytes[] memory) {
        bytes[] memory readCalls = new bytes[](3);
        readCalls[0] = abi.encodeWithSignature("iThreshold()");
        readCalls[1] = abi.encodeWithSignature("iCodeHash()");
        readCalls[2] = abi.encodeWithSignature("signers()");
        return readCalls;
    }

    /// The return data `valueReadCalls` answer with for these values.
    /// @param threshold The `iThreshold` answer.
    /// @param codeHash The `iCodeHash` answer.
    /// @param signers The `signers` answer.
    /// @return The expected value list.
    function valueExpected(uint256 threshold, bytes32 codeHash, address[] memory signers)
        internal
        pure
        returns (bytes[] memory)
    {
        bytes[] memory expectedValues = new bytes[](3);
        expectedValues[0] = abi.encode(threshold);
        expectedValues[1] = abi.encode(codeHash);
        expectedValues[2] = abi.encode(signers);
        return expectedValues;
    }

    /// A one-element list.
    /// @param value The element.
    /// @return The list.
    function one(bytes memory value) internal pure returns (bytes[] memory) {
        bytes[] memory values = new bytes[](1);
        values[0] = value;
        return values;
    }

    /// Every read answering exactly its expected bytes MUST pass, a zero
    /// threshold included.
    function testCheckResolvedValuesMatch(uint256 threshold, bytes32 codeHash, address[] memory signers) external {
        MockResolvedValues target = new MockResolvedValues(threshold, codeHash, signers);
        LibRainDeploy.checkResolvedValues(
            "test_network", address(target), valueReadCalls(), valueExpected(threshold, codeHash, signers)
        );

        MockResolvedValues zero = new MockResolvedValues(0, codeHash, signers);
        LibRainDeploy.checkResolvedValues(
            "test_network", address(zero), valueReadCalls(), valueExpected(0, codeHash, signers)
        );
    }

    /// One bit flipped in any expected value MUST revert naming that read, the
    /// expected bytes and the bytes answered.
    function testCheckResolvedValuesOneBitReverts(
        uint256 threshold,
        bytes32 codeHash,
        address[] memory signers,
        uint256 index,
        uint256 bit
    ) external {
        MockResolvedValues target = new MockResolvedValues(threshold, codeHash, signers);
        bytes[] memory expectedValues = valueExpected(threshold, codeHash, signers);
        index = bound(index, 0, 2);
        bytes memory actual = expectedValues[index];
        bytes memory wrong = bytes.concat(actual);
        bit = bound(bit, 0, wrong.length * 8 - 1);
        wrong[bit / 8] ^= bytes1(0x01) << (bit % 8);
        expectedValues[index] = wrong;

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedValue.selector, "test_network", address(target), index, wrong, actual
            )
        );
        this.externalCheckResolvedValues("test_network", address(target), valueReadCalls(), expectedValues);
    }

    /// An expected value the answer is a strict prefix or extension of MUST
    /// revert: equal leading bytes are not a match.
    function testCheckResolvedValuesLengthChangeReverts(address[] memory signers, address extra) external {
        MockResolvedValues target = new MockResolvedValues(0, bytes32(0), signers);
        bytes memory actual = abi.encode(signers);

        bytes memory longer = bytes.concat(actual, abi.encode(extra));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedValue.selector,
                "test_network",
                address(target),
                uint256(0),
                longer,
                actual
            )
        );
        this.externalCheckResolvedValues(
            "test_network", address(target), one(abi.encodeWithSignature("signers()")), one(longer)
        );

        bytes memory shorter = new bytes(actual.length - 32);
        for (uint256 i = 0; i < shorter.length; i++) {
            shorter[i] = actual[i];
        }
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedValue.selector,
                "test_network",
                address(target),
                uint256(0),
                shorter,
                actual
            )
        );
        this.externalCheckResolvedValues(
            "test_network", address(target), one(abi.encodeWithSignature("signers()")), one(shorter)
        );
    }

    /// A read that reverts MUST fail as a read, even when its revert data is
    /// exactly the expected bytes.
    function testCheckResolvedValuesRevertingReadReverts(bytes memory answer) external {
        vm.assume(answer.length > 0);
        MockRevertingAnswerOwner target = new MockRevertingAnswerOwner(answer);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.ResolvedValueReadFailed.selector, "test_network", address(target), uint256(0), answer
            )
        );
        this.externalCheckResolvedValues(
            "test_network", address(target), LibResolvedReadFixture.ownerReadCalls(), one(answer)
        );
    }

    /// A target with no code answers nothing, which MUST fail as a read, even
    /// against an empty expectation.
    function testCheckResolvedValuesUnreadableTargetReverts(address target) external {
        vm.assume(target.code.length == 0);
        // Precompiles and forge's own addresses have no code yet answer.
        vm.assume(uint160(target) > 0xffff);
        assumeNotForgeAddress(target);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.ResolvedValueReadFailed.selector, "test_network", target, uint256(0), bytes("")
            )
        );
        this.externalCheckResolvedValues("test_network", target, LibResolvedReadFixture.ownerReadCalls(), one(""));
    }

    /// An answer that is not whole words is still an answer: it MUST pass on
    /// exactly those bytes and mismatch on any other, never fail as a read.
    function testCheckResolvedValuesShortAnswerIsAnAnswer(bytes memory answer, bytes memory other) external {
        vm.assume(answer.length > 0 && answer.length < 0x20);
        vm.assume(keccak256(other) != keccak256(answer));
        MockRawAnswerOwner target = new MockRawAnswerOwner(answer);
        LibRainDeploy.checkResolvedValues(
            "test_network", address(target), LibResolvedReadFixture.ownerReadCalls(), one(answer)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedValue.selector,
                "test_network",
                address(target),
                uint256(0),
                other,
                answer
            )
        );
        this.externalCheckResolvedValues(
            "test_network", address(target), LibResolvedReadFixture.ownerReadCalls(), one(other)
        );
    }

    /// A failed read after the first MUST be named by its own index.
    function testCheckResolvedValuesReadFailureNamesTheFailingRead(
        uint256 threshold,
        bytes32 codeHash,
        address[] memory signers
    ) external {
        MockResolvedValues target = new MockResolvedValues(threshold, codeHash, signers);
        bytes[] memory readCalls = valueReadCalls();
        readCalls[1] = abi.encodeWithSignature("thisFunctionDoesNotExist()");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.ResolvedValueReadFailed.selector, "test_network", address(target), uint256(1), bytes("")
            )
        );
        this.externalCheckResolvedValues(
            "test_network", address(target), readCalls, valueExpected(threshold, codeHash, signers)
        );
    }

    /// Every read MUST be checked, not only the first.
    function testCheckResolvedValuesChecksEveryRead(uint256 threshold, bytes32 codeHash, address[] memory signers)
        external
    {
        MockResolvedValues target = new MockResolvedValues(threshold, codeHash, signers);
        bytes[] memory expectedValues = valueExpected(threshold, codeHash, signers);
        bytes memory wrong = abi.encode(~codeHash);
        expectedValues[1] = wrong;
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedValue.selector,
                "test_network",
                address(target),
                uint256(1),
                wrong,
                abi.encode(codeHash)
            )
        );
        this.externalCheckResolvedValues("test_network", address(target), valueReadCalls(), expectedValues);
    }

    /// Unpaired reads and expectations MUST revert with both lengths.
    function testCheckResolvedValuesLengthMismatchReverts(uint8 readCallsLength, uint8 expectedLength) external {
        vm.assume(readCallsLength != expectedLength);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.ResolvedValuesLengthMismatch.selector, uint256(readCallsLength), uint256(expectedLength)
            )
        );
        this.externalCheckResolvedValues(
            "test_network", address(this), new bytes[](readCallsLength), new bytes[](expectedLength)
        );
    }

    /// No reads MUST revert naming the target.
    function testCheckResolvedValuesNoReadsReverts(address target) external {
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoResolvedValueReads.selector, target));
        this.externalCheckResolvedValues("test_network", target, new bytes[](0), new bytes[](0));
    }

    /// No networks MUST revert before every other refusal.
    function testCheckResolvedValuesOnForksNoNetworksBeatsEverything() external {
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalCheckResolvedValuesOnForks(
            new string[](0), new uint256[](1), address(this), new bytes[](0), new bytes[](1)
        );
    }

    /// Unpaired fork ids MUST revert before anything is selected, and before the
    /// read set is checked.
    function testCheckResolvedValuesOnForksForkIdsLengthMismatchReverts() external {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.BASE;
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.ForkIdsLengthMismatch.selector, uint256(2), uint256(1)));
        this.externalCheckResolvedValuesOnForks(
            networks, LibResolvedReadFixture.unselectableForkIds(1), address(this), new bytes[](0), new bytes[](0)
        );
    }

    /// An unusable read set MUST be refused before anything is selected.
    function testCheckResolvedValuesOnForksReadSetRefusedBeforeSelecting() external {
        string[] memory networks = new string[](1);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;

        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.ResolvedValuesLengthMismatch.selector, uint256(2), uint256(1))
        );
        this.externalCheckResolvedValuesOnForks(
            networks, LibResolvedReadFixture.unselectableForkIds(1), address(this), new bytes[](2), new bytes[](1)
        );

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoResolvedValueReads.selector, address(this)));
        this.externalCheckResolvedValuesOnForks(
            networks, LibResolvedReadFixture.unselectableForkIds(1), address(this), new bytes[](0), new bytes[](0)
        );
    }

    /// No networks MUST revert before the read set is checked.
    function testCheckResolvedValuesOnNetworksNoNetworksReverts() external {
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoNetworks.selector));
        this.externalCheckResolvedValuesOnNetworks(new string[](0), address(this), new bytes[](0), new bytes[](1));
    }

    /// An unusable read set MUST be refused before anything is forked.
    function testCheckResolvedValuesOnNetworksReadSetRefusedBeforeForking() external {
        string[] memory networks = new string[](1);
        // Not a configured RPC alias, so forking it is itself an error.
        networks[0] = "unconfigured_network";

        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.ResolvedValuesLengthMismatch.selector, uint256(2), uint256(1))
        );
        this.externalCheckResolvedValuesOnNetworks(networks, address(this), new bytes[](2), new bytes[](1));

        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.NoResolvedValueReads.selector, address(this)));
        this.externalCheckResolvedValuesOnNetworks(networks, address(this), new bytes[](0), new bytes[](0));
    }

    /// Every network MUST be checked: a target that agrees only on the first
    /// fails naming the second.
    function testCheckResolvedValuesOnNetworksReachesEveryNetwork() external {
        address account = address(0xf00);
        address wrong = address(0xba4);
        MockChainDependentOwner target =
            new MockChainDependentOwner(account, wrong, LibResolvedReadFixture.ARBITRUM_ONE_CHAIN_ID);
        vm.makePersistent(address(target));

        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.BASE;

        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedValue.selector,
                LibRainDeploy.BASE,
                address(target),
                uint256(0),
                abi.encode(account),
                abi.encode(wrong)
            )
        );
        this.externalCheckResolvedValuesOnNetworks(
            networks, address(target), LibResolvedReadFixture.ownerReadCalls(), one(abi.encode(account))
        );
    }

    /// Every network agreeing MUST pass.
    function testCheckResolvedValuesOnNetworksEachNetwork() external {
        address account = address(0xf00);
        MockChainDependentOwner target =
            new MockChainDependentOwner(account, account, LibResolvedReadFixture.ARBITRUM_ONE_CHAIN_ID);
        vm.makePersistent(address(target));

        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.BASE;

        LibRainDeploy.checkResolvedValuesOnNetworks(
            vm, networks, address(target), LibResolvedReadFixture.ownerReadCalls(), one(abi.encode(account))
        );
    }
}
