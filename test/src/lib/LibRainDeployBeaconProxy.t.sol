// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {ICloneableFactoryV5} from "rain-factory-pr271-4379965/src/interface/ICloneableFactoryV5.sol";
import {BEACON_PROXY_CREATION_CODE} from "rain-factory-pr271-4379965/src/generated/BeaconProxy.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {CloneTarget} from "../../../src/lib/LibRainDeployClone.sol";
import {
    BEACON_PROXY_ARTIFACT_PATH,
    BEACON_PROXY_BEACON_IMMUTABLE_OFFSET,
    BEACON_PROXY_RUNTIME_OFFSET,
    BEACON_PROXY_STAND_IN_IMPLEMENTATION,
    BeaconProxyStandInBeacon,
    BeaconProxyStandInImplementation,
    LibRainDeployBeaconProxy
} from "../../../src/lib/LibRainDeployBeaconProxy.sol";
import {MockBeaconProxyFactory} from "../../concrete/MockBeaconProxyFactory.sol";
import {MockCloneableV2} from "../../concrete/MockCloneableV2.sol";
import {MockOriginOwnedCloneable} from "../../concrete/MockOriginOwnedCloneable.sol";

/// @title LibRainDeployBeaconProxyTest Tests for `LibRainDeployBeaconProxy`'s derivations and its
/// deploy step, each against a real `BeaconProxy` deploy.
contract LibRainDeployBeaconProxyTest is Test {
    bytes32 constant TEST_SALT = 0x1122334455667788990011223344556677889900112233445566778899001122;

    bytes constant TEST_DATA = hex"deadbeefcafe0102030405060708090a0b0c0d0e0f";

    /// @param network The network name a refusal should carry.
    /// @param deployer The address to broadcast as.
    /// @param targetData The `abi.encode`d `CloneTarget`.
    /// @return The address the step deployed to.
    function externalBeaconProxyDeployStep(string memory network, address deployer, bytes memory targetData)
        external
        returns (address)
    {
        return LibRainDeployBeaconProxy.beaconProxyDeployStep(vm, network, deployer, targetData);
    }

    /// A beacon serving a fresh `MockCloneableV2`, owned by this test.
    /// @return The beacon.
    function realBeacon() internal returns (address) {
        return address(new UpgradeableBeacon(address(new MockCloneableV2()), address(this)));
    }

    /// @param code Creation code.
    /// @return deployed Where `CREATE` put it.
    function create(bytes memory code) internal returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create(0, add(code, 0x20), mload(code))
        }
        assertNotEq(deployed, address(0), "create failed");
    }

    /// The offsets are pinned to the generated creation code: the constructor copies the runtime from
    /// `BEACON_PROXY_RUNTIME_OFFSET` and stores the beacon at `BEACON_PROXY_BEACON_IMMUTABLE_OFFSET`,
    /// the operand of the runtime's one `PUSH32` of zero.
    function testBeaconProxyOffsetsArePinned() external pure {
        assertEq(BEACON_PROXY_RUNTIME_OFFSET, 0x424);
        assertEq(BEACON_PROXY_BEACON_IMMUTABLE_OFFSET, 0x23);
        bytes memory creation = BEACON_PROXY_CREATION_CODE;
        assertEq(creation.length - BEACON_PROXY_RUNTIME_OFFSET, 0x10b, "runtime length");
        // `PUSH2 0x10b PUSH2 0x424 PUSH0 CODECOPY`, then `PUSH0 PUSH1 0x23 ADD MSTORE`.
        bytes memory constructorTail = hex"61010b6104245f395f60230152";
        uint256 found = 0;
        for (uint256 i = 0; i + constructorTail.length <= BEACON_PROXY_RUNTIME_OFFSET; i++) {
            bool matches = true;
            for (uint256 j = 0; j < constructorTail.length && matches; j++) {
                matches = creation[i + j] == constructorTail[j];
            }
            if (matches) {
                found++;
            }
        }
        assertEq(found, 1, "the constructor's copy and immutable store");
        uint256 push32 = 0;
        for (uint256 i = BEACON_PROXY_RUNTIME_OFFSET; i < creation.length; i++) {
            if (creation[i] == 0x7f) {
                push32++;
            }
        }
        assertEq(push32, 1, "one PUSH32 in the runtime");
        assertEq(uint8(creation[BEACON_PROXY_RUNTIME_OFFSET + BEACON_PROXY_BEACON_IMMUTABLE_OFFSET - 1]), 0x7f);
        for (uint256 i = 0; i < 0x20; i++) {
            assertEq(uint8(creation[BEACON_PROXY_RUNTIME_OFFSET + BEACON_PROXY_BEACON_IMMUTABLE_OFFSET + i]), 0);
        }
    }

    /// The creation code is the generated creation code with `abi.encode(beacon, "")` appended.
    function testBeaconProxyCreationCode(address beacon) external pure {
        assertEq(
            LibRainDeployBeaconProxy.beaconProxyCreationCode(beacon),
            abi.encodePacked(BEACON_PROXY_CREATION_CODE, abi.encode(beacon, bytes("")))
        );
    }

    /// The runtime matches what a real `BeaconProxy` deploy leaves, for any beacon address.
    function testBeaconProxyRuntimeMatchesARealDeploy(address beacon) external {
        vm.assume(uint160(beacon) > 0xffff && beacon.code.length == 0);
        vm.assume(beacon != BEACON_PROXY_STAND_IN_IMPLEMENTATION);
        vm.etch(beacon, type(BeaconProxyStandInBeacon).runtimeCode);
        vm.etch(BEACON_PROXY_STAND_IN_IMPLEMENTATION, type(BeaconProxyStandInImplementation).runtimeCode);

        address proxy = create(LibRainDeployBeaconProxy.beaconProxyCreationCode(beacon));
        assertEq(proxy.code, LibRainDeployBeaconProxy.beaconProxyRuntimeCode(beacon));
        assertEq(proxy.codehash, LibRainDeployBeaconProxy.beaconProxyDeployedCodehash(beacon));
    }

    /// The runtime of a real beacon's proxy matches too, and the proxy delegates into its implementation.
    function testBeaconProxyRuntimeMatchesARealBeacon() external {
        address beacon = realBeacon();
        address proxy = create(LibRainDeployBeaconProxy.beaconProxyCreationCode(beacon));
        assertEq(proxy.code, LibRainDeployBeaconProxy.beaconProxyRuntimeCode(beacon));
        assertEq(MockCloneableV2(proxy).version(), 2);
    }

    /// The derived address is where a real factory deploys the proxy, and what it predicts.
    function testBeaconProxyAddressMatchesARealFactory(bytes32 salt, bytes memory data) external {
        MockBeaconProxyFactory factory = new MockBeaconProxyFactory();
        address beacon = realBeacon();
        CloneTarget memory target =
            CloneTarget({factory: address(factory), implementation: beacon, data: data, salt: salt});
        address expected = LibRainDeployBeaconProxy.beaconProxyDeployedAddress(target);
        assertEq(factory.predictBeaconProxyAddressOpenSalt(beacon, data, salt), expected);
        assertEq(factory.beaconProxyDeterministicOpenSalt(beacon, data, salt), expected);
        assertEq(expected.code, LibRainDeployBeaconProxy.beaconProxyRuntimeCode(beacon));
    }

    /// The address moves with each of factory, beacon, salt and data.
    function testBeaconProxyAddressMovesWithEveryInput(CloneTarget memory target, uint160 delta, bytes32 otherSalt)
        external
        pure
    {
        vm.assume(delta != 0 && otherSalt != target.salt);
        address base = LibRainDeployBeaconProxy.beaconProxyDeployedAddress(target);
        CloneTarget memory moved = CloneTarget(target.factory, target.implementation, target.data, target.salt);
        unchecked {
            moved.factory = address(uint160(target.factory) + delta);
        }
        assertNotEq(LibRainDeployBeaconProxy.beaconProxyDeployedAddress(moved), base, "factory");
        moved = CloneTarget(target.factory, target.implementation, target.data, target.salt);
        unchecked {
            moved.implementation = address(uint160(target.implementation) + delta);
        }
        assertNotEq(LibRainDeployBeaconProxy.beaconProxyDeployedAddress(moved), base, "beacon");
        moved = CloneTarget(target.factory, target.implementation, target.data, otherSalt);
        assertNotEq(LibRainDeployBeaconProxy.beaconProxyDeployedAddress(moved), base, "salt");
        moved = CloneTarget(target.factory, target.implementation, abi.encodePacked(target.data, hex"00"), target.salt);
        assertNotEq(LibRainDeployBeaconProxy.beaconProxyDeployedAddress(moved), base, "data");
    }

    /// The artifact path names nothing this build compiles.
    function testBeaconProxyArtifactPathResolvesToNothing() external {
        vm.expectRevert();
        this.externalGetCode(BEACON_PROXY_ARTIFACT_PATH);
    }

    /// @param path An artifact path.
    /// @return Its creation code.
    function externalGetCode(string memory path) external view returns (bytes memory) {
        return vm.getCode(path);
    }

    /// The stand-in implementation initializes to the `ICloneableV2` success value with any data.
    function testStandInImplementationInitializes(bytes memory data) external {
        BeaconProxyStandInImplementation standIn = new BeaconProxyStandInImplementation();
        assertEq(standIn.initialize(data), keccak256("ICloneableV2.initialize"));
    }

    /// The stand-in beacon serves the stand-in implementation.
    function testStandInBeaconServesTheStandInImplementation() external {
        assertEq(new BeaconProxyStandInBeacon().implementation(), BEACON_PROXY_STAND_IN_IMPLEMENTATION);
    }

    /// The step deploys where the package derives, broadcast as the deployer.
    function testBeaconProxyDeployStepDeploysTheDerivedAddress() external {
        MockBeaconProxyFactory factory = new MockBeaconProxyFactory();
        CloneTarget memory target =
            CloneTarget({factory: address(factory), implementation: realBeacon(), data: TEST_DATA, salt: TEST_SALT});
        address deployed =
            this.externalBeaconProxyDeployStep(LibRainDeploy.ARBITRUM_ONE, address(0xD3910E8), abi.encode(target));
        assertEq(deployed, LibRainDeployBeaconProxy.beaconProxyDeployedAddress(target));
        assertEq(deployed.codehash, LibRainDeployBeaconProxy.beaconProxyDeployedCodehash(target.implementation));
    }

    /// The step refuses a factory that predicts another address, before deploying.
    function testBeaconProxyDeployStepPredictionMismatchReverts() external {
        MockBeaconProxyFactory factory = new MockBeaconProxyFactory();
        CloneTarget memory target =
            CloneTarget({factory: address(factory), implementation: realBeacon(), data: TEST_DATA, salt: TEST_SALT});
        address expected = LibRainDeployBeaconProxy.beaconProxyDeployedAddress(target);
        address predicted = address(uint160(expected) + 1);
        vm.mockCall(
            address(factory),
            abi.encodeWithSelector(ICloneableFactoryV5.predictBeaconProxyAddressOpenSalt.selector),
            abi.encode(predicted)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployBeaconProxy.BeaconProxyFactoryPredictionMismatch.selector,
                LibRainDeploy.ARBITRUM_ONE,
                address(factory),
                expected,
                predicted
            )
        );
        this.externalBeaconProxyDeployStep(LibRainDeploy.ARBITRUM_ONE, address(this), abi.encode(target));
        assertEq(expected.code.length, 0);
    }

    /// The step refuses a proxy whose `owner()` is the deploy key.
    function testBeaconProxyDeployStepRefusesTheDeployKeySeated() external {
        MockBeaconProxyFactory factory = new MockBeaconProxyFactory();
        address beacon = address(new UpgradeableBeacon(address(new MockOriginOwnedCloneable()), address(this)));
        address deployer = address(0xD3910E8);
        CloneTarget memory target = CloneTarget({
            factory: address(factory), implementation: beacon, data: abi.encode(address(0)), salt: TEST_SALT
        });
        address expected = LibRainDeployBeaconProxy.beaconProxyDeployedAddress(target);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployBeaconProxy.BeaconProxySeatsDeployKey.selector, LibRainDeploy.ARBITRUM_ONE, expected
            )
        );
        this.externalBeaconProxyDeployStep(LibRainDeploy.ARBITRUM_ONE, deployer, abi.encode(target));
    }

    /// A proxy owned by anyone but the deploy key passes.
    function testBeaconProxyDeployStepAcceptsAnotherOwner(address owner) external {
        address deployer = address(0xD3910E8);
        vm.assume(owner != deployer && owner != address(0));
        MockBeaconProxyFactory factory = new MockBeaconProxyFactory();
        address beacon = address(new UpgradeableBeacon(address(new MockOriginOwnedCloneable()), address(this)));
        CloneTarget memory target =
            CloneTarget({factory: address(factory), implementation: beacon, data: abi.encode(owner), salt: TEST_SALT});
        address deployed = this.externalBeaconProxyDeployStep(LibRainDeploy.ARBITRUM_ONE, deployer, abi.encode(target));
        assertEq(MockOriginOwnedCloneable(deployed).owner(), owner);
    }
}
