// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    NEWLINE_DUE_TO_MAX_LENGTH,
    RAIN_COPYRIGHT_TEXT,
    RAIN_SPDX_LICENSE_IDENTIFIER
} from "rain-sol-codegen-0.1.39/src/lib/LibCodeGen.sol";
import {
    DeployDeclaration,
    DeployDependency,
    DeploySuite,
    SnapshotFile
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {
    FrozenSnapshotDescribedByMetaAmbiguous,
    FrozenSnapshotUnreadable,
    LibRainDeploySnapshot
} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {LibForeignLineBreaks} from "../../lib/LibForeignLineBreaks.sol";

contract LibRainDeploySnapshotDescribedByMetaTest is Test {
    string constant ROOT = "fixture-lib/described-by-meta";

    function zoltuDeclaration() internal pure returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployZoltuMechanism.extend(d);
        return d;
    }

    function suite(bytes memory meta) internal pure returns (DeploySuite memory) {
        return DeploySuite({
            networks: new string[](0),
            suite: "Record",
            creationCode: type(MockDeployable).creationCode,
            storedDeployedAddress: address(0),
            storedBytecodeHash: bytes32(0),
            storedRuntimeCode: "",
            artifactPath: "test/concrete/MockDeployable.sol:MockDeployable",
            dependencies: new DeployDependency[](0),
            mechanismData: LibRainDeployZoltuMechanism.mechanismData(),
            describedByMeta: meta
        });
    }

    function hexDigits(bytes memory data) internal pure returns (string memory) {
        return vm.replace(vm.toString(data), "0x", "");
    }

    function writeSuite(string memory name, bytes memory meta) internal returns (string memory, string memory) {
        string memory root = string.concat(ROOT, "/", name);
        string memory path = LibRainDeployZoltuMechanism.writeSuiteSnapshot(
            zoltuDeclaration(),
            vm,
            SnapshotFile(root, "0_1_0", "Record", RAIN_SPDX_LICENSE_IDENTIFIER, RAIN_COPYRIGHT_TEXT),
            suite(meta)
        );
        return (root, path);
    }

    function writeRecord(string memory name, string memory record) internal returns (string memory, string memory) {
        string memory root = string.concat(ROOT, "/", name);
        string memory path = string.concat(root, "/0_1_0/Record.sol");
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(string.concat(root, "/0_1_0"), true);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(path, record);
        return (root, path);
    }

    function removeRoot(string memory root) internal {
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(root, true);
    }

    function addressLine() internal pure returns (string memory) {
        return string.concat("address constant DEPLOYED_ADDRESS = address(", vm.toString(address(1)), ");\n");
    }

    function metaLine(string memory digits) internal pure returns (string memory) {
        return string.concat("bytes constant DESCRIBED_BY_META = hex\"", digits, "\";\n");
    }

    function externalRecordedDescribedByMeta(string memory path) external view returns (bool) {
        return LibRainDeploySnapshot.recordedDescribedByMeta(vm, path);
    }

    function externalReleasedImport(string memory path) external view returns (string memory) {
        return LibRainDeploySnapshot.releasedImport(vm, path);
    }

    function externalReleasedSuiteEntry(string memory path) external view returns (string memory) {
        return LibRainDeploySnapshot.releasedSuiteEntry(vm, 0, path, suite(""), zoltuDeclaration());
    }

    /// The source after the `DEPENDENCIES` declaration, which MUST be declared exactly once.
    function afterDependencies(string memory source) internal pure returns (string memory) {
        string[] memory parts = vm.split(source, "\nbytes constant DEPENDENCIES =");
        assertEq(parts.length, 2);
        return parts[1];
    }

    function checkWriterDeclaresTheMetaLast(string memory name, bytes memory meta, string memory separator) internal {
        (string memory root, string memory path) = writeSuite(name, meta);
        string memory source = vm.readFile(path);
        removeRoot(root);
        string[] memory parts = vm.split(afterDependencies(source), "\nbytes constant DESCRIBED_BY_META =");
        assertEq(parts.length, 2);
        assertEq(parts[1], string.concat(separator, "hex\"", hexDigits(meta), "\";\n"));
        assertEq(vm.split(source, "DESCRIBED_BY_META").length, 2);
    }

    function testTheWriterDeclaresAShortMetaLastOnOneLine() external {
        checkWriterDeclaresTheMetaLast("short", hex"ff0a0d", " ");
    }

    function testTheWriterDeclaresALongMetaLastWrapped() external {
        bytes memory meta = new bytes(64);
        for (uint256 i = 0; i < meta.length; i++) {
            meta[i] = bytes1(uint8(i + 1));
        }
        checkWriterDeclaresTheMetaLast("long", meta, NEWLINE_DUE_TO_MAX_LENGTH);
    }

    function testTheWriterDeclaresNoMetaForAnEmptyOne() external {
        (string memory root, string memory path) = writeSuite("empty", "");
        string memory source = vm.readFile(path);
        removeRoot(root);
        assertFalse(vm.contains(source, "DESCRIBED_BY_META"));
        assertEq(vm.split(afterDependencies(source), "\nbytes constant ").length, 1);
    }

    function testAWrittenMetaIsRecordedAndAliased(bytes memory meta) external {
        vm.assume(meta.length != 0);
        (string memory root, string memory path) = writeSuite("round-trip", meta);
        bool recorded = this.externalRecordedDescribedByMeta(path);
        string memory imported = this.externalReleasedImport(path);
        string memory entry = this.externalReleasedSuiteEntry(path);
        removeRoot(root);
        assertTrue(recorded);
        assertEq(
            imported,
            "import {\n    DEPLOYED_ADDRESS as Record_0_1_0_DEPLOYED_ADDRESS,\n"
            "    BYTECODE_HASH as Record_0_1_0_BYTECODE_HASH,\n" "    CREATION_CODE as Record_0_1_0_CREATION_CODE,\n"
            "    RUNTIME_CODE as Record_0_1_0_RUNTIME_CODE,\n" "    DEPENDENCIES as Record_0_1_0_DEPENDENCIES,\n"
            "    DESCRIBED_BY_META as Record_0_1_0_DESCRIBED_BY_META\n" "} from \"../generated/0_1_0/Record.sol\";\n\n"
        );
        assertEq(
            entry,
            "        suites[0] = DeploySuite({\n" "            suite: \"Record@0_1_0\",\n"
            "            creationCode: Record_0_1_0_CREATION_CODE,\n"
            "            storedDeployedAddress: Record_0_1_0_DEPLOYED_ADDRESS,\n"
            "            storedBytecodeHash: Record_0_1_0_BYTECODE_HASH,\n"
            "            storedRuntimeCode: Record_0_1_0_RUNTIME_CODE,\n"
            "            artifactPath: \"test/concrete/MockDeployable.sol:MockDeployable\",\n"
            "            dependencies: abi.decode(Record_0_1_0_DEPENDENCIES, (DeployDependency[])),\n"
            "            mechanismData: LibRainDeployZoltuMechanism.mechanismData(),\n"
            "            networks: new string[](0),\n" "            describedByMeta: Record_0_1_0_DESCRIBED_BY_META\n"
            "        });\n"
        );
    }

    function testAWrittenEmptyMetaIsNeitherRecordedNorAliased() external {
        (string memory root, string memory path) = writeSuite("round-trip-empty", "");
        bool recorded = this.externalRecordedDescribedByMeta(path);
        string memory imported = this.externalReleasedImport(path);
        string memory entry = this.externalReleasedSuiteEntry(path);
        removeRoot(root);
        assertFalse(recorded);
        assertFalse(vm.contains(imported, "DESCRIBED_BY_META"));
        assertTrue(
            vm.contains(
                entry, "            networks: new string[](0),\n            describedByMeta: \"\"\n        });\n"
            )
        );
        assertFalse(vm.contains(entry, "DESCRIBED_BY_META"));
    }

    function testTheMetaAliasFollowsTheMechanismDataAlias() external {
        (string memory root, string memory path) = writeRecord(
            "after-mechanism-data",
            string.concat(addressLine(), "bytes constant MECHANISM_DATA = hex\"00\";\n", metaLine("ff"))
        );
        string memory imported = this.externalReleasedImport(path);
        removeRoot(root);
        assertTrue(
            vm.contains(
                imported,
                "    MECHANISM_DATA as Record_0_1_0_MECHANISM_DATA,\n"
                "    DESCRIBED_BY_META as Record_0_1_0_DESCRIBED_BY_META\n} from"
            )
        );
    }

    function checkRecorded(string memory name, string memory record, bool expected) internal {
        (string memory root, string memory path) = writeRecord(name, record);
        bool recorded = this.externalRecordedDescribedByMeta(path);
        removeRoot(root);
        assertEq(recorded, expected);
    }

    function testARecordDeclaringTheMetaRecordsIt() external {
        checkRecorded("declared", string.concat(addressLine(), metaLine("ff")), true);
        checkRecorded(
            "declared-wrapped",
            string.concat(addressLine(), "bytes constant DESCRIBED_BY_META =\n    hex\"ff\";\n"),
            true
        );
        checkRecorded(
            "declared-beside-a-commented-one",
            string.concat(addressLine(), "/*\n", metaLine("00"), "*/\n", metaLine("ff")),
            true
        );
    }

    function testARecordNotDeclaringTheMetaRecordsNone() external {
        checkRecorded("undeclared", addressLine(), false);
        checkRecorded("commented", string.concat(addressLine(), "/*\n", metaLine("ff"), "*/\n"), false);
    }

    function testTwoDeclarationsOfTheMetaAreAmbiguous() external {
        (string memory root, string memory path) =
            writeRecord("ambiguous", string.concat(addressLine(), metaLine("ff"), metaLine("ff")));
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotDescribedByMetaAmbiguous.selector, path));
        this.externalRecordedDescribedByMeta(path);
        removeRoot(root);
    }

    function checkUnreadable(string memory name, string memory record) internal {
        (string memory root, string memory path) = writeRecord(name, record);
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, path));
        this.externalRecordedDescribedByMeta(path);
        removeRoot(root);
    }

    function testTheMetaNamedOutsideTheWritersDeclarationIsUnreadable() external {
        checkUnreadable("line-comment", string.concat(addressLine(), "// DESCRIBED_BY_META\n"));
        checkUnreadable("indented", string.concat(addressLine(), "    ", metaLine("ff")));
        checkUnreadable("longer-name", string.concat(addressLine(), "bytes constant DESCRIBED_BY_METAS = hex\"ff\";\n"));
        checkUnreadable(
            "other-name", string.concat(addressLine(), "bytes constant NOT_DESCRIBED_BY_META = hex\"ff\";\n")
        );
        checkUnreadable(
            "double-space", string.concat(addressLine(), "bytes  constant DESCRIBED_BY_META = hex\"ff\";\n")
        );
        checkUnreadable(
            "beside-the-declaration", string.concat(addressLine(), metaLine("ff"), "// DESCRIBED_BY_META\n")
        );
    }

    function testAForeignLineBreakIsUnreadable() external {
        string[] memory breaks = LibForeignLineBreaks.foreignLineBreaks();
        for (uint256 i = 0; i < breaks.length; i++) {
            checkUnreadable(
                string.concat("foreign-break-", vm.toString(i)), string.concat(addressLine(), breaks[i], metaLine("ff"))
            );
        }
    }
}
