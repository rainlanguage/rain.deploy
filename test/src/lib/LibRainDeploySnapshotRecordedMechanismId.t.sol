// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    DeployDeclaration,
    DeployDependency,
    DeploySuite,
    MechanismUnclaimed
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {FrozenSnapshotUnreadable, LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {LibRainDeployZoltuMechanism, ZOLTU_MECHANISM_ID} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {LibMockCreate2Mechanism} from "../../lib/LibMockCreate2Mechanism.sol";

contract LibRainDeploySnapshotRecordedMechanismIdTest is Test {
    string constant ROOT = "fixture-lib/recorded-mechanism-id";

    bytes32 constant WORD = 0x0123456789abcdef00112233445566778899aabbccddeeff0f1e2d3c4b5a6978;

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

    function externalRecordedMechanismId(string memory path) external view returns (bytes32) {
        return LibRainDeploySnapshot.recordedMechanismId(vm, path);
    }

    function externalReleasedSuiteEntry(string memory path) external view returns (string memory) {
        DeployDeclaration memory d;
        LibRainDeployZoltuMechanism.extend(d);
        LibMockCreate2Mechanism.extend(d);
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
        return LibRainDeploySnapshot.releasedSuiteEntry(vm, 0, path, template, d);
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
        checkId("zoltu", everyNetworkLine(), ZOLTU_MECHANISM_ID);
        checkId("zoltu-commented", string.concat(everyNetworkLine(), "/*\n", mechanismDataLine(hexDigits(WORD)), "*/\n"), ZOLTU_MECHANISM_ID);
    }

    function testTheIdIsTheLeadingWordOfMechanismData() external {
        checkId("exact-word", string.concat(everyNetworkLine(), mechanismDataLine(hexDigits(WORD))), WORD);
        checkId(
            "trailing-bytes",
            string.concat(mechanismDataLine(string.concat(hexDigits(WORD), "deadbeef")), everyNetworkLine()),
            WORD
        );
        checkId(
            "per-network",
            string.concat(
                perNetworkLine(137),
                mechanismDataLine(string.concat(hexDigits(WORD), hexDigits(ZOLTU_MECHANISM_ID))),
                perNetworkLine(42161)
            ),
            WORD
        );
        checkId(
            "wrapped",
            string.concat(
                everyNetworkLine(), "bytes constant MECHANISM_DATA =\n    hex\"", hexDigits(WORD), "00\";\n"
            ),
            WORD
        );
        checkId(
            "zoltu-word",
            string.concat(everyNetworkLine(), mechanismDataLine(hexDigits(ZOLTU_MECHANISM_ID))),
            ZOLTU_MECHANISM_ID
        );
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
                everyNetworkLine(),
                "bytes constant MECHANISM_DATA = abi.encode(bytes32(", vm.toString(WORD), "));\n"
            )
        );
        checkUnreadable(
            "bare-word",
            string.concat(everyNetworkLine(), "bytes constant MECHANISM_DATA = ", vm.toString(WORD), "00000000;\n")
        );
        checkUnreadable(
            "wrapped-without-value",
            string.concat(everyNetworkLine(), "bytes constant MECHANISM_DATA =\n")
        );
        checkUnreadable(
            "split-value",
            string.concat(everyNetworkLine(), "bytes constant MECHANISM_DATA = hex\"", hexDigits(WORD), "\" hex\"00\";\n")
        );
    }

    function testARecordWhoseLeadingWordNoMechanismClaimsIsUnclaimed() external {
        (string memory dir, string memory path) =
            writeRecord("unclaimed", string.concat(everyNetworkLine(), mechanismDataLine(hexDigits(WORD))));
        vm.expectRevert(abi.encodeWithSelector(MechanismUnclaimed.selector, path));
        this.externalReleasedSuiteEntry(path);
        removeRecord(dir);
    }
}
