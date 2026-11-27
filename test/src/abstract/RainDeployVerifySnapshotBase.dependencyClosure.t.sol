// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    DeployCandidate,
    DeployDeclaration,
    DeployDependency,
    DeploySuite,
    ExternalDeployment
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifySnapshotBase} from "../../../src/abstract/RainDeployVerifySnapshotBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {ExampleDeploySuites} from "../../abstract/ExampleDeploySuites.sol";
import {LibBeaconTest} from "../../lib/LibBeaconTest.sol";

contract RainDeployVerifySnapshotBaseDependencyClosureTest is ExampleDeploySuites, RainDeployVerifySnapshotBase {
    address constant EXTERNAL = address(0xe000);
    bytes constant EXTERNAL_CODE = hex"ee";
    uint256 constant FEWER_SUITES = 8;
    uint256 constant LARGE_CODE = 2048;

    function declaration() internal view override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        addExample(d);
        return d;
    }

    /// The creation code `LibDataContract.contractCreationCode` builds of `data`.
    function dataContract(bytes memory data) internal pure returns (bytes memory) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return abi.encodePacked(hex"61", uint16(data.length + 1), hex"80600c6000396000f300", data);
    }

    function key(uint256 i) internal pure returns (string memory) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return string(abi.encodePacked("s", bytes1(uint8(0x61 + i / 26)), bytes1(uint8(0x61 + i % 26))));
    }

    /// `released` then `candidates` Zoltu suites on Arbitrum One, each with `size` bytes of code past its index and
    /// depending on the external, or with `chained` on the suite before it where there is one.
    function synthetic(uint256 released, uint256 candidates, uint256 size, bool chained)
        internal
        pure
        returns (DeployDeclaration memory)
    {
        DeployDeclaration memory d;
        LibRainDeployZoltuMechanism.extend(d);
        d.externalDeployments = new ExternalDeployment[](1);
        d.externalDeployments[0] = ExternalDeployment({deployedAddress: EXTERNAL, codeHash: keccak256(EXTERNAL_CODE)});
        d.released = new DeploySuite[](released);
        d.candidates = new DeployCandidate[](candidates);
        DeployDependency memory previous = DeployDependency({deployedAddress: EXTERNAL, runtimeCode: EXTERNAL_CODE});
        for (uint256 i = 0; i < released + candidates; i++) {
            bytes memory data = bytes.concat(abi.encode(i), new bytes(size));
            DeploySuite memory suite = LibBeaconTest.zoltuSuite(
                key(i), dataContract(data), bytes.concat(hex"00", data), "test/synthetic.sol:Synthetic"
            );
            suite.networks = new string[](1);
            suite.networks[0] = LibRainDeploy.ARBITRUM_ONE;
            suite.dependencies = new DeployDependency[](1);
            suite.dependencies[0] = previous;
            if (chained) {
                previous = DeployDependency({
                    deployedAddress: suite.storedDeployedAddress, runtimeCode: suite.storedRuntimeCode
                });
            }
            if (i < released) {
                d.released[i] = suite;
            } else {
                d.candidates[i - released] = DeployCandidate({snapshot: suite, unanchorableReason: ""});
            }
        }
        return d;
    }

    function freeMemoryPointer() internal pure returns (uint256) {
        uint256 pointer;
        assembly ("memory-safe") {
            pointer := mload(0x40)
        }
        return pointer;
    }

    /// The memory `testSnapshotInternallyConsistent`'s loop allocates over `count` candidates of `size` bytes of code.
    function perSuiteCheckMemory(uint256 count, uint256 size) internal returns (uint256) {
        DeployDeclaration memory d = synthetic(0, count, size, false);
        DeploySuite[] memory suites = allSuites(d);
        uint256 start = freeMemoryPointer();
        for (uint256 i = 0; i < suites.length; i++) {
            checkInternallyConsistent(d, suites[i]);
        }
        return freeMemoryPointer() - start;
    }

    /// Copying every candidate on each suite's closure costs memory for code quadratic in the suites.
    function testPerSuiteCheckMemoryForCodeGrowsLinearlyInSuites() external {
        uint256 fewer = perSuiteCheckMemory(FEWER_SUITES, LARGE_CODE) - perSuiteCheckMemory(FEWER_SUITES, 0);
        uint256 more = perSuiteCheckMemory(2 * FEWER_SUITES, LARGE_CODE) - perSuiteCheckMemory(2 * FEWER_SUITES, 0);
        assertLe(more, 3 * fewer);
    }

    function testPerSuiteCheckLeavesTheDeclaredSuitesUnchanged() external {
        DeployDeclaration memory d = synthetic(1, 2, 0, true);
        bytes memory declared = abi.encode(d.released, d.candidates);

        checkInternallyConsistent(d, d.released[0]);
        for (uint256 i = 0; i < d.candidates.length; i++) {
            checkInternallyConsistent(d, d.candidates[i].snapshot);
        }

        assertEq(abi.encode(d.released, d.candidates), declared);
    }
}
