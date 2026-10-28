// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    DeployDeclaration,
    DeployDependency,
    DeploySuite,
    LegacyRecordAmbiguous,
    MechanismUnclaimed
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {FrozenSnapshotUnreadable, LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {LibRainDeployZoltuMechanism, ZOLTU_MECHANISM_ID} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {LibMockCreate2Mechanism, MOCK_CREATE2_MECHANISM_ID} from "../../lib/LibMockCreate2Mechanism.sol";
import {LibMockSaltMechanism, MOCK_SALT_MECHANISM_ID} from "../../lib/LibMockSaltMechanism.sol";
import {IMockMechanismProbe, MOCK_MECHANISM_PROBE} from "../../lib/LibMockMechanismProbe.sol";

contract LibRainDeploySnapshotRecordedMechanismIdTest is Test {
    string constant ROOT = "fixture-lib/recorded-mechanism-id";

    /// A leading word that is no declared mechanism's id.
    bytes32 constant WORD = 0x0123456789abcdef00112233445566778899aabbccddeeff0f1e2d3c4b5a6978;

    function declaration() internal pure returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployZoltuMechanism.extend(d);
        LibMockCreate2Mechanism.extend(d);
        LibMockSaltMechanism.extend(d);
        return d;
    }

    function writeRecord(string memory name, string memory record) internal returns (string memory, string memory) {
        string memory dir = string.concat(ROOT, "/", name);
        string memory path = string.concat(dir, "/0_1_0/Record.sol");
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(string.concat(dir, "/0_1_0"), true);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(path, record);
        return (dir, path);
    }

    function removeRecord(string memory dir) internal {
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(dir, true);
    }

    function everyNetworkLine() internal pure returns (string memory) {
        return string.concat("address constant DEPLOYED_ADDRESS = address(", vm.toString(address(1)), ");\n");
    }

    function perNetworkLine(uint256 chainId) internal pure returns (string memory) {
        return string.concat(
            "address constant DEPLOYED_ADDRESS_", vm.toString(chainId), " = address(", vm.toString(address(2)), ");\n"
        );
    }

    function hexDigits(bytes32 word) internal pure returns (string memory) {
        return vm.replace(vm.toString(word), "0x", "");
    }

    function mechanismDataLine(string memory digits) internal pure returns (string memory) {
        return string.concat("bytes constant MECHANISM_DATA = hex\"", digits, "\";\n");
    }

    function untaggedRecord() internal pure returns (string memory) {
        return string.concat(everyNetworkLine(), mechanismDataLine(string.concat(hexDigits(WORD), "deadbeef")));
    }

    function legacyRecordIdCall(bytes32 mechanismId, string memory path) internal pure returns (bytes memory) {
        return abi.encodeCall(IMockMechanismProbe.legacyRecordId, (mechanismId, path));
    }

    function claim(bytes32 mechanismId, string memory path) internal {
        vm.mockCall(MOCK_MECHANISM_PROBE, legacyRecordIdCall(mechanismId, path), abi.encode(mechanismId));
    }

    function expectNoHandlerAsked() internal {
        vm.expectCall(MOCK_MECHANISM_PROBE, abi.encodeWithSelector(IMockMechanismProbe.legacyRecordId.selector), 0);
    }

    function expectEveryHandlerAskedOnce(string memory path) internal {
        vm.expectCall(MOCK_MECHANISM_PROBE, legacyRecordIdCall(MOCK_CREATE2_MECHANISM_ID, path), 1);
        vm.expectCall(MOCK_MECHANISM_PROBE, legacyRecordIdCall(MOCK_SALT_MECHANISM_ID, path), 1);
    }

    function externalRecordedMechanismId(string memory path) external view returns (bytes32) {
        return LibRainDeploySnapshot.recordedMechanismId(declaration(), vm, path);
    }

    function externalZoltuOnlyRecordedMechanismId(string memory path) external view returns (bytes32) {
        DeployDeclaration memory d;
        LibRainDeployZoltuMechanism.extend(d);
        return LibRainDeploySnapshot.recordedMechanismId(d, vm, path);
    }

    function externalZoltuLegacyRecordId(string memory path) external view returns (bytes32) {
        DeployDeclaration memory d = declaration();
        return LibRainDeployZoltuMechanism.handler().legacyRecordId(d, vm, path);
    }

    function externalReleasedSuiteEntry(string memory path) external view returns (string memory) {
        DeploySuite memory template = DeploySuite({
            suite: "Record",
            creationCode: "",
            storedDeployedAddress: address(0),
            storedBytecodeHash: bytes32(0),
            storedRuntimeCode: "",
            artifactPath: "",
            dependencies: new DeployDependency[](0),
            mechanismData: LibRainDeployZoltuMechanism.mechanismData(),
            networks: new string[](0)
        });
        return LibRainDeploySnapshot.releasedSuiteEntry(vm, 0, path, template, declaration());
    }

    function checkId(string memory name, string memory record, bytes32 expected) internal {
        (string memory dir, string memory path) = writeRecord(name, record);
        bytes32 id = this.externalRecordedMechanismId(path);
        removeRecord(dir);
        assertEq(id, expected);
    }

    function checkUnreadable(string memory name, string memory record) internal {
        (string memory dir, string memory path) = writeRecord(name, record);
        vm.expectRevert(abi.encodeWithSelector(FrozenSnapshotUnreadable.selector, path));
        this.externalRecordedMechanismId(path);
        removeRecord(dir);
    }

    function testARecordWithoutMechanismDataReadsAsZoltu() external {
        expectNoHandlerAsked();
        checkId("zoltu", everyNetworkLine(), ZOLTU_MECHANISM_ID);
        checkId(
            "zoltu-commented",
            string.concat(everyNetworkLine(), "/*\n", mechanismDataLine(hexDigits(WORD)), "*/\n"),
            ZOLTU_MECHANISM_ID
        );
    }

    function testTheIdIsTheLeadingWordOfMechanismData() external {
        expectNoHandlerAsked();
        checkId(
            "exact-word",
            string.concat(everyNetworkLine(), mechanismDataLine(hexDigits(MOCK_CREATE2_MECHANISM_ID))),
            MOCK_CREATE2_MECHANISM_ID
        );
        checkId(
            "trailing-bytes",
            string.concat(
                mechanismDataLine(string.concat(hexDigits(MOCK_SALT_MECHANISM_ID), "deadbeef")), everyNetworkLine()
            ),
            MOCK_SALT_MECHANISM_ID
        );
        checkId(
            "per-network",
            string.concat(
                perNetworkLine(137),
                mechanismDataLine(string.concat(hexDigits(MOCK_CREATE2_MECHANISM_ID), hexDigits(ZOLTU_MECHANISM_ID))),
                perNetworkLine(42161)
            ),
            MOCK_CREATE2_MECHANISM_ID
        );
        checkId(
            "wrapped",
            string.concat(
                everyNetworkLine(),
                "bytes constant MECHANISM_DATA =\n    hex\"",
                hexDigits(MOCK_SALT_MECHANISM_ID),
                "00\";\n"
            ),
            MOCK_SALT_MECHANISM_ID
        );
        checkId(
            "zoltu-word",
            string.concat(everyNetworkLine(), mechanismDataLine(hexDigits(ZOLTU_MECHANISM_ID))),
            ZOLTU_MECHANISM_ID
        );
    }

    function testATaggedRecordIsItsLeadingWordWhateverAHandlerWouldClaim() external {
        (string memory dir, string memory path) = writeRecord(
            "tagged-claimed",
            string.concat(
                everyNetworkLine(), mechanismDataLine(string.concat(hexDigits(MOCK_CREATE2_MECHANISM_ID), "00"))
            )
        );
        claim(MOCK_SALT_MECHANISM_ID, path);
        claim(MOCK_CREATE2_MECHANISM_ID, path);
        expectNoHandlerAsked();
        bytes32 id = this.externalRecordedMechanismId(path);
        removeRecord(dir);
        assertEq(id, MOCK_CREATE2_MECHANISM_ID);
    }

    function testMechanismDataShorterThanAWordIsUnreadable() external {
        checkUnreadable("one-byte", string.concat(everyNetworkLine(), mechanismDataLine("01")));
        checkUnreadable(
            "one-digit-short",
            string.concat(everyNetworkLine(), mechanismDataLine(vm.replace(hexDigits(WORD), "6978", "697")))
        );
        checkUnreadable("empty", string.concat(everyNetworkLine(), mechanismDataLine("")));
    }

    function testMechanismDataNotAHexLiteralIsUnreadable() external {
        checkUnreadable(
            "abi-encode",
            string.concat(
                everyNetworkLine(), "bytes constant MECHANISM_DATA = abi.encode(bytes32(", vm.toString(WORD), "));\n"
            )
        );
        checkUnreadable(
            "bare-word",
            string.concat(everyNetworkLine(), "bytes constant MECHANISM_DATA = ", vm.toString(WORD), "00000000;\n")
        );
        checkUnreadable("wrapped-without-value", string.concat(everyNetworkLine(), "bytes constant MECHANISM_DATA =\n"));
        checkUnreadable(
            "split-value",
            string.concat(
                everyNetworkLine(), "bytes constant MECHANISM_DATA = hex\"", hexDigits(WORD), "\" hex\"00\";\n"
            )
        );
    }

    function testAnUntaggedRecordIsTheOneHandlerClaimingIt() external {
        (string memory dir, string memory path) = writeRecord("legacy-create2", untaggedRecord());
        claim(MOCK_CREATE2_MECHANISM_ID, path);
        expectEveryHandlerAskedOnce(path);
        bytes32 id = this.externalRecordedMechanismId(path);
        removeRecord(dir);
        assertEq(id, MOCK_CREATE2_MECHANISM_ID);

        (dir, path) = writeRecord("legacy-salt", untaggedRecord());
        claim(MOCK_SALT_MECHANISM_ID, path);
        expectEveryHandlerAskedOnce(path);
        id = this.externalRecordedMechanismId(path);
        removeRecord(dir);
        assertEq(id, MOCK_SALT_MECHANISM_ID);
    }

    function testAnUntaggedRecordNoHandlerClaimsIsUnclaimed() external {
        (string memory dir, string memory path) = writeRecord("legacy-unclaimed", untaggedRecord());
        expectEveryHandlerAskedOnce(path);
        vm.expectRevert(abi.encodeWithSelector(MechanismUnclaimed.selector, path));
        this.externalRecordedMechanismId(path);
        removeRecord(dir);
    }

    function testAnUntaggedRecordTwoHandlersClaimIsAmbiguous() external {
        (string memory dir, string memory path) = writeRecord("legacy-ambiguous", untaggedRecord());
        claim(MOCK_CREATE2_MECHANISM_ID, path);
        claim(MOCK_SALT_MECHANISM_ID, path);
        vm.expectRevert(abi.encodeWithSelector(LegacyRecordAmbiguous.selector, path));
        this.externalRecordedMechanismId(path);
        removeRecord(dir);
    }

    function testAHandlerRefusingLegacyRecordIdPropagates() external {
        (string memory dir, string memory path) = writeRecord("legacy-refused", untaggedRecord());
        vm.mockCallRevert(MOCK_MECHANISM_PROBE, legacyRecordIdCall(MOCK_SALT_MECHANISM_ID, path), abi.encode("refused"));
        vm.expectRevert(abi.encode("refused"));
        this.externalRecordedMechanismId(path);
        removeRecord(dir);
    }

    function testZoltuNeverClaimsALegacyRecord() external {
        (string memory dir, string memory path) = writeRecord("zoltu-legacy", untaggedRecord());
        assertEq(this.externalZoltuLegacyRecordId(path), 0);
        vm.expectRevert(abi.encodeWithSelector(MechanismUnclaimed.selector, path));
        this.externalZoltuOnlyRecordedMechanismId(path);
        removeRecord(dir);

        (dir, path) = writeRecord(
            "zoltu-tagged", string.concat(everyNetworkLine(), mechanismDataLine(hexDigits(MOCK_CREATE2_MECHANISM_ID)))
        );
        assertEq(this.externalZoltuLegacyRecordId(path), 0);
        removeRecord(dir);

        (dir, path) = writeRecord("zoltu-untagged-zoltu", everyNetworkLine());
        assertEq(this.externalZoltuLegacyRecordId(path), 0);
        removeRecord(dir);
    }

    function testTheReleasedEntryOfALegacyRecordIsTheClaimingMechanismsExpression() external {
        (string memory dir, string memory path) = writeRecord("released-legacy", untaggedRecord());
        claim(MOCK_CREATE2_MECHANISM_ID, path);
        string memory entry = this.externalReleasedSuiteEntry(path);
        removeRecord(dir);
        assertEq(
            entry,
            "        suites[0] = DeploySuite({\n" "            suite: \"Record@0_1_0\",\n"
            "            creationCode: Record_0_1_0_CREATION_CODE,\n"
            "            storedDeployedAddress: Record_0_1_0_DEPLOYED_ADDRESS,\n"
            "            storedBytecodeHash: Record_0_1_0_BYTECODE_HASH,\n"
            "            storedRuntimeCode: Record_0_1_0_RUNTIME_CODE,\n" "            artifactPath: \"\",\n"
            "            dependencies: abi.decode(Record_0_1_0_DEPENDENCIES, (DeployDependency[])),\n"
            "            mechanismData: Record_0_1_0_MECHANISM_DATA,\n" "            networks: new string[](0)\n"
            "        });\n"
        );
    }

    function testTheReleasedEntryOfAnUnclaimedRecordIsUnclaimed() external {
        (string memory dir, string memory path) = writeRecord("unclaimed", untaggedRecord());
        vm.expectRevert(abi.encodeWithSelector(MechanismUnclaimed.selector, path));
        this.externalReleasedSuiteEntry(path);
        removeRecord(dir);
    }

    function testTheReleasedEntryOfAnAmbiguousRecordIsAmbiguous() external {
        (string memory dir, string memory path) = writeRecord("ambiguous", untaggedRecord());
        claim(MOCK_CREATE2_MECHANISM_ID, path);
        claim(MOCK_SALT_MECHANISM_ID, path);
        vm.expectRevert(abi.encodeWithSelector(LegacyRecordAmbiguous.selector, path));
        this.externalReleasedSuiteEntry(path);
        removeRecord(dir);
    }
}
