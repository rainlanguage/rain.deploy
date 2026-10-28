// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    FrozenSnapshotAmbiguous,
    FrozenSnapshotMechanismDataAmbiguous,
    FrozenSnapshotMechanismDataMissing,
    FrozenSnapshotUnreadable,
    LibRainDeploySnapshot
} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {LibForeignLineBreaks} from "../../lib/LibForeignLineBreaks.sol";

/// @title LibRainDeploySnapshotRecordedMechanismTest
/// @notice Each release's mechanism shape is read from its own record.
contract LibRainDeploySnapshotRecordedMechanismTest is Test {
    /// Where the refusal tests write the records they read, one directory per test, each removed
    /// once read.
    string constant REFUSAL_ROOT = "fixture-lib/recorded-mechanism";

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

    /// External wrapper for `recordedMechanismShape` so `vm.expectRevert` sees its refusal at a lower
    /// call depth.
    /// @param path The record file to read.
    /// @return Whether the record declares `MECHANISM_DATA`.
    /// @return Whether the record declares its addresses per network.
    function externalRecordedMechanismShape(string memory path) external view returns (bool, bool) {
        return LibRainDeploySnapshot.recordedMechanismShape(vm, path);
    }

    /// Reads `record` and expects `recordedMechanismShape` to refuse it with `selector`, naming the
    /// file.
    /// @param name The test's directory under `REFUSAL_ROOT`.
    /// @param record The record's contents.
    /// @param selector The refusal expected.
    function checkRefused(string memory name, string memory record, bytes4 selector) internal {
        (string memory dir, string memory path) = writeRecord(name, record);
        vm.expectRevert(abi.encodeWithSelector(selector, path));
        this.externalRecordedMechanismShape(path);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(dir, true);
    }

    /// Reads `record` and expects `recordedMechanismShape` to read it as the expected shape.
    /// @param name The test's directory under `REFUSAL_ROOT`.
    /// @param record The record's contents.
    /// @param expectedMechanismData Whether `MECHANISM_DATA` is expected to be declared.
    /// @param expectedPerNetwork Whether per-network addresses are expected.
    function checkRead(string memory name, string memory record, bool expectedMechanismData, bool expectedPerNetwork)
        internal
    {
        (string memory dir, string memory path) = writeRecord(name, record);
        (bool mechanismData, bool perNetwork) = this.externalRecordedMechanismShape(path);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(dir, true);
        assertEq(mechanismData, expectedMechanismData);
        assertEq(perNetwork, expectedPerNetwork);
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
            false, false
        );
        checkRead(
            "block-commented-second",
            string.concat(everyNetworkLine(address(1)), MECHANISM_DATA_LINE, "/*\n", MECHANISM_DATA_LINE, "*/\n"),
            true, false
        );
        checkRead(
            "nested-opener",
            string.concat(everyNetworkLine(address(1)), "/* a /* b */\n", MECHANISM_DATA_LINE),
            true, false
        );
        checkRead(
            "opener-in-line-comment",
            string.concat(everyNetworkLine(address(1)), "// /*\n", MECHANISM_DATA_LINE, "// */\n"),
            true, false
        );
        checkRead(
            "line-comment-backslash",
            string.concat(everyNetworkLine(address(1)), "// \\\n/*\n", MECHANISM_DATA_LINE, "*/\n"),
            false, false
        );
        checkRead(
            "lone-slash",
            string.concat(everyNetworkLine(address(1)), "// a / b\n/ /*\n", MECHANISM_DATA_LINE, "*/\n"),
            false, false
        );
    }

    /// A record holding a carriage return, vertical tab, form feed, NEL, LS or PS is refused before any mechanism is
    /// read from it, wherever the break sits.
    function testRecordHoldingAnotherLineBreakIsUnreadable() external {
        string[] memory breaks = LibForeignLineBreaks.foreignLineBreaks();
        for (uint256 i = 0; i < breaks.length; i++) {
            checkRefused(
                string.concat("line-break-", vm.toString(i)),
                string.concat(everyNetworkLine(address(1)), "// note", breaks[i], MECHANISM_DATA_LINE),
                FrozenSnapshotUnreadable.selector
            );
            checkRefused(
                string.concat("trailing-line-break-", vm.toString(i)),
                string.concat(everyNetworkLine(address(1)), "// note", breaks[i], "\n"),
                FrozenSnapshotUnreadable.selector
            );
        }
    }

    /// The three shapes, from minimal records.
    function testTheThreeMechanismsReadFromTheirDeclarations() external {
        checkRead("zoltu", everyNetworkLine(address(1)), false, false);
        checkRead("clone", string.concat(MECHANISM_DATA_LINE, everyNetworkLine(address(1))), true, false);
        checkRead(
            "per-network",
            string.concat(perNetworkLine(137, address(2)), MECHANISM_DATA_LINE, perNetworkLine(42161, address(3))),
            true, true
        );
    }

    /// A line naming `MECHANISM_DATA` that does not start with the writer's declaration is refused as unreadable,
    /// whether solc would read it as a declaration or not.
    function testMechanismDataOffTheWritersDeclarationIsUnreadable() external {
        checkRefused(
            "leading-space",
            string.concat(everyNetworkLine(address(1)), " ", MECHANISM_DATA_LINE),
            FrozenSnapshotUnreadable.selector
        );
        checkRefused(
            "leading-tab",
            string.concat(everyNetworkLine(address(1)), "\t", MECHANISM_DATA_LINE),
            FrozenSnapshotUnreadable.selector
        );
        checkRefused(
            "line-commented",
            string.concat(everyNetworkLine(address(1)), "// ", MECHANISM_DATA_LINE),
            FrozenSnapshotUnreadable.selector
        );
        checkRefused(
            "line-commented-per-network",
            string.concat(perNetworkLine(137, address(2)), MECHANISM_DATA_LINE, "// MECHANISM_DATA\n"),
            FrozenSnapshotUnreadable.selector
        );
    }
}
