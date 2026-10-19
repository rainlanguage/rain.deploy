// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDependency, DeployMechanism, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    FrozenSnapshotAmbiguous,
    FrozenSnapshotMechanismDataAmbiguous,
    FrozenSnapshotMechanismDataMissing,
    FrozenSnapshotUnreadable,
    LibRainDeploySnapshot
} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {CLONE_ARTIFACT_PATH} from "../../../src/lib/LibRainDeployClone.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployMechanism} from "../../../src/lib/LibRainDeployMechanism.sol";
import {MockCloneable} from "../../concrete/MockCloneable.sol";
import {
    BYTECODE_HASH as ZOLTU_BYTECODE_HASH,
    DEPLOYED_ADDRESS as ZOLTU_DEPLOYED_ADDRESS
} from "../../fixture-mechanism-change/generated/0_0_1/MockCloneable.sol";
import {
    BYTECODE_HASH as CLONE_BYTECODE_HASH,
    DEPLOYED_ADDRESS as CLONE_DEPLOYED_ADDRESS,
    MECHANISM_DATA as CLONE_MECHANISM_DATA
} from "../../fixture-mechanism-change/generated/0_0_2/MockCloneable.sol";
import {
    BYTECODE_HASH as PER_NETWORK_BYTECODE_HASH,
    MECHANISM_DATA as PER_NETWORK_MECHANISM_DATA
} from "../../fixture-mechanism-change/generated/0_0_3/MockCloneable.sol";
import {LibMockCloneableReleased} from "../../fixture-mechanism-change/lib/LibMockCloneableReleased.sol";

