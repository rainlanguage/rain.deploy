// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {
    DeployCandidate,
    DeployDependency,
    DeployMechanism,
    DeploySuite
} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {RainDeployVerifyChain} from "../../../src/abstract/RainDeployVerifyChain.sol";
import {DeployBeacon} from "../../../src/lib/LibRainDeployBeacon.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {MockDeployableV2} from "../../concrete/MockDeployableV2.sol";

contract RainDeployVerifyChainBeaconTest is RainDeployVerifyChain {
    address constant OWNER = address(0xB0B);

    mapping(uint256 => DeployBeacon[]) internal sBeacons;
    address internal sBeacon;
    address internal sImplementation;

    function releasedSuites() internal pure override returns (DeploySuite[] memory) {
        return new DeploySuite[](0);
    }

    function candidateSuites() internal pure override returns (DeployCandidate[] memory) {
        DeployCandidate[] memory candidates = new DeployCandidate[](1);
        candidates[0] = DeployCandidate({
            snapshot: DeploySuite({
                suite: "beacon-chain-candidate",
                creationCode: type(MockDeployableV2).creationCode,
                storedDeployedAddress: LibRainDeploy.zoltuAddress(type(MockDeployableV2).creationCode),
                storedBytecodeHash: keccak256(type(MockDeployableV2).runtimeCode),
                storedRuntimeCode: type(MockDeployableV2).runtimeCode,
                artifactPath: "test/concrete/MockDeployableV2.sol:MockDeployableV2",
                dependencies: new DeployDependency[](0),
                mechanism: DeployMechanism.Zoltu,
                mechanismData: ""
            }),
            unanchorableReason: ""
        });
        return candidates;
    }

    function beacons(uint256 chainId) internal view override returns (DeployBeacon[] memory) {
        return sBeacons[chainId];
    }

    function setUp() external {
        sImplementation = address(new MockDeployableV2());
        sBeacon = address(new UpgradeableBeacon(sImplementation, OWNER));
        vm.makePersistent(sImplementation, sBeacon);
    }

    function declared(address owner) internal view returns (DeployBeacon memory) {
        return DeployBeacon({
            beacon: sBeacon,
            beaconCodeHash: sBeacon.codehash,
            implementation: sImplementation,
            implementationCodeHash: sImplementation.codehash,
            owner: owner
        });
    }

    function networksNamed(string memory first, string memory second)
        internal
        pure
        returns (SupportedNetwork[] memory)
    {
        string[] memory names = new string[](bytes(second).length == 0 ? 1 : 2);
        names[0] = first;
        if (names.length == 2) {
            names[1] = second;
        }
        return LibRainDeploy.declaredNetworkConfigs(names);
    }

    function externalCheckDeployedOnNetworks(SupportedNetwork[] memory networks) external {
        checkDeployedOnNetworks(networks, releasedSuites());
    }

    function testChainGroupPassesABeaconAtItsDeclaredState() external {
        sBeacons[42161].push(declared(OWNER));
        this.externalCheckDeployedOnNetworks(networksNamed(LibRainDeploy.ARBITRUM_ONE, ""));
    }

    function testChainGroupChecksBeaconsWithoutSuites() external {
        sBeacons[42161].push(declared(address(0xCAFE)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeploy.UnexpectedResolvedAddress.selector,
                LibRainDeploy.ARBITRUM_ONE,
                sBeacon,
                1,
                address(0xCAFE),
                OWNER
            )
        );
        this.externalCheckDeployedOnNetworks(networksNamed(LibRainDeploy.ARBITRUM_ONE, ""));
    }

    function testChainGroupChecksEachNetworksOwnBeacons() external {
        sBeacons[42161].push(declared(OWNER));
        DeployBeacon memory missing = declared(OWNER);
        missing.beacon = address(0xBEAC0);
        sBeacons[8453].push(missing);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.NotDeployedOnNetwork.selector, LibRainDeploy.BASE, address(0xBEAC0))
        );
        this.externalCheckDeployedOnNetworks(networksNamed(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE));
    }
}
