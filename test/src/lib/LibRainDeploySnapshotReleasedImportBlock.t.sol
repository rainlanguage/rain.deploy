// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeployDeclaration} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {LibRainDeployZoltuMechanism, ZOLTU_MECHANISM_ID} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {LibMockCreate2Mechanism, MOCK_CREATE2_MECHANISM_ID} from "../../lib/LibMockCreate2Mechanism.sol";
import {LibMockSaltMechanism, MOCK_SALT_MECHANISM_ID} from "../../lib/LibMockSaltMechanism.sol";

contract LibRainDeploySnapshotReleasedImportBlockTest is Test {
    string constant ROOT = "fixture-lib/released-import-block";

    string constant SUITES_IMPORT =
        "import {DeployDependency, DeploySuite} from \"../abstract/RainDeploySuitesBase.sol\";\n";
    string constant ZOLTU_IMPORT =
        "import {LibRainDeployZoltuMechanism} from \"../lib/LibRainDeployZoltuMechanism.sol\";\n";
    string constant SALT_IMPORT = "import {LibMockSaltMechanism} from \"../../test/lib/LibMockSaltMechanism.sol\";\n";

    function declaration() internal pure returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployZoltuMechanism.extend(d);
        LibMockCreate2Mechanism.extend(d);
        LibMockSaltMechanism.extend(d);
        return d;
    }

    function tag(uint256 i) internal pure returns (string memory) {
        return string.concat("0_0_", vm.toString(i + 1));
    }

    /// A Zoltu record declares no `MECHANISM_DATA`; any other leads its `MECHANISM_DATA` with its id.
    function record(bytes32 id) internal pure returns (string memory) {
        string memory addressLine =
            string.concat("address constant DEPLOYED_ADDRESS = address(", vm.toString(address(1)), ");\n");
        if (id == ZOLTU_MECHANISM_ID) {
            return addressLine;
        }
        string memory digits = vm.replace(vm.toString(id), "0x", "");
        return string.concat(addressLine, "bytes constant MECHANISM_DATA = hex\"", digits, "\";\n");
    }

    /// One record per id, tagged `0_0_<i + 1>` in order.
    function writeRecords(string memory name, bytes32[] memory ids) internal returns (string memory, string[] memory) {
        string memory dir = string.concat(ROOT, "/", name);
        string[] memory paths = new string[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            string memory tagDir = string.concat(dir, "/", tag(i));
            paths[i] = string.concat(tagDir, "/Record.sol");
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.createDir(tagDir, true);
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.writeFile(paths[i], record(ids[i]));
        }
        return (dir, paths);
    }

    function importBlock(string memory name, bytes32[] memory ids) internal returns (string memory) {
        (string memory dir, string[] memory paths) = writeRecords(name, ids);
        string memory imports = LibRainDeploySnapshot.releasedImportBlock(vm, paths, declaration());
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(dir, true);
        return imports;
    }

    function recordImport(uint256 i, bool mechanismData) internal pure returns (string memory) {
        string memory prefix = string.concat("Record_", tag(i));
        string memory aliases = string.concat(
            aliased(prefix, "DEPLOYED_ADDRESS"),
            ",\n",
            aliased(prefix, "BYTECODE_HASH"),
            ",\n",
            aliased(prefix, "CREATION_CODE"),
            ",\n"
        );
        aliases = string.concat(aliases, aliased(prefix, "RUNTIME_CODE"), ",\n", aliased(prefix, "DEPENDENCIES"));
        if (mechanismData) {
            aliases = string.concat(aliases, ",\n", aliased(prefix, "MECHANISM_DATA"));
        }
        return string.concat("import {\n", aliases, "\n} from \"../generated/", tag(i), "/Record.sol\";\n\n");
    }

    function aliased(string memory prefix, string memory name) internal pure returns (string memory) {
        return string.concat("    ", name, " as ", prefix, "_", name);
    }

    function testEachMechanismImportOnceAtItsFirstRecordAndNoneForAnEmptyOne() external {
        bytes32[] memory ids = new bytes32[](4);
        ids[0] = ZOLTU_MECHANISM_ID;
        ids[1] = MOCK_SALT_MECHANISM_ID;
        ids[2] = MOCK_SALT_MECHANISM_ID;
        ids[3] = MOCK_CREATE2_MECHANISM_ID;
        string memory records =
            string.concat(recordImport(0, false), recordImport(1, true), recordImport(2, true), recordImport(3, true));
        assertEq(
            importBlock("zoltu-salt-salt-create2", ids),
            string.concat(SUITES_IMPORT, ZOLTU_IMPORT, SALT_IMPORT, "\n", records)
        );
    }

    function testTheMechanismImportsFollowTheRecordOrder() external {
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = MOCK_SALT_MECHANISM_ID;
        ids[1] = ZOLTU_MECHANISM_ID;
        assertEq(
            importBlock("salt-zoltu", ids),
            string.concat(SUITES_IMPORT, SALT_IMPORT, ZOLTU_IMPORT, "\n", recordImport(0, true), recordImport(1, false))
        );
    }

    function testARecordWithoutZoltuImportsNoZoltu() external {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = MOCK_SALT_MECHANISM_ID;
        assertEq(importBlock("salt", ids), string.concat(SUITES_IMPORT, SALT_IMPORT, "\n", recordImport(0, true)));
    }
}
