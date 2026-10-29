// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {DescribedByMetaNotEmittedAt, MetaBoardUndeclared} from "../../../src/lib/LibRainDeployDescribedByMeta.sol";
import {DescribedByMetaDeploy} from "../../concrete/DescribedByMetaDeploy.sol";
import {RecordedMetaEmission, RecordingMetaBoard} from "../../concrete/RecordingMetaBoard.sol";
import {MockCreate2Factory} from "../../concrete/MockCreate2Factory.sol";
import {MOCK_CREATE2_FACTORY} from "../../lib/LibMockCreate2Mechanism.sol";

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

    /// The suite is read before `expectRevert`, which the read would otherwise consume.
    function expectMetaBroadcastRefused(string[] memory networks, bytes memory refusal) internal {
        DeploySuite memory suite = sDeploy.describedSuite(SUITE, META);
        vm.expectRevert(refusal);
        broadcast(suite, networks);
    }

    function testASuiteCarryingAMetaWithNoMetaBoardIsRefusedBeforeAnyFork() external {
        sDeploy.setMetaBoard(address(0));
        expectMetaBroadcastRefused(
            sDeploy.arbitrumAndPolygon(), abi.encodeWithSelector(MetaBoardUndeclared.selector, SUITE)
        );
        assertFalse(anyForkExists());
    }

    function testTheFirstNetworkIsCheckedAtItsOwnChainsDeclaredBlock() external {
        declareBothBlocks();
        expectMetaBroadcastRefused(
            sDeploy.arbitrumAndPolygon(),
            abi.encodeWithSelector(DescribedByMetaNotEmittedAt.selector, SUITE, ARBITRUM_CHAIN_ID, ARBITRUM_BLOCK)
        );
    }

    function testTheFirstNetworkReversedIsCheckedAtItsOwnChainsDeclaredBlock() external {
        declareBothBlocks();
        expectMetaBroadcastRefused(
            polygonAndArbitrum(),
            abi.encodeWithSelector(DescribedByMetaNotEmittedAt.selector, SUITE, POLYGON_CHAIN_ID, POLYGON_BLOCK)
        );
    }

    function testTheSecondNetworkIsCheckedAtItsOwnChainsDeclaredBlockAfterTheFirstEmits() external {
        sDeploy.declareEmission(SUITE, POLYGON_CHAIN_ID, POLYGON_BLOCK);
        expectMetaBroadcastRefused(
            sDeploy.arbitrumAndPolygon(),
            abi.encodeWithSelector(DescribedByMetaNotEmittedAt.selector, SUITE, POLYGON_CHAIN_ID, POLYGON_BLOCK)
        );
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

    function testEachNetworkEmitsAboutItsOwnDeployment() external {
        vm.etch(MOCK_CREATE2_FACTORY, type(MockCreate2Factory).runtimeCode);
        vm.makePersistent(MOCK_CREATE2_FACTORY);
        address[] memory deployed = broadcast(
            sDeploy.perNetworkDescribedSuite("described-per-network@0_0_1", META), sDeploy.arbitrumAndPolygon()
        );
        assertNotEq(deployed[0], deployed[1]);
        RecordedMetaEmission[] memory emissions = sMetaBoard.emissions();
        assertEq(emissions.length, 2);
        assertEq(emissions[0].chainId, ARBITRUM_CHAIN_ID);
        assertEq(emissions[0].subject, bytes32(uint256(uint160(deployed[0]))));
        assertEq(emissions[1].chainId, POLYGON_CHAIN_ID);
        assertEq(emissions[1].subject, bytes32(uint256(uint160(deployed[1]))));
    }

    function testASuiteWithoutAMetaEmitsNothing() external {
        declareBothBlocks();
        broadcast(sDeploy.describedSuite(SUITE, ""), sDeploy.arbitrumAndPolygon());
        assertEq(sMetaBoard.emissions().length, 0);
    }
}
