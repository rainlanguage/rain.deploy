// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    DeployDeclaration,
    DescribedByMetaEmission,
    RainDeploySuitesBase
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";

/// @title RainDeploySuitesBaseDescribedByMetaEmissionBlockTest
/// @notice `describedByMetaEmissionBlock` answers the block declared for exactly the suite and chain asked about.
contract RainDeploySuitesBaseDescribedByMetaEmissionBlockTest is RainDeploySuitesBase, Test {
    function declaration() internal pure override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        return d;
    }

    function declaring(DescribedByMetaEmission[] memory emissions) internal pure returns (DeployDeclaration memory) {
        DeployDeclaration memory d = declaration();
        d.describedByMetaEmissions = emissions;
        return d;
    }

    function one(string memory suite, uint256 chainId, uint256 blockNumber)
        internal
        pure
        returns (DescribedByMetaEmission[] memory)
    {
        DescribedByMetaEmission[] memory emissions = new DescribedByMetaEmission[](1);
        emissions[0] = DescribedByMetaEmission({suite: suite, chainId: chainId, blockNumber: blockNumber});
        return emissions;
    }

    function testNoEmissionsDeclareNoBlock(string memory suite, uint256 chainId) external pure {
        (bool declared, uint256 blockNumber) = describedByMetaEmissionBlock(declaration(), suite, chainId);
        assertFalse(declared);
        assertEq(blockNumber, 0);
    }

    function testTheSuiteOnTheChainGetsItsBlock(string memory suite, uint256 chainId, uint256 blockNumber)
        external
        pure
    {
        (bool declared, uint256 found) =
            describedByMetaEmissionBlock(declaring(one(suite, chainId, blockNumber)), suite, chainId);
        assertTrue(declared);
        assertEq(found, blockNumber);
    }

    function testTheSuiteOnAnotherChainDeclaresNoBlock(
        string memory suite,
        uint256 chainId,
        uint256 otherChainId,
        uint256 blockNumber
    ) external pure {
        vm.assume(otherChainId != chainId);
        (bool declared, uint256 found) =
            describedByMetaEmissionBlock(declaring(one(suite, chainId, blockNumber)), suite, otherChainId);
        assertFalse(declared);
        assertEq(found, 0);
    }

    function testAnotherSuiteOnTheChainDeclaresNoBlock(
        string memory suite,
        string memory otherSuite,
        uint256 chainId,
        uint256 blockNumber
    ) external pure {
        vm.assume(keccak256(bytes(otherSuite)) != keccak256(bytes(suite)));
        (bool declared, uint256 found) =
            describedByMetaEmissionBlock(declaring(one(suite, chainId, blockNumber)), otherSuite, chainId);
        assertFalse(declared);
        assertEq(found, 0);
    }

    function testASuiteWhoseNameExtendsTheDeclaredOneDeclaresNoBlock(uint256 chainId, uint256 blockNumber)
        external
        pure
    {
        (bool declared,) = describedByMetaEmissionBlock(
            declaring(one("described@0_0_1", chainId, blockNumber)), "described@0_0_10", chainId
        );
        assertFalse(declared);
    }

    function testTheMatchingEntryIsFoundPastOthers(
        string memory suite,
        string memory otherSuite,
        uint256 chainId,
        uint256 otherChainId,
        uint256 blockNumber,
        uint256 otherBlockNumber
    ) external pure {
        vm.assume(keccak256(bytes(otherSuite)) != keccak256(bytes(suite)));
        vm.assume(otherChainId != chainId);
        DescribedByMetaEmission[] memory emissions = new DescribedByMetaEmission[](3);
        emissions[0] = DescribedByMetaEmission({suite: suite, chainId: otherChainId, blockNumber: otherBlockNumber});
        emissions[1] = DescribedByMetaEmission({suite: otherSuite, chainId: chainId, blockNumber: otherBlockNumber});
        emissions[2] = DescribedByMetaEmission({suite: suite, chainId: chainId, blockNumber: blockNumber});
        (bool declared, uint256 found) = describedByMetaEmissionBlock(declaring(emissions), suite, chainId);
        assertTrue(declared);
        assertEq(found, blockNumber);
    }

    function testBlockZeroDeclaredIsDeclared(string memory suite, uint256 chainId) external pure {
        (bool declared, uint256 found) = describedByMetaEmissionBlock(declaring(one(suite, chainId, 0)), suite, chainId);
        assertTrue(declared);
        assertEq(found, 0);
    }
}
