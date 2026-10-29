// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {DescribedByMetaNotEmittedAt, MetaBoardUndeclared} from "../../../src/lib/LibRainDeployDescribedByMeta.sol";
import {DescribedByMetaDeploy} from "../../concrete/DescribedByMetaDeploy.sol";
import {RecordedMetaEmission, RecordingMetaBoard} from "../../concrete/RecordingMetaBoard.sol";

contract RainDeployBroadcastDescribedByMetaTest is Test {
    uint256 constant ARBITRUM_CHAIN_ID = 42161;
    uint256 constant POLYGON_CHAIN_ID = 137;
    uint256 constant ARBITRUM_BLOCK = 504083840;
    uint256 constant POLYGON_BLOCK = 70000000;
    uint256 constant DEPLOYER_KEY = 0xa11ce;
    string constant SUITE = "described@0_0_1";
    bytes constant META = "described-by meta";

    DescribedByMetaDeploy internal sDeploy;
    RecordingMetaBoard internal sMetaBoard;

    function setUp() external {
        sDeploy = new DescribedByMetaDeploy();
        sMetaBoard = new RecordingMetaBoard();
        vm.makePersistent(address(sMetaBoard));
        sDeploy.setMetaBoard(address(sMetaBoard));
    }

    function anyForkExists() internal returns (bool) {
        (bool forked,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(0)));
        return forked;
    }

    function polygonAndArbitrum() internal pure returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.POLYGON;
        networks[1] = LibRainDeploy.ARBITRUM_ONE;
        return networks;
    }

    function declareBothBlocks() internal {
        sDeploy.declareEmission(SUITE, POLYGON_CHAIN_ID, POLYGON_BLOCK);
        sDeploy.declareEmission(SUITE, ARBITRUM_CHAIN_ID, ARBITRUM_BLOCK);
    }

    function broadcast(DeploySuite memory suite, string[] memory networks) internal returns (address[] memory) {
        (address[] memory deployed,) = sDeploy.externalBroadcastSuite(suite, networks, DEPLOYER_KEY);
        return deployed;
    }

    function testASuiteCarryingAMetaWithNoMetaBoardIsRefusedBeforeAnyFork() external {
        sDeploy.setMetaBoard(address(0));
        vm.expectRevert(abi.encodeWithSelector(MetaBoardUndeclared.selector, SUITE));
        broadcast(sDeploy.describedSuite(SUITE, META), sDeploy.arbitrumAndPolygon());
        assertFalse(anyForkExists());
    }

    function testTheFirstNetworkIsCheckedAtItsOwnChainsDeclaredBlock() external {
        declareBothBlocks();
        vm.expectRevert(
            abi.encodeWithSelector(DescribedByMetaNotEmittedAt.selector, SUITE, ARBITRUM_CHAIN_ID, ARBITRUM_BLOCK)
        );
        broadcast(sDeploy.describedSuite(SUITE, META), sDeploy.arbitrumAndPolygon());
    }

    function testTheFirstNetworkReversedIsCheckedAtItsOwnChainsDeclaredBlock() external {
        declareBothBlocks();
        vm.expectRevert(
            abi.encodeWithSelector(DescribedByMetaNotEmittedAt.selector, SUITE, POLYGON_CHAIN_ID, POLYGON_BLOCK)
        );
        broadcast(sDeploy.describedSuite(SUITE, META), polygonAndArbitrum());
    }

    function testTheSecondNetworkIsCheckedAtItsOwnChainsDeclaredBlockAfterTheFirstEmits() external {
        sDeploy.declareEmission(SUITE, POLYGON_CHAIN_ID, POLYGON_BLOCK);
        vm.expectRevert(
            abi.encodeWithSelector(DescribedByMetaNotEmittedAt.selector, SUITE, POLYGON_CHAIN_ID, POLYGON_BLOCK)
        );
        broadcast(sDeploy.describedSuite(SUITE, META), sDeploy.arbitrumAndPolygon());
    }

    function testEachUndeclaredNetworkEmitsOnItsOwnChainAsTheDeployer() external {
        address[] memory deployed = broadcast(sDeploy.describedSuite(SUITE, META), sDeploy.arbitrumAndPolygon());
        RecordedMetaEmission[] memory emissions = sMetaBoard.emissions();
        assertEq(emissions.length, 2);
        assertEq(emissions[0].chainId, ARBITRUM_CHAIN_ID);
        assertEq(emissions[1].chainId, POLYGON_CHAIN_ID);
        for (uint256 i = 0; i < emissions.length; i++) {
            assertEq(emissions[i].sender, vm.addr(DEPLOYER_KEY));
            assertEq(emissions[i].subject, bytes32(uint256(uint160(deployed[i]))));
            assertEq(emissions[i].meta, META);
        }
    }

    function testASuiteWithoutAMetaEmitsNothing() external {
        declareBothBlocks();
        broadcast(sDeploy.describedSuite(SUITE, ""), sDeploy.arbitrumAndPolygon());
        assertEq(sMetaBoard.emissions().length, 0);
    }
}
