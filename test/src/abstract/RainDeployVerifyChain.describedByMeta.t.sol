// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Vm, VmSafe} from "forge-std-1.17.0/src/Vm.sol";
import {
    DeployCandidate,
    DeployDeclaration,
    DeployDependency,
    DeploySuite,
    DescribedByMetaEmission
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {
    DescribedByMetaEmissionUndeclared,
    DescribedByMetaNotEmittedAt,
    MetaBoardUndeclared
} from "../../../src/lib/LibRainDeployDescribedByMeta.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../../src/lib/LibRainDeployZoltuMechanism.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";
import {LocalLogsForkVm} from "../../concrete/LocalLogsForkVm.sol";
import {MockDescribedByMeta} from "../../concrete/MockDescribedByMeta.sol";
import {LibMetaV1_2Log} from "../../lib/LibMetaV1_2Log.sol";

/// @title RainDeployVerifyChainDescribedByMetaTest
/// @notice The chain group refuses a suite carrying a described-by meta without a declared metaboard before forking,
/// and on each network the suite is required on checks the emission at the block declared for that network's chain.
contract RainDeployVerifyChainDescribedByMetaTest is RainDeployVerifyChain {
    uint256 constant ARBITRUM_CHAIN_ID = 42161;
    uint256 constant POLYGON_CHAIN_ID = 137;

    LocalLogsForkVm internal sForkVm;
    address internal sMetaBoard;
    DescribedByMetaEmission[] internal sEmissions;

    function setUp() external {
        sForkVm = new LocalLogsForkVm();
        sMetaBoard = makeAddr("metaboard");
        vm.etch(sMetaBoard, hex"00");
        vm.etch(described(), type(MockDescribedByMeta).runtimeCode);
    }

    function declaration() internal view override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        LibRainDeployDeclaration.setNetworks(d, bothNetworks());
        LibRainDeployDeclaration.addCandidates(d, candidates());
        d.metaBoard = sMetaBoard;
        d.describedByMetaEmissions = sEmissions;
        return d;
    }

    function bothNetworks() internal pure returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        return networks;
    }

    function meta() internal pure returns (bytes memory) {
        return "described-by meta";
    }

    function creationCode() internal pure returns (bytes memory) {
        return abi.encodePacked(type(MockDescribedByMeta).creationCode, abi.encode(keccak256(meta())));
    }

    function described() internal pure returns (address) {
        return LibRainDeploy.zoltuAddress(creationCode());
    }

    function describedSuite() internal pure returns (DeploySuite memory) {
        return DeploySuite({
            networks: bothNetworks(),
            suite: "described@0_0_1",
            creationCode: creationCode(),
            storedDeployedAddress: described(),
            storedBytecodeHash: keccak256(type(MockDescribedByMeta).runtimeCode),
            storedRuntimeCode: type(MockDescribedByMeta).runtimeCode,
            artifactPath: "test/concrete/MockDescribedByMeta.sol:MockDescribedByMeta",
            dependencies: new DeployDependency[](0),
            mechanismData: LibRainDeployZoltuMechanism.mechanismData(),
            describedByMeta: meta()
        });
    }

    function candidates() internal pure returns (DeployCandidate[] memory) {
        DeploySuite memory candidate = describedSuite();
        candidate.suite = "described";
        DeployCandidate[] memory declared = new DeployCandidate[](1);
        declared[0] = DeployCandidate({snapshot: candidate, unanchorableReason: ""});
        return declared;
    }

    function declare(uint256 chainId, uint256 blockNumber) internal {
        sEmissions.push(DescribedByMetaEmission({suite: "described@0_0_1", chainId: chainId, blockNumber: blockNumber}));
    }

    function emitAt(uint256 chainId, uint256 blockNumber) internal {
        LibMetaV1_2Log.setInBlock(
            sForkVm,
            chainId,
            blockNumber,
            sMetaBoard,
            LibMetaV1_2Log.one(sMetaBoard, address(this), described(), meta())
        );
    }

    function checkSuite(DeploySuite memory suite) external {
        DeploySuite[] memory suites = new DeploySuite[](1);
        suites[0] = suite;
        DeployDeclaration memory d = declaration();
        checkDeployedOnNetworks(d, Vm(address(sForkVm)), LibRainDeploy.declaredNetworkConfigs(d.networks), suites);
    }

    function testAnUndeclaredMetaBoardIsRefusedBeforeForking() external {
        sMetaBoard = address(0);
        vm.expectCall(address(sForkVm), abi.encodeWithSelector(LocalForkVm.createFork.selector), 0);
        vm.expectRevert(abi.encodeWithSelector(MetaBoardUndeclared.selector, "described@0_0_1"));
        this.checkSuite(describedSuite());
    }

    function testNoDeclaredEmissionBlockIsRefusedOnTheFirstNetwork() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                DescribedByMetaEmissionUndeclared.selector,
                LibRainDeploy.ARBITRUM_ONE,
                "described@0_0_1",
                ARBITRUM_CHAIN_ID
            )
        );
        this.checkSuite(describedSuite());
    }

    function testABlockDeclaredOnTheFirstChainAloneIsRefusedOnTheSecond(uint256 blockNumber) external {
        declare(ARBITRUM_CHAIN_ID, blockNumber);
        emitAt(ARBITRUM_CHAIN_ID, blockNumber);
        vm.expectRevert(
            abi.encodeWithSelector(
                DescribedByMetaEmissionUndeclared.selector, LibRainDeploy.POLYGON, "described@0_0_1", POLYGON_CHAIN_ID
            )
        );
        this.checkSuite(describedSuite());
    }

    function testTheEmissionAtEachChainsDeclaredBlockPasses(uint256 arbitrumBlock, uint256 polygonBlock) external {
        vm.assume(arbitrumBlock != polygonBlock);
        declare(ARBITRUM_CHAIN_ID, arbitrumBlock);
        declare(POLYGON_CHAIN_ID, polygonBlock);
        emitAt(ARBITRUM_CHAIN_ID, arbitrumBlock);
        emitAt(POLYGON_CHAIN_ID, polygonBlock);
        vm.expectCall(
            address(sForkVm),
            abi.encodeCall(VmSafe.eth_getLogs, (arbitrumBlock, arbitrumBlock, sMetaBoard, LibMetaV1_2Log.topics())),
            1
        );
        vm.expectCall(
            address(sForkVm),
            abi.encodeCall(VmSafe.eth_getLogs, (polygonBlock, polygonBlock, sMetaBoard, LibMetaV1_2Log.topics())),
            1
        );
        this.checkSuite(describedSuite());
    }

    function testADeclaredBlockWithoutTheEmissionIsRefusedNamingItsChain(uint256 arbitrumBlock, uint256 polygonBlock)
        external
    {
        declare(ARBITRUM_CHAIN_ID, arbitrumBlock);
        declare(POLYGON_CHAIN_ID, polygonBlock);
        emitAt(ARBITRUM_CHAIN_ID, arbitrumBlock);
        vm.expectRevert(
            abi.encodeWithSelector(
                DescribedByMetaNotEmittedAt.selector, "described@0_0_1", POLYGON_CHAIN_ID, polygonBlock
            )
        );
        this.checkSuite(describedSuite());
    }

    function testANetworkTheSuiteIsNotRequiredOnNeedsNoDeclaredBlock(uint256 blockNumber) external {
        declare(ARBITRUM_CHAIN_ID, blockNumber);
        emitAt(ARBITRUM_CHAIN_ID, blockNumber);
        DeploySuite memory suite = describedSuite();
        suite.networks = new string[](1);
        suite.networks[0] = LibRainDeploy.ARBITRUM_ONE;
        this.checkSuite(suite);
    }
}
