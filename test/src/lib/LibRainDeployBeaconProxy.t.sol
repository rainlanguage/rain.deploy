// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {
    ICLONEABLE_FACTORY_V5_BEACON_PROXY_CREATION_CODE_HASH
} from "rain-factory-0.2.5/src/interface/deprecated/ICloneableFactoryV5.sol";
import {ICloneableFactoryV6} from "rain-factory-0.2.5/src/interface/ICloneableFactoryV6.sol";
import {BEACON_PROXY_CREATION_CODE} from "rain-factory-0.2.5/src/generated/BeaconProxy.sol";
import {DelegatedBeacon} from "rain-factory-0.2.5/src/lib/LibICloneableFactoryV5.sol";
import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {CloneTarget} from "../../../src/lib/LibRainDeployClone.sol";
import {BEACON_PROXY_ARTIFACT_PATH, LibRainDeployBeaconProxy} from "../../../src/lib/LibRainDeployBeaconProxy.sol";
import {EXAMPLE_BEACON_PROXY_RUNTIME_CODE, LibBeaconProxyTest} from "../../lib/LibBeaconProxyTest.sol";
import {MockBeaconProxyFactory} from "../../concrete/MockBeaconProxyFactory.sol";
import {MockCloneableV2} from "../../concrete/MockCloneableV2.sol";
import {MockDirtyOwnerCloneable} from "../../concrete/MockDirtyOwnerCloneable.sol";
import {MockLongOwnerCloneable} from "../../concrete/MockLongOwnerCloneable.sol";
import {MockMisansweringOwnerCloneable} from "../../concrete/MockMisansweringOwnerCloneable.sol";
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
    /// @return Where `CREATE` put it.
    function create(bytes memory code) internal returns (address) {
        address deployed;
        assembly ("memory-safe") {
            deployed := create(0, add(code, 0x20), mload(code))
        }
        assertNotEq(deployed, address(0), "create failed");
        return deployed;
    }

    /// The creation code is the generated creation code with `abi.encode(beacon, "")` appended.
    function testBeaconProxyCreationCode(address beacon) external pure {
        assertEq(
            LibRainDeployBeaconProxy.beaconProxyCreationCode(beacon),
            abi.encodePacked(BEACON_PROXY_CREATION_CODE, abi.encode(beacon, bytes("")))
        );
    }

    /// The generated runtime is the code a real factory leaves at the derived address, for a real beacon at any
    /// address, and generating it leaves no state behind.
    function testBeaconProxyRuntimeCodeIsWhatARealFactoryDeploys(address beaconAt, bytes32 salt, bytes memory data)
        external
    {
        assumeNotForgeAddress(beaconAt);
        vm.assume(uint160(beaconAt) > 0xffff && beaconAt.code.length == 0);
        MockCloneableV2 implementation = new MockCloneableV2();
        vm.assume(beaconAt != address(implementation));

        bytes memory generated = LibRainDeployBeaconProxy.beaconProxyRuntimeCode(
            vm, beaconAt, address(implementation), address(implementation).code
        );
        assertEq(beaconAt.code.length, 0, "beacon left behind");

        deployCodeTo(
            "UpgradeableBeacon.sol:UpgradeableBeacon", abi.encode(address(implementation), address(this)), beaconAt
        );
        MockBeaconProxyFactory factory = new MockBeaconProxyFactory();
        address proxy = factory.beaconProxyDeterministicOpenSalt(beaconAt, data, salt);
        assertEq(proxy.code, generated);
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

    /// The derived address is `CREATE2` from the factory over the V5 beacon-proxy open salt and the
    /// proxy's creation code with `abi.encode(beacon, "")`, built here from the domain string and
    /// held to the V5 creation code hash.
    function testBeaconProxyAddressIsTheV5Formula(CloneTarget memory target) external pure {
        assertEq(keccak256(BEACON_PROXY_CREATION_CODE), ICLONEABLE_FACTORY_V5_BEACON_PROXY_CREATION_CODE_HASH);
        bytes32 salt =
            keccak256(abi.encode(keccak256("rain.factory.beaconproxy.opensalt"), target.salt, keccak256(target.data)));
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(BEACON_PROXY_CREATION_CODE, abi.encode(target.implementation, bytes(""))));
        address expected =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), target.factory, salt, initCodeHash)))));
        assertEq(LibRainDeployBeaconProxy.beaconProxyDeployedAddress(target), expected);
    }

    /// The artifact path is a `<file>.sol:BeaconProxy` path that names nothing this build compiles.
    function testBeaconProxyArtifactPathResolvesToNothing() external view {
        string[] memory parts = vm.split(BEACON_PROXY_ARTIFACT_PATH, ".sol:");
        assertEq(parts.length, 2, "one .sol: separator");
        assertEq(parts[1], "BeaconProxy", "contract name");
        try vm.getCode(BEACON_PROXY_ARTIFACT_PATH) returns (bytes memory) {
            revert("artifact path resolved");
        } catch {}
    }

    /// The step deploys where the package derives, broadcast as the deployer.
    function testBeaconProxyDeployStepDeploysTheDerivedAddress() external {
        MockBeaconProxyFactory factory = new MockBeaconProxyFactory();
        CloneTarget memory target =
            CloneTarget({factory: address(factory), implementation: realBeacon(), data: TEST_DATA, salt: TEST_SALT});
        address deployed =
            this.externalBeaconProxyDeployStep(LibRainDeploy.ARBITRUM_ONE, address(0xD3910E8), abi.encode(target));
        assertEq(deployed, LibRainDeployBeaconProxy.beaconProxyDeployedAddress(target));
        address implementation = UpgradeableBeacon(target.implementation).implementation();
        assertEq(
            deployed.code,
            LibRainDeployBeaconProxy.beaconProxyRuntimeCode(
                vm, target.implementation, implementation, implementation.code
            )
        );
    }

    /// The step returns the address the factory's deploy call reports, not the address it derived.
    function testBeaconProxyDeployStepReturnsWhereTheFactoryDeployed() external {
        MockBeaconProxyFactory factory = new MockBeaconProxyFactory();
        CloneTarget memory target =
            CloneTarget({factory: address(factory), implementation: realBeacon(), data: TEST_DATA, salt: TEST_SALT});
        address elsewhere = address(uint160(LibRainDeployBeaconProxy.beaconProxyDeployedAddress(target)) + 1);
        vm.mockCall(
            address(factory),
            abi.encodeWithSelector(ICloneableFactoryV6(address(factory)).beaconProxyDeterministicOpenSalt.selector),
            abi.encode(elsewhere)
        );
        address deployed =
            this.externalBeaconProxyDeployStep(LibRainDeploy.ARBITRUM_ONE, address(0xD3910E8), abi.encode(target));
        assertEq(deployed, elsewhere);
    }

    /// The step stops the broadcast it starts, so the caller can start the next one.
    function testBeaconProxyDeployStepStopsItsBroadcast() external {
        MockBeaconProxyFactory factory = new MockBeaconProxyFactory();
        CloneTarget memory target =
            CloneTarget({factory: address(factory), implementation: realBeacon(), data: TEST_DATA, salt: TEST_SALT});
        this.externalBeaconProxyDeployStep(LibRainDeploy.ARBITRUM_ONE, address(0xD3910E8), abi.encode(target));
        vm.startBroadcast(address(0xD3910E8));
        vm.stopBroadcast();
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
            abi.encodeWithSelector(ICloneableFactoryV6(address(factory)).predictBeaconProxyAddressOpenSalt.selector),
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

    /// A proxy whose `owner()` reverts with the deploy key as its whole revert data, or returns fewer than 32 bytes,
    /// has not answered an owner, so it passes.
    function testBeaconProxyDeployStepAcceptsAnOwnerThatDoesNotAnswer(bool short) external {
        address deployer = address(0xD3910E8);
        MockBeaconProxyFactory factory = new MockBeaconProxyFactory();
        address beacon = address(new UpgradeableBeacon(address(new MockMisansweringOwnerCloneable()), address(this)));
        CloneTarget memory target =
            CloneTarget({factory: address(factory), implementation: beacon, data: abi.encode(short), salt: TEST_SALT});
        address deployed = this.externalBeaconProxyDeployStep(LibRainDeploy.ARBITRUM_ONE, deployer, abi.encode(target));
        assertEq(deployed, LibRainDeployBeaconProxy.beaconProxyDeployedAddress(target));
        (bool answered, bytes memory owner) = deployed.staticcall(abi.encodeWithSignature("owner()"));
        assertEq(answered, short);
        assertEq(owner.length, short ? 0x1f : 0x20);
        assertEq(owner, short ? owner : abi.encode(deployer));
    }

    /// A proxy whose `owner()` word holds the deploy key in its address bits is refused whatever bits sit above it.
    function testBeaconProxyDeployStepRefusesTheDeployKeyUnderDirtyHighBits(uint96 high) external {
        vm.assume(high != 0);
        address deployer = address(0xD3910E8);
        MockBeaconProxyFactory factory = new MockBeaconProxyFactory();
        address beacon = address(new UpgradeableBeacon(address(new MockDirtyOwnerCloneable()), address(this)));
        CloneTarget memory target =
            CloneTarget({factory: address(factory), implementation: beacon, data: abi.encode(high), salt: TEST_SALT});
        address expected = LibRainDeployBeaconProxy.beaconProxyDeployedAddress(target);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployBeaconProxy.BeaconProxySeatsDeployKey.selector, LibRainDeploy.ARBITRUM_ONE, expected
            )
        );
        this.externalBeaconProxyDeployStep(LibRainDeploy.ARBITRUM_ONE, deployer, abi.encode(target));
    }

    /// A proxy whose `owner()` answers more than a word, the deploy key in its first, is refused.
    function testBeaconProxyDeployStepRefusesTheDeployKeyInALongerAnswer(bytes32 trailing) external {
        address deployer = address(0xD3910E8);
        MockBeaconProxyFactory factory = new MockBeaconProxyFactory();
        address beacon = address(new UpgradeableBeacon(address(new MockLongOwnerCloneable()), address(this)));
        CloneTarget memory target = CloneTarget({
            factory: address(factory), implementation: beacon, data: abi.encode(trailing), salt: TEST_SALT
        });
        address expected = LibRainDeployBeaconProxy.beaconProxyDeployedAddress(target);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibRainDeployBeaconProxy.BeaconProxySeatsDeployKey.selector, LibRainDeploy.ARBITRUM_ONE, expected
            )
        );
        this.externalBeaconProxyDeployStep(LibRainDeploy.ARBITRUM_ONE, deployer, abi.encode(target));
    }

    /// The step refuses an EIP-7702 delegated beacon with the factory's `DelegatedBeacon`, deploying nothing.
    function testBeaconProxyDeployStepRefusesADelegatedBeacon(address delegate) external {
        MockBeaconProxyFactory factory = new MockBeaconProxyFactory();
        address beacon = address(0xBEAC0);
        vm.etch(beacon, abi.encodePacked(hex"ef0100", delegate));
        CloneTarget memory target =
            CloneTarget({factory: address(factory), implementation: beacon, data: TEST_DATA, salt: TEST_SALT});
        address expected = LibRainDeployBeaconProxy.beaconProxyDeployedAddress(target);
        vm.expectRevert(abi.encodeWithSelector(DelegatedBeacon.selector));
        this.externalBeaconProxyDeployStep(LibRainDeploy.ARBITRUM_ONE, address(0xD3910E8), abi.encode(target));
        assertEq(expected.code.length, 0);
    }

    /// The example fixture's runtime code is what the generator produces for its beacon.
    function testExampleBeaconProxyRuntimeCodeIsGenerated() external {
        MockCloneableV2 implementation = new MockCloneableV2();
        assertEq(
            EXAMPLE_BEACON_PROXY_RUNTIME_CODE,
            LibRainDeployBeaconProxy.beaconProxyRuntimeCode(
                vm, LibBeaconProxyTest.exampleBeacon(), address(implementation), address(implementation).code
            )
        );
    }
}
