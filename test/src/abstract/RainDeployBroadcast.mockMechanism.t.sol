// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {SuiteSeatsDeployKey} from "../../../src/abstract/RainDeployBroadcast.sol";
import {DeployDependency, DeploySuite} from "../../../src/abstract/RainDeploySuitesBase.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {ChainDeploy} from "../../../src/lib/LibRainDeployExtendedNetworks.sol";
import {
    MOCK_CREATE2_FACTORY,
    MOCK_CREATE2_SALT,
    MockCreate2Mechanism,
    MockCreate2NetworkUnfrozen
} from "../../abstract/MockCreate2DeploySuites.sol";
import {MockCreate2Deploy} from "../../concrete/MockCreate2Deploy.sol";
import {MockCreate2Factory} from "../../concrete/MockCreate2Factory.sol";
import {MockChainOriginOwned} from "../../concrete/MockChainOriginOwned.sol";
import {MockDeployable} from "../../concrete/MockDeployable.sol";
import {LocalForkVm} from "../../concrete/LocalForkVm.sol";

/// @title RainDeployBroadcastMockMechanismTest
/// @notice `deployAndBroadcast` and the seat check over a per-network mechanism, offline on `LocalForkVm`.
contract RainDeployBroadcastMockMechanismTest is Test {
    event MockCreate2Verification(string[] networks, string suite, address[] deployed);

    MockCreate2Deploy internal sDeploy;

    LocalForkVm internal sForkVm;

    function setUp() external {
        sDeploy = new MockCreate2Deploy();
        sForkVm = new LocalForkVm();
        vm.etch(MOCK_CREATE2_FACTORY, type(MockCreate2Factory).runtimeCode);
    }

    function networkAddress(uint256 chainId, bytes memory creationCode) internal pure returns (address) {
        bytes32 salt = keccak256(abi.encode(MOCK_CREATE2_SALT, abi.encode(chainId)));
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), MOCK_CREATE2_FACTORY, salt, keccak256(creationCode)))))
        );
    }

    function networkAddress(uint256 chainId) internal pure returns (address) {
        return networkAddress(chainId, type(MockDeployable).creationCode);
    }

    function names(string memory a, string memory b) internal pure returns (string[] memory) {
        string[] memory networks = new string[](2);
        networks[0] = a;
        networks[1] = b;
        return networks;
    }

    function anyForkExists() internal returns (bool) {
        (bool forked,) = address(vm).call(abi.encodeWithSignature("selectFork(uint256)", uint256(0)));
        return forked;
    }

    function testBroadcastsEachNetworkAtItsOwnAddress() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        address[] memory expected = new address[](2);
        expected[0] = networkAddress(42161);
        expected[1] = networkAddress(137);
        string[] memory networks = names(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON);
        vm.expectEmit(address(sDeploy));
        emit MockCreate2Verification(networks, release.suite, expected);
        (address[] memory deployed,) =
            sDeploy.externalDeployAndBroadcast(Vm(address(sForkVm)), networks, 1, release, release);
        assertEq(deployed.length, 2);
        assertEq(deployed[0], expected[0]);
        assertEq(deployed[1], expected[1]);
        assertEq(expected[0].code, type(MockDeployable).runtimeCode);
        assertEq(expected[1].code, type(MockDeployable).runtimeCode);
    }

    /// The mechanism's verification log replaces the Zoltu verify commands.
    function testBroadcastFormatsNoZoltuVerifyCommand() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        vm.expectCall(address(sForkVm), abi.encodeWithSignature("toString(address)", networkAddress(42161)), 0);
        sDeploy.externalDeployAndBroadcast(
            Vm(address(sForkVm)), names(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON), 1, release, release
        );
    }

    /// A network the candidate adds but the release neither records nor extends is refused before any fork, at the
    /// address the release's derivation gives it there.
    function testBroadcastRefusesAnUnfrozenCandidateNetworkBeforeAnyFork() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        DeploySuite memory candidate = sDeploy.externalMockCandidate();
        vm.expectRevert(
            abi.encodeWithSelector(
                MockCreate2NetworkUnfrozen.selector, release.suite, LibRainDeploy.BASE, networkAddress(8453)
            )
        );
        sDeploy.externalDeployAndBroadcast(
            vm, names(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.BASE), 1, release, candidate
        );
        assertFalse(anyForkExists());
    }

    /// An extended network broadcasts at its declared address.
    function testBroadcastsADeclaredExtendedNetwork() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        ChainDeploy[] memory extended = new ChainDeploy[](1);
        extended[0] =
            ChainDeploy({chainId: 8453, data: abi.encode(uint256(8453)), deployedAddress: networkAddress(8453)});
        DeploySuite memory frozen = sDeploy.externalAppendExtendedNetworks(release, extended);
        (address[] memory deployed,) = sDeploy.externalDeployAndBroadcast(
            Vm(address(sForkVm)),
            names(LibRainDeploy.BASE, LibRainDeploy.POLYGON),
            1,
            frozen,
            sDeploy.externalMockCandidate()
        );
        assertEq(deployed[0], networkAddress(8453));
        assertEq(deployed[1], networkAddress(137));
        assertEq(networkAddress(8453).code, type(MockDeployable).runtimeCode);
    }

    /// The recorded address on each network is held to the mechanism's derivation there before any fork.
    function testBroadcastRefusesAStaleRecordedAddressBeforeAnyFork() external {
        DeploySuite memory release = sDeploy.externalMockRelease();
        MockCreate2Mechanism memory mechanism = abi.decode(release.mechanismData, (MockCreate2Mechanism));
        mechanism.networks[1].deployedAddress = address(0x5a1e);
        release.mechanismData = abi.encode(mechanism);
        vm.expectRevert(
            abi.encodeWithSelector(LibRainDeploy.UnexpectedDeployedAddress.selector, address(0x5a1e), networkAddress(137))
        );
        sDeploy.externalDeployAndBroadcast(
            vm, names(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON), 1, release, release
        );
        assertFalse(anyForkExists());
    }

    function originOwnedOnSuite(uint256 ownedOn) internal view returns (DeploySuite memory) {
        bytes memory creationCode = abi.encodePacked(
            type(MockChainOriginOwned).creationCode, abi.encode(ownedOn)
        );
        ChainDeploy[] memory networks = new ChainDeploy[](2);
        networks[0] = ChainDeploy({
            chainId: 42161, data: abi.encode(uint256(42161)), deployedAddress: networkAddress(42161, creationCode)
        });
        networks[1] =
            ChainDeploy({chainId: 137, data: abi.encode(uint256(137)), deployedAddress: networkAddress(137, creationCode)});
        DeploySuite memory suite = sDeploy.externalMockRelease();
        suite.creationCode = creationCode;
        suite.dependencies = new DeployDependency[](0);
        suite.mechanismData = abi.encode(
            MockCreate2Mechanism({
                factory: MOCK_CREATE2_FACTORY, salt: MOCK_CREATE2_SALT, beacon: address(0), networks: networks
            })
        );
        return suite;
    }

    /// The seat check deploys each network's address under its own chain id: the one seating the deploy key there
    /// refuses the broadcast, by its own address.
    function testSeatCheckDeploysEachNetworkUnderItsOwnChainId() external {
        address deployer = vm.addr(1);
        DeploySuite memory suite = originOwnedOnSuite(137);
        vm.expectRevert(
            abi.encodeWithSelector(SuiteSeatsDeployKey.selector, suite.suite, networkAddress(137, suite.creationCode))
        );
        sDeploy.externalCheckSeatsNoDeployKey(suite, names(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON), deployer);
    }

    function testSeatCheckLeavesNothingDeployed() external {
        DeploySuite memory suite = originOwnedOnSuite(1);
        sDeploy.externalCheckSeatsNoDeployKey(
            suite, names(LibRainDeploy.ARBITRUM_ONE, LibRainDeploy.POLYGON), vm.addr(1)
        );
        assertEq(networkAddress(42161, suite.creationCode).code.length, 0);
        assertEq(networkAddress(137, suite.creationCode).code.length, 0);
    }
}