/// @title LibRainDeploySnapshotRecordedMechanismTest
/// @notice Each release's mechanism is read from its own record.
contract LibRainDeploySnapshotRecordedMechanismTest is Test {
    /// The committed record of `MockCloneable`.
    string constant RECORD_ROOT = "test/fixture-mechanism-change/generated";

    /// Where the committed released lib for `RECORD_ROOT` is.
    string constant LIB_DIR = "test/fixture-mechanism-change/lib";

    /// Where `testTheCommittedLibIsWhatTheGeneratorEmits` writes its fresh generation, removed once
    /// read.
    string constant FRESH_LIB_DIR = "fixture-lib/recorded-mechanism-libs";

    /// Where the refusal tests write the records they read, one directory per test, each removed
    /// once read.
    string constant REFUSAL_ROOT = "fixture-lib/recorded-mechanism";

    string constant RECORD_CONTRACT = "MockCloneable";

    /// The released lib's `DeploySuite` import, from `LIB_DIR`.
    string constant SUITES_IMPORT_PATH = "../../../src/abstract/RainDeploySuitesBase.sol";

    /// The current declaration.
    /// @return The template the released lib takes its key and artifact path from.
    function template() internal pure returns (DeploySuite memory) {
        return DeploySuite({
            suite: "mock-cloneable",
            creationCode: "",
            storedDeployedAddress: address(0),
            storedBytecodeHash: bytes32(0),
            storedRuntimeCode: "",
            artifactPath: CLONE_ARTIFACT_PATH,
            dependencies: new DeployDependency[](0),
            mechanism: DeployMechanism.ClonePerNetwork,
            mechanismData: ""
        });
    }

    /// @param tag The release.
    /// @return The record file of `RECORD_CONTRACT` at `tag`.
    function recordPath(string memory tag) internal pure returns (string memory) {
        return LibRainDeploySnapshot.pathForSnapshot(RECORD_ROOT, tag, RECORD_CONTRACT);
    }

    /// External wrapper for `recordedMechanism` so `vm.expectRevert` sees its refusal at a lower
    /// call depth.
    /// @param path The record file to read.
    /// @return The mechanism the record was cut with.
    function externalRecordedMechanism(string memory path) external view returns (DeployMechanism) {
        return LibRainDeploySnapshot.recordedMechanism(vm, path);
    }

    /// Each record reads as the mechanism its declarations say it was cut with.
    function testRecordedMechanismReadsEachReleaseOnItsOwn() external view {
        assertEq(
            uint256(LibRainDeploySnapshot.recordedMechanism(vm, recordPath("0_0_1"))), uint256(DeployMechanism.Zoltu)
        );
        assertEq(
            uint256(LibRainDeploySnapshot.recordedMechanism(vm, recordPath("0_0_2"))), uint256(DeployMechanism.Clone)
        );
        assertEq(
            uint256(LibRainDeploySnapshot.recordedMechanism(vm, recordPath("0_0_3"))),
            uint256(DeployMechanism.ClonePerNetwork)
        );
    }

    /// The committed released lib is exactly what `writeReleasedSuitesLib` writes from the
    /// committed record today.
    function testTheCommittedLibIsWhatTheGeneratorEmits() external {
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(FRESH_LIB_DIR, true);
        string memory written = LibRainDeploySnapshot.writeReleasedSuitesLib(
            vm, FRESH_LIB_DIR, RECORD_ROOT, RECORD_CONTRACT, template(), SUITES_IMPORT_PATH
        );
        string memory fresh = vm.readFile(written);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(FRESH_LIB_DIR, true);

        assertEq(
            vm.readFile(
                LibRainDeploySnapshot.pathForLib(LIB_DIR, LibRainDeploySnapshot.releasedLibraryName(RECORD_CONTRACT))
            ),
            fresh
        );
    }

    /// Every entry of the committed lib, which compiles, is its release as that release was cut.
    function testEveryEntryIsItsReleasesOwnMechanism() external pure {
        DeploySuite[] memory suites = LibMockCloneableReleased.releasedSuites();
        assertEq(suites.length, 3);

        assertEq(suites[0].suite, "mock-cloneable@0_0_1");
        assertEq(uint256(suites[0].mechanism), uint256(DeployMechanism.Zoltu));
        assertEq(suites[0].mechanismData, "");
        assertEq(suites[0].storedDeployedAddress, ZOLTU_DEPLOYED_ADDRESS);
        assertEq(suites[0].storedDeployedAddress, LibRainDeploy.zoltuAddress(type(MockCloneable).creationCode));
        assertEq(suites[0].storedBytecodeHash, ZOLTU_BYTECODE_HASH);

        assertEq(suites[1].suite, "mock-cloneable@0_0_2");
        assertEq(uint256(suites[1].mechanism), uint256(DeployMechanism.Clone));
        assertEq(suites[1].mechanismData, CLONE_MECHANISM_DATA);
        assertEq(suites[1].storedDeployedAddress, CLONE_DEPLOYED_ADDRESS);
        assertEq(suites[1].storedBytecodeHash, CLONE_BYTECODE_HASH);

        assertEq(suites[2].suite, "mock-cloneable@0_0_3");
        assertEq(uint256(suites[2].mechanism), uint256(DeployMechanism.ClonePerNetwork));
        assertEq(suites[2].mechanismData, PER_NETWORK_MECHANISM_DATA);
        assertEq(suites[2].storedDeployedAddress, address(0));
        assertEq(suites[2].storedBytecodeHash, PER_NETWORK_BYTECODE_HASH);

        for (uint256 i = 0; i < suites.length; i++) {
            assertEq(suites[i].artifactPath, CLONE_ARTIFACT_PATH);
            assertEq(keccak256(suites[i].storedRuntimeCode), suites[i].storedBytecodeHash);
        }
        assertEq(LibRainDeployMechanism.deployedAddress(suites[0], 1), suites[0].storedDeployedAddress);
        assertEq(LibRainDeployMechanism.deployedAddress(suites[1], 1), suites[1].storedDeployedAddress);
    }

    /// Writes `record` as the one file of a refusal test's own directory.
    /// @param name The test's directory under `REFUSAL_ROOT`.
    /// @param record The record's contents.
    /// @return The directory, to remove once read, and the record file.
    function writeRecord(string memory name, string memory record) internal returns (string memory, string memory) {
        string memory dir = string.concat(REFUSAL_ROOT, "/", name);
        string memory path = string.concat(dir, "/Record.sol");
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(dir, true);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(path, record);
        return (dir, path);
    }

    /// `address constant DEPLOYED_ADDRESS = address(<a>);`
    /// @param a The address.
    /// @return The declaration line, newline-terminated.
    function everyNetworkLine(address a) internal pure returns (string memory) {
        return string.concat("address constant DEPLOYED_ADDRESS = address(", vm.toString(a), ");\n");
    }

    /// `address constant DEPLOYED_ADDRESS_<chainId> = address(<a>);`
    /// @param chainId The chain id.
    /// @param a The address.
    /// @return The declaration line, newline-terminated.
    function perNetworkLine(uint256 chainId, address a) internal pure returns (string memory) {
        return string.concat(
            "address constant DEPLOYED_ADDRESS_", vm.toString(chainId), " = address(", vm.toString(a), ");\n"
        );
    }

    string constant MECHANISM_DATA_LINE = "bytes constant MECHANISM_DATA = hex\"01\";\n";

    /// Reads `record` and expects `recordedMechanism` to refuse it with `selector`, naming the
    /// file.
    /// @param name The test's directory under `REFUSAL_ROOT`.
    /// @param record The record's contents.
    /// @param selector The refusal expected.
    function checkRefused(string memory name, string memory record, bytes4 selector) internal {
        (string memory dir, string memory path) = writeRecord(name, record);
        vm.expectRevert(abi.encodeWithSelector(selector, path));
        this.externalRecordedMechanism(path);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(dir, true);
    }

    /// Reads `record` and expects `recordedMechanism` to read it as `expected`.
    /// @param name The test's directory under `REFUSAL_ROOT`.
    /// @param record The record's contents.
    /// @param expected The mechanism expected.
    function checkRead(string memory name, string memory record, DeployMechanism expected) internal {
        (string memory dir, string memory path) = writeRecord(name, record);
        DeployMechanism read = this.externalRecordedMechanism(path);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(dir, true);
        assertEq(uint256(read), uint256(expected));
    }

    /// A record with no deployed address is refused as unreadable, with or without
    /// `MECHANISM_DATA`.
    function testARecordWithNoDeployedAddressIsUnreadable() external {
        checkRefused("no-address", MECHANISM_DATA_LINE, FrozenSnapshotUnreadable.selector);
        checkRefused(
            "no-address-no-data", "bytes32 constant BYTECODE_HASH = 0x00;\n", FrozenSnapshotUnreadable.selector
        );
    }

    /// A record declaring `DEPLOYED_ADDRESS` beside a `DEPLOYED_ADDRESS_<chainId>` is refused as
    /// ambiguous, with or without `MECHANISM_DATA`.
    function testARecordDeclaringBothAddressFormsIsAmbiguous() external {
        checkRefused(
            "both-forms",
            string.concat(everyNetworkLine(address(1)), perNetworkLine(137, address(2)), MECHANISM_DATA_LINE),
            FrozenSnapshotAmbiguous.selector
        );
        checkRefused(
            "both-forms-no-data",
            string.concat(perNetworkLine(137, address(2)), everyNetworkLine(address(1))),
            FrozenSnapshotAmbiguous.selector
        );
    }

    /// A record declaring its addresses per network without `MECHANISM_DATA` is refused.
    function testPerNetworkAddressesWithoutMechanismDataAreRefused() external {
        checkRefused(
            "per-network-no-data",
            string.concat(perNetworkLine(137, address(2)), perNetworkLine(42161, address(3))),
            FrozenSnapshotMechanismDataMissing.selector
        );
    }

    /// A record declaring `MECHANISM_DATA` twice is refused, beside either address form.
    function testMechanismDataDeclaredTwiceIsAmbiguous() external {
        checkRefused(
            "data-twice",
            string.concat(everyNetworkLine(address(1)), MECHANISM_DATA_LINE, MECHANISM_DATA_LINE),
            FrozenSnapshotMechanismDataAmbiguous.selector
        );
        checkRefused(
            "data-twice-per-network",
            string.concat(MECHANISM_DATA_LINE, perNetworkLine(137, address(2)), MECHANISM_DATA_LINE),
            FrozenSnapshotMechanismDataAmbiguous.selector
        );
    }

    /// `MECHANISM_DATA` counts only as a declaration the compiler reads.
    function testCommentedOutMechanismDataIsNotADeclaration() external {
        checkRead(
            "block-commented",
            string.concat(everyNetworkLine(address(1)), "/*\n", MECHANISM_DATA_LINE, "*/\n"),
            DeployMechanism.Zoltu
        );
        checkRead(
            "line-commented",
            string.concat(everyNetworkLine(address(1)), "// ", MECHANISM_DATA_LINE),
            DeployMechanism.Zoltu
        );
        checkRead(
            "block-commented-second",
            string.concat(everyNetworkLine(address(1)), MECHANISM_DATA_LINE, "/*\n", MECHANISM_DATA_LINE, "*/\n"),
            DeployMechanism.Clone
        );
        checkRead(
            "nested-opener",
            string.concat(everyNetworkLine(address(1)), "/* a /* b */\n", MECHANISM_DATA_LINE),
            DeployMechanism.Clone
        );
        checkRead(
            "opener-in-line-comment",
            string.concat(everyNetworkLine(address(1)), "// /*\n", MECHANISM_DATA_LINE, "// */\n"),
            DeployMechanism.Clone
        );
        checkRead(
            "line-comment-backslash",
            string.concat(everyNetworkLine(address(1)), "// \\\n/*\n", MECHANISM_DATA_LINE, "*/\n"),
            DeployMechanism.Zoltu
        );
        checkRead(
            "lone-slash",
            string.concat(everyNetworkLine(address(1)), "// a / b\n/ /*\n", MECHANISM_DATA_LINE, "*/\n"),
            DeployMechanism.Zoltu
        );
    }

    /// A record holding a carriage return, vertical tab, form feed, NEL, LS or PS is refused before any mechanism is
    /// read from it.
    function testRecordHoldingAnotherLineBreakIsUnreadable() external {
        string[] memory breaks = new string[](6);
        breaks[0] = "\r";
        breaks[1] = "\x0b";
        breaks[2] = "\x0c";
        breaks[3] = "\xc2\x85";
        breaks[4] = "\xe2\x80\xa8";
        breaks[5] = "\xe2\x80\xa9";
        for (uint256 i = 0; i < breaks.length; i++) {
            checkRefused(
                string.concat("line-break-", vm.toString(i)),
                string.concat(everyNetworkLine(address(1)), "// note", breaks[i], MECHANISM_DATA_LINE),
                FrozenSnapshotUnreadable.selector
            );
        }
    }

    /// The three readings, from minimal records.
    function testTheThreeMechanismsReadFromTheirDeclarations() external {
        checkRead("zoltu", everyNetworkLine(address(1)), DeployMechanism.Zoltu);
        checkRead("clone", string.concat(MECHANISM_DATA_LINE, everyNetworkLine(address(1))), DeployMechanism.Clone);
        checkRead(
            "per-network",
            string.concat(perNetworkLine(137, address(2)), MECHANISM_DATA_LINE, perNetworkLine(42161, address(3))),
            DeployMechanism.ClonePerNetwork
        );
    }
}
