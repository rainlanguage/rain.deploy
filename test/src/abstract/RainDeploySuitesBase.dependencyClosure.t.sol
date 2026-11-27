// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {RAIN_COPYRIGHT_TEXT, RAIN_SPDX_LICENSE_IDENTIFIER} from "rain-sol-codegen-0.1.39/src/lib/LibCodeGen.sol";
import {
    DeployCandidate,
    DeployDeclaration,
    DeployDependency,
    DeployMechanismHandler,
    DeploySuite,
    RainDeploySuitesBase,
    SnapshotFile
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {DeploySuiteIndex, LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {LibBeaconTest} from "../../lib/LibBeaconTest.sol";

contract RainDeploySuitesBaseDependencyClosureTest is RainDeploySuitesBase, Test {
    string constant ROOT = "fixture-lib/write-suite-snapshot-closure";
    address constant SUBJECT = address(0x5000);
    address constant A = address(0xa000);
    address constant B = address(0xb000);

    /// Zoltu, but its snapshot etches the suite's dependency closure first, as a mechanism whose snapshot deploys
    /// the suite locally does.
    function closureSnapshotMechanism() internal pure returns (DeployMechanismHandler memory) {
        DeployMechanismHandler memory handler = LibRainDeployZoltuMechanism.handler();
        handler.writeSuiteSnapshot = closureThenSnapshot;
        return handler;
    }

    function closureThenSnapshot(
        DeployDeclaration memory d,
        DeploySuiteIndex memory index,
        Vm fileVm,
        SnapshotFile memory file,
        DeploySuite memory suite
    ) internal returns (string memory) {
        LibRainDeployDeclaration.etchDependencyClosure(
            d, index, fileVm, suite, LibRainDeployDeclaration.recordedOnly(d, suite)
        );
        return LibRainDeployZoltuMechanism.writeSuiteSnapshot(d, index, fileVm, file, suite);
    }

    /// Distinct creation code per suite, so each snapshot's Zoltu deploy lands at its own address.
    function suiteAt(string memory key, address at, DeployDependency[] memory dependencies)
        internal
        pure
        returns (DeploySuite memory)
    {
        DeploySuite memory suite = LibBeaconTest.zoltuSuite(
            key,
            bytes.concat(type(MockDeployable).creationCode, bytes20(at)),
            type(MockDeployable).runtimeCode,
            "test/concrete/MockDeployable.sol:MockDeployable"
        );
        suite.storedDeployedAddress = at;
        suite.dependencies = dependencies;
        suite.networks = new string[](1);
        suite.networks[0] = LibRainDeploy.ARBITRUM_ONE;
        return suite;
    }

    function deps(address at, bytes memory code) internal pure returns (DeployDependency[] memory) {
        DeployDependency[] memory list = new DeployDependency[](1);
        list[0] = DeployDependency({deployedAddress: at, runtimeCode: code});
        return list;
    }

    /// Release `a` depends on nothing, candidate `b` on `a`, candidate `subject` on `b`.
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.addMechanism(d, closureSnapshotMechanism());
        d.released = new DeploySuite[](1);
        d.released[0] = suiteAt("a@0_0_1", A, new DeployDependency[](0));
        d.candidates = new DeployCandidate[](2);
        d.candidates[0] = DeployCandidate({snapshot: suiteAt("b", B, deps(A, hex"aa")), unanchorableReason: ""});
        d.candidates[1] =
            DeployCandidate({snapshot: suiteAt("subject", SUBJECT, deps(B, hex"bb")), unanchorableReason: ""});
        return d;
    }

    function snapshotFile(string memory root, uint256 i) internal pure returns (SnapshotFile memory) {
        return SnapshotFile(
            root, "0_1_0", string.concat("Suite", vm.toString(i)), RAIN_SPDX_LICENSE_IDENTIFIER, RAIN_COPYRIGHT_TEXT
        );
    }

    function pointer(DeploySuite[] memory list) internal pure returns (uint256) {
        uint256 at;
        assembly ("memory-safe") {
            at := list
        }
        return at;
    }

    function pointer(address[][] memory list) internal pure returns (uint256) {
        uint256 at;
        assembly ("memory-safe") {
            at := list
        }
        return at;
    }

    function testSnapshotLoopOverEverySuiteBuildsTheSharedIndexOnce() external {
        string memory root = string.concat(ROOT, "/loop");
        DeployDeclaration memory d = declaration();
        DeploySuite[] memory suites = allSuites(d);
        DeploySuiteIndex memory index = LibRainDeployDeclaration.emptyIndex();
        uint256 writtenOverTheBuiltIndex = 0;

        for (uint256 i = 0; i < suites.length; i++) {
            bool built = index.built;
            uint256 builtSuites = pointer(index.suites);
            uint256 builtRecorded = pointer(index.recorded);
            writeSuiteSnapshot(d, index, vm, snapshotFile(root, i), suites[i]);
            if (built) {
                writtenOverTheBuiltIndex++;
                assertEq(pointer(index.suites), builtSuites);
                assertEq(pointer(index.recorded), builtRecorded);
            }
        }
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(root, true);

        assertTrue(index.built);
        assertEq(writtenOverTheBuiltIndex, 1);
        assertEq(A.code, hex"aa");
        assertEq(B.code, hex"bb");
    }

    function testSnapshotReachingTheClosureBuildsTheCallersIndex() external {
        string memory root = string.concat(ROOT, "/caller");
        DeployDeclaration memory d = declaration();
        DeploySuiteIndex memory index = LibRainDeployDeclaration.emptyIndex();

        writeSuiteSnapshot(d, index, vm, snapshotFile(root, 0), d.candidates[1].snapshot);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(root, true);

        assertEq(B.code, hex"bb");
        assertEq(A.code, hex"aa");
        assertTrue(index.built);
        assertEq(index.suites.length, 3);
    }
}
