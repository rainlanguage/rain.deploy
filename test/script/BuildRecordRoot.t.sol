// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibRainDeploySnapshot} from "../../src/lib/LibRainDeploySnapshot.sol";
import {BuildRecordRootHarness} from "../concrete/BuildRecordRootHarness.sol";

contract BuildRecordRootTest is Test {
    string constant FIXTURE_ROOT = "test/generated-build-record-root";

    /// A cheatcode write is not undone by a revert, so a failure leaves
    /// generated sources on disk and the next run reads THOSE.
    function resetFixture(string memory root) internal {
        if (vm.exists(root)) {
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.removeDir(root, true);
        }
    }

    function testRegenerateSnapshotsWritesUnderTheRecordRoot() external {
        resetFixture(FIXTURE_ROOT);
        BuildRecordRootHarness harness = new BuildRecordRootHarness(FIXTURE_ROOT);
        string[] memory names = harness.externalSnapshotContractNames();

        harness.externalRegenerateSnapshots();

        bool[] memory written = new bool[](names.length);
        string[] memory regenerated = new string[](names.length);
        string[] memory committed = new string[](names.length);
        for (uint256 i = 0; i < names.length; i++) {
            string memory path =
                LibRainDeploySnapshot.pathForSnapshot(FIXTURE_ROOT, LibRainDeploySnapshot.CANDIDATE, names[i]);
            written[i] = vm.exists(path);
            regenerated[i] = written[i] ? vm.readFile(path) : "";
            committed[i] = vm.readFile(LibRainDeploySnapshot.pathForSnapshot(LibRainDeploySnapshot.CANDIDATE, names[i]));
        }

        resetFixture(FIXTURE_ROOT);

        assertTrue(names.length > 0, "no contract is generated, so nothing was asserted");
        for (uint256 i = 0; i < names.length; i++) {
            assertTrue(written[i], string.concat("regeneration wrote nothing under the record root: ", names[i]));
            assertEq(
                regenerated[i],
                committed[i],
                string.concat("snapshot under the record root is not the committed one: ", names[i])
            );
        }
    }
}
