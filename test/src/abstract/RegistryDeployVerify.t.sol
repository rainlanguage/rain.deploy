// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {DeployDeclaration, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerify} from "../../../src/abstract/RainDeployVerify.sol";
import {RegistryDeploySuites, ParameterisedContract} from "../../../src/abstract/RegistryDeploySuites.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";
import {
    BYTECODE_HASH as BYTECODE_HASH_0_1_19,
    CREATION_CODE as CREATION_CODE_0_1_19
} from "../../../src/generated/0_1_19/TimelockController.sol";
import {LibTimelockController} from "../../../src/lib/LibTimelockController.sol";
import {MockTimelockControllerGeneration} from "../../concrete/MockTimelockControllerGeneration.sol";
import {MockTimelockControllerImmutableGeneration} from "../../concrete/MockTimelockControllerImmutableGeneration.sol";

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
/// Everything is inherited, which is the point: `RegistryDeploySuites` says
/// which registries and which releases exist and `RainDeployVerify` says what
/// is true of them. Its own tests deploy each frozen code record's creation code with its
/// declaration's reference arguments, which only this repo's declaration
/// carries, and pin against fixtures that the check walks every code record
/// under its root and refuses a record whose creation code deploys other code.
///
/// The retired `AddressRegistry` releases declare, as their own `networks`, the
/// networks they were live on at retirement.
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

    /// Where the hash-mismatch fixture is written. Its own tree, apart from
    /// the other fixtures, because forge runs them in parallel.
    string constant HASH_FIXTURE_ROOT = "test/generated-deploy-verify-hash";

    /// Where the two-declaration fixture is written. Its own tree, apart from
    /// the other fixtures, because forge runs them in parallel.
    string constant TWO_DECLARED_FIXTURE_ROOT = "test/generated-deploy-verify-two";

    /// Reverts unless every frozen code record under `recordRoot` that
    /// `declared` names deploys its `CREATION_CODE`, with that declaration's
    /// `referenceConstructorArgs`, to runtime code hashing to its
    /// `BYTECODE_HASH`.
    /// @param recordRoot The record root to read the code records from.
    /// @param declared The parameterised contracts the code records are of.
    /// @return The number of code records checked.
    function checkFrozenCodeRecordsDeploy(string memory recordRoot, ParameterisedContract[] memory declared)
        internal
        returns (uint256)
    {
        string[] memory names = new string[](declared.length);
        for (uint256 i = 0; i < declared.length; i++) {
            names[i] = parameterisedContractName(declared[i]);
        }
        // Every code record's file name is one of `names`, so `matched`
        // indexes `declared`.
        (, string[] memory codeRecords) =
            partitionFrozenRecords(LibRainDeploySnapshot.frozenSnapshotPaths(vm, recordRoot), names);
        for (uint256 i = 0; i < codeRecords.length; i++) {
            string memory path = codeRecords[i];
            uint256 matched = codeRecordIndex(path, names);

            string[] memory lines = LibRainDeploySnapshot.splitRecordLines(vm, vm.readFile(path));
            bytes32 recordedHash = declaredBytes32(path, lines, declarationLine(path, lines, BYTECODE_HASH_DECLARATION));
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
        return checkFrozenCodeRecordsDeploy(recordRoot, parameterisedContracts());
    }

    /// External wrapper so `vm.expectRevert` lands at the right call depth.
    /// @param recordRoot The record root to read the code records from.
    /// @param declared The parameterised contracts the code records are of.
    function externalCheckFrozenCodeRecordsDeployAgainst(
        string memory recordRoot,
        ParameterisedContract[] memory declared
    ) external returns (uint256) {
        return checkFrozenCodeRecordsDeploy(recordRoot, declared);
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

    /// A code record whose `CREATION_CODE` deploys its own `RUNTIME_CODE` but
    /// whose `BYTECODE_HASH` names other code MUST be refused against the
    /// declared hash, not the hash of the declared runtime code.
    function testFrozenCodeRecordDeployingOtherThanItsHashIsRefused() external {
        if (vm.exists(HASH_FIXTURE_ROOT)) {
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.removeDir(HASH_FIXTURE_ROOT, true);
        }
        string memory path = string.concat(HASH_FIXTURE_ROOT, "/0_1_19/TimelockController.sol");
        bytes32 otherHash = keccak256(type(MockTimelockControllerGeneration).runtimeCode);
        string memory record = vm.replace(
            vm.readFile("src/generated/0_1_19/TimelockController.sol"),
            vm.replace(vm.toString(BYTECODE_HASH_0_1_19), "0x", ""),
            vm.replace(vm.toString(otherHash), "0x", "")
        );
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(string.concat(HASH_FIXTURE_ROOT, "/0_1_19"), true);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(path, record);

        vm.expectRevert(
            abi.encodeWithSelector(FrozenCodeRecordDeploysOtherCode.selector, path, otherHash, BYTECODE_HASH_0_1_19)
        );
        this.externalCheckFrozenCodeRecordsDeploy(HASH_FIXTURE_ROOT);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(HASH_FIXTURE_ROOT, true);
    }

    /// With two parameterised contracts declared, each code record MUST be
    /// deployed with its own declaration's `referenceConstructorArgs`. The
    /// second declaration's contract keeps its `minDelay` in an immutable, so
    /// the first declaration's args deploy it to other code.
    function testEachCodeRecordDeploysWithItsOwnDeclaration() external {
        if (vm.exists(TWO_DECLARED_FIXTURE_ROOT)) {
            //forge-lint: disable-next-line(unsafe-cheatcode)
            vm.removeDir(TWO_DECLARED_FIXTURE_ROOT, true);
        }
        string memory dir = string.concat(TWO_DECLARED_FIXTURE_ROOT, "/0_1_19");
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.createDir(dir, true);
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(
            string.concat(dir, "/TimelockController.sol"), vm.readFile("src/generated/0_1_19/TimelockController.sol")
        );

        ParameterisedContract[] memory declared = new ParameterisedContract[](2);
        declared[0] = parameterisedContracts()[0];
        declared[1] = ParameterisedContract({
            artifactPath: "test/concrete/MockTimelockControllerImmutableGeneration.sol:MockTimelockControllerImmutableGeneration",
            referenceConstructorArgs: LibTimelockController.timelockConstructorArgs(7, address(1)),
            spdxLicenseIdentifier: "LicenseRef-DCL-1.0",
            copyrightText: "Copyright (c) 2020 Rain Open Source Software Ltd"
        });

        bytes memory creationCode = type(MockTimelockControllerImmutableGeneration).creationCode;
        bytes memory runtimeCode = deployedCode(abi.encodePacked(creationCode, declared[1].referenceConstructorArgs));
        assertNotEq(
            keccak256(deployedCode(abi.encodePacked(creationCode, declared[0].referenceConstructorArgs))),
            keccak256(runtimeCode)
        );

        string memory path = string.concat(dir, "/MockTimelockControllerImmutableGeneration.sol");
        string memory record = string.concat(
            "bytes32 constant BYTECODE_HASH = bytes32(",
            vm.toString(keccak256(runtimeCode)),
            ");\nbytes constant CREATION_CODE = hex\"",
            vm.replace(vm.toString(creationCode), "0x", ""),
            "\";\nbytes constant RUNTIME_CODE = hex\"",
            vm.replace(vm.toString(runtimeCode), "0x", ""),
            "\";\n"
        );
        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.writeFile(path, record);
        checkFrozenCodeRecord(path, record);

        assertEq(this.externalCheckFrozenCodeRecordsDeployAgainst(TWO_DECLARED_FIXTURE_ROOT, declared), 2);

        //forge-lint: disable-next-line(unsafe-cheatcode)
        vm.removeDir(TWO_DECLARED_FIXTURE_ROOT, true);
    }

    /// The runtime code `initCode` deploys.
    /// @param initCode The creation code with its constructor args.
    /// @return The deployed code.
    function deployedCode(bytes memory initCode) internal returns (bytes memory) {
        address deployed;
        assembly ("memory-safe") {
            deployed := create(0, add(initCode, 0x20), mload(initCode))
        }
        assertNotEq(deployed, address(0));
        return deployed.code;
    }

    /// The retired `AddressRegistry` releases are required only on the networks they were live on at retirement;
    /// every other suite on every declared network.
    function testAddressRegistryReleasesAreRequiredOnlyWhereTheyWereLive() external pure {
        DeployDeclaration memory d = declaration();
        DeploySuite[] memory suites = allSuites(d);
        string[] memory live = addressRegistryNetworks();
        uint256 retired = 0;
        for (uint256 i = 0; i < suites.length; i++) {
            bool isRetired = keccak256(bytes(suiteKeyName(suites[i].suite))) == keccak256(bytes(ADDRESS_REGISTRY_SUITE));
            if (isRetired) {
                retired++;
                assertEq(keccak256(abi.encode(suites[i].networks)), keccak256(abi.encode(live)), suites[i].suite);
            } else {
                assertEq(keccak256(abi.encode(suites[i].networks)), keccak256(abi.encode(d.networks)), suites[i].suite);
            }
            for (uint256 j = 0; j < d.networks.length; j++) {
                assertEq(requiresSuiteOn(suites[i], d.networks[j]), !isRetired || isListed(live, d.networks[j]));
            }
        }
        assertGt(retired, 0, "no AddressRegistry release declared");
    }

    function isListed(string[] memory networks, string memory network) internal pure returns (bool) {
        for (uint256 i = 0; i < networks.length; i++) {
            if (keccak256(bytes(networks[i])) == keccak256(bytes(network))) {
                return true;
            }
        }
        return false;
    }
}
