// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    DeployCandidate,
    DeployDeclaration,
    DeployDependency,
    DeploySuite,
    DescribedByMetaEmission
} from "../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibRainDeployDeclaration} from "../../src/lib/LibRainDeployDeclaration.sol";
import {LibRainDeployZoltuMechanism} from "../../src/lib/LibRainDeployZoltuMechanism.sol";
import {ExternalDeployBroadcast} from "../abstract/ExternalDeployBroadcast.sol";
import {MockDescribedByMeta} from "./MockDescribedByMeta.sol";

contract DescribedByMetaDeploy is ExternalDeployBroadcast {
    address internal sMetaBoard;
    DescribedByMetaEmission[] internal sEmissions;

    //forge-lint: disable-next-line(missing-zero-check)
    function setMetaBoard(address metaBoard) external {
        sMetaBoard = metaBoard;
    }

    function declareEmission(string memory suite, uint256 chainId, uint256 blockNumber) external {
        sEmissions.push(DescribedByMetaEmission({suite: suite, chainId: chainId, blockNumber: blockNumber}));
    }

    function arbitrumAndPolygon() public pure returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.ARBITRUM_ONE;
        networks[1] = LibRainDeploy.POLYGON;
        return networks;
    }

    function describedSuite(string memory suite, bytes memory meta) public pure returns (DeploySuite memory) {
        bytes memory creationCode =
            abi.encodePacked(type(MockDescribedByMeta).creationCode, abi.encode(keccak256(meta)));
        return DeploySuite({
            networks: arbitrumAndPolygon(),
            suite: suite,
            creationCode: creationCode,
            storedDeployedAddress: LibRainDeploy.zoltuAddress(creationCode),
            storedBytecodeHash: keccak256(type(MockDescribedByMeta).runtimeCode),
            storedRuntimeCode: type(MockDescribedByMeta).runtimeCode,
            artifactPath: "test/concrete/MockDescribedByMeta.sol:MockDescribedByMeta",
            dependencies: new DeployDependency[](0),
            mechanismData: LibRainDeployZoltuMechanism.mechanismData(),
            describedByMeta: meta
        });
    }

    function declaration() internal view override returns (DeployDeclaration memory) {
        DeployDeclaration memory d;
        LibRainDeployDeclaration.extend(d);
        LibRainDeployZoltuMechanism.extend(d);
        LibRainDeployDeclaration.setNetworks(d, arbitrumAndPolygon());
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({snapshot: describedSuite("described", ""), unanchorableReason: ""});
        LibRainDeployDeclaration.addCandidates(d, candidates);
        d.metaBoard = sMetaBoard;
        d.describedByMetaEmissions = sEmissions;
        return d;
    }
}
