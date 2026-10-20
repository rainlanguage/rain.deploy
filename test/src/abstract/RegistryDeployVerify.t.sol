// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeploySuite, RainDeploySuitesBase} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerify} from "../../../src/abstract/RainDeployVerify.sol";
import {RainDeployVerifySnapshotBase} from "../../../src/abstract/RainDeployVerifySnapshotBase.sol";
import {RegistryDeploySuites, ParameterisedContract} from "../../../src/abstract/RegistryDeploySuites.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {
    BYTECODE_HASH as BYTECODE_HASH_0_1_19,
    CREATION_CODE as CREATION_CODE_0_1_19
} from "../../../src/generated/0_1_19/TimelockController.sol";
import {MockTimelockControllerGeneration} from "../../concrete/MockTimelockControllerGeneration.sol";

/// A frozen code record's `CREATION_CODE` deploys code that does not hash to
/// its `BYTECODE_HASH`.
/// @param path The record file.
/// @param recorded The record's `BYTECODE_HASH`.
/// @param deployed The deployed code's hash.
error FrozenCodeRecordDeploysOtherCode(string path, bytes32 recorded, bytes32 deployed);

/// @title RegistryDeployVerifyTest
/// @notice This repo's own registry declaration bound to `RainDeployVerify` —
/// the same inheritance a consumer writes, so a check that reaches this
/// contract reaches every consumer that has bumped, and one that does not reach
/// it never shipped.
///
/// Everything is inherited but two overrides, which is the point:
/// `RegistryDeploySuites` says which registries and which releases exist and
/// `RainDeployVerify` says what is true of them. The first names the
/// code records a release freezes beside the suites' — the parameterised
/// contracts — so the frozen-record walk reads them as code and not as deploys.
/// Its own tests deploy each frozen code record's creation code with its
/// declaration's reference arguments, which only this repo's declaration
/// carries, and pin against fixtures that the check walks every code record
/// under its root and refuses a record whose creation code deploys other code.
///
/// The second binds `registryRequiresSuiteOn`, so the retired `AddressRegistry`
/// releases are required only on the networks they were live on at retirement.
///
/// The chain half is red until every release declared here is live on every
/// supported network, which is why the deploy is dispatched before the tag is
/// pushed. That is the check working: "nothing is deployed at the address
/// `LibConfigRegistry` reads" is the single most important fact about these
/// pins, and no snapshot assertion can discover it — a perfectly consistent set
/// of pins for a contract that exists nowhere passes every one of them.
///
/// What the inherited assertions do with a declaration is the abstracts'
/// business and is pinned against fixtures rather than here:
/// `RainDeployVerifyChainTest` for a set the matrix must check on every
/// network, `RainDeployVerifyChainCandidateTest` for the candidate it must
/// ignore, `RainDeployVerifyChainEmptyTest` for a set with nothing in it, which
/// it must not fork for, and `RainDeployVerifySnapshotBaseTest` for the
/// snapshot groups at every position and every shape of declaration.
contract RegistryDeployVerifyTest is RegistryDeploySuites, RainDeployVerify {
    /// Where the deploys-other-code fixture is written. Its own tree: no other
    /// contract reads or clears it, and the record check reads `src/generated`.
    string constant DEPLOYS_OTHER_FIXTURE_ROOT = "test/generated-deploy-verify";

    /// Where the record-count fixture is written. Its own tree, apart from the
    /// deploys-other-code fixture, because forge runs the two in parallel.
    string constant COUNT_FIXTURE_ROOT = "test/generated-deploy-verify-count";

    /// @inheritdoc RainDeployVerifySnapshotBase
    function frozenCodeRecordNames() internal pure override returns (string[] memory) {
        return parameterisedContractNames();
    }

    /// Reverts unless every frozen code record under `recordRoot` deploys its
    /// `CREATION_CODE`, with its declaration's `referenceConstructorArgs`, to
    /// runtime code hashing to its `BYTECODE_HASH`.
    /// @param recordRoot The record root to read the code records from.
    /// @return The number of code records checked.
    function checkFrozenCodeRecordsDeploy(string memory recordRoot) internal returns (uint256) {
        (, string[] memory codeRecords) =
            partitionFrozenRecords(LibRainDeploySnapshot.frozenSnapshotPaths(vm, recordRoot), frozenCodeRecordNames());
        ParameterisedContract[] memory declared = parameterisedContracts();
        for (uint256 i = 0; i < codeRecords.length; i++) {
            string memory path = codeRecords[i];
            uint256 matched = codeRecordIndex(path, frozenCodeRecordNames());
            assertLt(matched, declared.length, path);

            string[] memory lines = vm.split(LibRainDeploySnapshot.withoutBlockComments(vm, vm.readFile(path)), "\n");
            bytes32 recordedHash = declaredBytecodeHash(lines, declarationLine(path, lines, BYTECODE_HASH_DECLARATION));
            bytes memory initCode = abi.encodePacked(
                declaredBytes(path, lines, declarationLine(path, lines, CREATION_CODE_DECLARATION)),
                declared[matched].referenceConstructorArgs
            );

            address deployed;
            assembly ("memory-safe") {
                deployed := create(0, add(initCode, 0x20), mload(initCode))
            }
            if (deployed.codehash != recordedHash) {
                revert FrozenCodeRecordDeploysOtherCode(path, recordedHash, deployed.codehash);
            }
        }
        return codeRecords.length;
    }

    /// External wrapper so `vm.expectRevert` lands at the right call depth.
    /// @param recordRoot The record root to read the code records from.
    function externalCheckFrozenCodeRecordsDeploy(string memory recordRoot) external returns (uint256) {
        return checkFrozenCodeRecordsDeploy(recordRoot);
    }

    /// Every frozen code record's `CREATION_CODE`, deployed with its
    /// declaration's `referenceConstructorArgs`, MUST deploy runtime code
    /// hashing to the record's `BYTECODE_HASH`. The args are today's
    /// declaration's, applied to every frozen generation, so a declaration
    /// change MUST keep them valid for every frozen record.
    function testEveryFrozenCodeRecordDeploysItsRecordedHash() external {
        assertGt(this.externalCheckFrozenCodeRecordsDeploy(LibRainDeploySnapshot.LIB_FS_ROOT), 0);
    }

    /// Every code record under the root MUST be checked: a root holding two
    /// valid generations reports exactly two, and with either one swapped to
    /// deploy other code the walk refuses that one, so the record the walk
    /// reaches second is deployed whichever order `readDir` lists them in.
    function testEveryCodeRecordUnderTheRootIsChecked() external {
        // A cheatcode write is not undone by a revert, so a failed run leaves
        // records under the root that this run would count.
        if (vm.exists(COUNT_FIXTURE_ROOT)) {
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.removeDir(COUNT_FIXTURE_ROOT, true);
        }
        string[2] memory tags = ["0_1_18", "0_1_19"];
        string[2] memory paths;
        string[2] memory records;
        for (uint256 i = 0; i < tags.length; i++) {
            string memory dir = string.concat(COUNT_FIXTURE_ROOT, "/", tags[i]);
            paths[i] = string.concat(dir, "/TimelockController.sol");
            records[i] = vm.readFile(string.concat("src/generated/", tags[i], "/TimelockController.sol"));
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.createDir(dir, true);
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.writeFile(paths[i], records[i]);
        }

        assertEq(this.externalCheckFrozenCodeRecordsDeploy(COUNT_FIXTURE_ROOT), 2);

        for (uint256 bad = 0; bad < tags.length; bad++) {
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.writeFile(
                paths[bad],
                vm.replace(
                    records[bad],
                    vm.replace(vm.toString(CREATION_CODE_0_1_19), "0x", ""),
                    vm.replace(vm.toString(type(MockTimelockControllerGeneration).creationCode), "0x", "")
                )
            );
            vm.expectRevert(
                abi.encodeWithSelector(
                    FrozenCodeRecordDeploysOtherCode.selector,
                    paths[bad],
                    BYTECODE_HASH_0_1_19,
                    keccak256(type(MockTimelockControllerGeneration).runtimeCode)
                )
            );
            this.externalCheckFrozenCodeRecordsDeploy(COUNT_FIXTURE_ROOT);
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.writeFile(paths[bad], records[bad]);
        }

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(COUNT_FIXTURE_ROOT, true);
    }

    /// A code record whose `RUNTIME_CODE` and `BYTECODE_HASH` agree but whose
    /// `CREATION_CODE` deploys other code MUST be refused. The fixture is the
    /// real `0_1_19` record with only its `CREATION_CODE` swapped for
    /// `MockTimelockControllerGeneration`'s.
    function testFrozenCodeRecordDeployingOtherCodeIsRefused() external {
        string memory path = string.concat(DEPLOYS_OTHER_FIXTURE_ROOT, "/0_1_19/TimelockController.sol");
        string memory record = vm.replace(
            vm.readFile("src/generated/0_1_19/TimelockController.sol"),
            vm.replace(vm.toString(CREATION_CODE_0_1_19), "0x", ""),
            vm.replace(vm.toString(type(MockTimelockControllerGeneration).creationCode), "0x", "")
        );
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(string.concat(DEPLOYS_OTHER_FIXTURE_ROOT, "/0_1_19"), true);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(path, record);

        checkFrozenCodeRecord(path, record);

        vm.expectRevert(
            abi.encodeWithSelector(
                FrozenCodeRecordDeploysOtherCode.selector,
                path,
                BYTECODE_HASH_0_1_19,
                keccak256(type(MockTimelockControllerGeneration).runtimeCode)
            )
        );
        this.externalCheckFrozenCodeRecordsDeploy(DEPLOYS_OTHER_FIXTURE_ROOT);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(DEPLOYS_OTHER_FIXTURE_ROOT, true);
    }

    /// @inheritdoc RainDeploySuitesBase
    function requiresSuiteOn(DeploySuite memory suite, string memory network) internal pure override returns (bool) {
        return registryRequiresSuiteOn(suite, network);
    }

    /// The chain group reads the declaration's narrowing.
    function testRequiresSuiteOnIsTheRegistryNarrowing() external pure {
        DeploySuite memory suite;
        suite.suite = "address-registry@0_1_18";
        assertFalse(requiresSuiteOn(suite, "new_network"));
        assertTrue(requiresSuiteOn(suite, LibRainDeploy.BASE));
        suite.suite = "config-registry";
        assertTrue(requiresSuiteOn(suite, "new_network"));
    }
}
