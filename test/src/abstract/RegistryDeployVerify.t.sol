// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {RainDeployVerify} from "../../../src/abstract/RainDeployVerify.sol";
import {RainDeployVerifySnapshotBase} from "../../../src/abstract/RainDeployVerifySnapshotBase.sol";
import {RegistryDeploySuites, ParameterisedContract} from "../../../src/abstract/RegistryDeploySuites.sol";
import {LibRainDeploySnapshot} from "../../../src/lib/LibRainDeploySnapshot.sol";

/// @title RegistryDeployVerifyTest
/// @notice This repo's own registry declaration bound to `RainDeployVerify` —
/// the same single line a consumer writes, so every inherited check that
/// reaches this contract reaches every consumer that has bumped.
///
/// `RegistryDeploySuites` says which registries and which releases exist and
/// `RainDeployVerify` says what is true of them. The one override names the
/// code records a release freezes beside the suites' — the parameterised
/// contracts — so the frozen-record walk reads them as code and not as deploys.
/// The one test of its own deploys each frozen code record's creation code
/// with its declaration's reference arguments, which only this repo's
/// declaration carries.
///
/// The chain half is red until every release declared here is live on every
/// supported network, which is why the deploy is dispatched before the release
/// PR merges. That is the check working: "nothing is deployed at the address
/// `LibAddressRegistry` reads" is the single most important fact about these
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
    /// @inheritdoc RainDeployVerifySnapshotBase
    function frozenCodeRecordNames() internal pure override returns (string[] memory) {
        return parameterisedContractNames();
    }

    /// Every frozen code record's `CREATION_CODE`, deployed with its
    /// declaration's `referenceConstructorArgs`, MUST deploy runtime code
    /// hashing to the record's `BYTECODE_HASH`. The args are today's
    /// declaration's, applied to every frozen generation, so a declaration
    /// change MUST keep them valid for every frozen record.
    function testEveryFrozenCodeRecordDeploysItsRecordedHash() external {
        (, string[] memory codeRecords) =
            partitionFrozenRecords(LibRainDeploySnapshot.frozenSnapshotPaths(vm), frozenCodeRecordNames());
        ParameterisedContract[] memory declared = parameterisedContracts();
        assertGt(codeRecords.length, 0);
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
            assertNotEq(deployed, address(0), path);
            assertEq(deployed.codehash, recordedHash, path);
        }
    }
}
