// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration, DeployDependency, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";

contract LibRainDeploySnapshotWriteReleasedSuitesLibMemoryTest is Test {
    string constant ROOT = "fixture-lib/write-released-suites-lib-memory";
    string constant RECORD_ROOT = "fixture-lib/write-released-suites-lib-memory/record";
    string constant LIB_DIR = "fixture-lib/write-released-suites-lib-memory/lib";
    string constant CONTRACT = "Record";
    uint256 constant RECORDS = 8;
    uint256 constant CODE_BYTES = 0x8000;

    function setUp() external {
        if (vm.exists(ROOT)) {
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.removeDir(ROOT, true);
        }
    }

    function declaration() internal pure returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployZoltuMechanism.extend(d);
        return d;
    }

    function template() internal pure returns (DeploySuite memory) {
        return DeploySuite({
            networks: new string[](0),
            suite: "record",
            creationCode: "",
            storedDeployedAddress: address(0),
            storedBytecodeHash: bytes32(0),
            storedRuntimeCode: "",
            artifactPath: "src/concrete/Record.sol:Record",
            dependencies: new DeployDependency[](0),
            mechanismData: "",
            describedByMeta: ""
        });
    }

    /// Records of real size, so the record text dominates what each one allocates.
    function writeRecords() internal returns (string[] memory) {
        string memory code = vm.replace(vm.toString(new bytes(CODE_BYTES)), "0x", "");
        string memory text = string.concat(
            "address constant DEPLOYED_ADDRESS = address(",
            vm.toString(address(1)),
            ");\n\nbytes constant CREATION_CODE =\n    hex\"",
            code,
            "\";\n"
        );
        string[] memory paths = new string[](RECORDS);
        for (uint256 i = 0; i < RECORDS; i++) {
            string memory dir = string.concat(RECORD_ROOT, "/0_0_", vm.toString(i + 1));
            paths[i] = string.concat(dir, "/", CONTRACT, ".sol");
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.createDir(dir, true);
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.writeFile(paths[i], text);
        }
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(LIB_DIR, true);
        return paths;
    }

    function freeMemoryPointer() internal pure returns (uint256) {
        uint256 pointer;
        assembly ("memory-safe") {
            pointer := mload(0x40)
        }
        return pointer;
    }

    function readEachRecordOnceMemory(string[] memory paths) external view returns (uint256) {
        uint256 start = freeMemoryPointer();
        for (uint256 i = 0; i < paths.length; i++) {
            LibRainDeploySnapshot.recordLines(vm, paths[i], vm.readFile(paths[i]));
        }
        return freeMemoryPointer() - start;
    }

    function writeReleasedSuitesLibMemory() external returns (uint256) {
        uint256 start = freeMemoryPointer();
        LibRainDeploySnapshot.writeReleasedSuitesLib(
            vm,
            LIB_DIR,
            RECORD_ROOT,
            CONTRACT,
            template(),
            declaration(),
            LibRainDeploySnapshot.suitesImportPathInThisRepo()
        );
        return freeMemoryPointer() - start;
    }

    /// Memory gas is quadratic in one frame's allocations, so a second copy of every record compounds across releases.
    function testWriteReleasedSuitesLibAllocatesOneReadOfEachRecord() external {
        string[] memory paths = writeRecords();
        uint256 readOnce = this.readEachRecordOnceMemory(paths);
        uint256 written = this.writeReleasedSuitesLibMemory();
        uint256 recordBytes = bytes(vm.readFile(paths[0])).length;
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(ROOT, true);

        assertGt(readOnce, RECORDS * recordBytes);
        assertLt(written, readOnce + RECORDS * recordBytes);
    }
}
