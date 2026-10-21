// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Vm} from "forge-std-1.17.0/src/Vm.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IERC5313} from "@openzeppelin-contracts-5.7.0/interfaces/IERC5313.sol";
import {ICloneableFactoryV5} from "rain-factory-pr271-976cd62/src/interface/ICloneableFactoryV5.sol";
import {BEACON_PROXY_CREATION_CODE} from "rain-factory-pr271-976cd62/src/generated/BeaconProxy.sol";
import {LibICloneableFactoryV5} from "rain-factory-pr271-976cd62/src/lib/LibICloneableFactoryV5.sol";

import {DeployDependency} from "./LibRainDeploy.sol";
import {CloneTarget} from "./LibRainDeployClone.sol";

/// @dev Where `BeaconProxy`'s runtime starts in `BEACON_PROXY_CREATION_CODE`: the constructor ends
/// `CODECOPY(0, 0x424, 0x10b)`, and the runtime is the creation code's tail.
uint256 constant BEACON_PROXY_RUNTIME_OFFSET = 0x424;

/// @dev Where the beacon immutable's word starts in `BeaconProxy`'s runtime: the operand of its single
/// `PUSH32`, which the constructor fills with `MSTORE(0x23, beacon)`.
uint256 constant BEACON_PROXY_BEACON_IMMUTABLE_OFFSET = 0x23;

/// @dev The artifact path a beacon proxy suite carries. It names no compiled source here: see
/// `BEACON_PROXY_UNANCHORABLE_REASON`.
string constant BEACON_PROXY_ARTIFACT_PATH = "rain-factory/BeaconProxy.sol:BeaconProxy";

string constant BEACON_PROXY_UNANCHORABLE_REASON = "An OpenZeppelin BeaconProxy, deployed by the factory from "
    "rain-factory's generated creation code with the beacon as its constructor argument. Its source is not "
    "compiled here, so there is no artifact to anchor it to; the beacon, and each implementation the beacon "
    "serves, are the anchored contracts, and because the beacon address is embedded in the proxy's runtime the "
    "recorded code hash is what says which beacon this proxy reads.";

/// @dev The implementation the stand-in beacon serves during a local deploy.
address constant BEACON_PROXY_STAND_IN_IMPLEMENTATION =
    address(uint160(uint256(keccak256("rain.deploy.beaconproxy.standin.implementation"))));

/// @dev Etched over a beacon proxy's beacon during a local deploy: its `implementation()` returns
/// `BEACON_PROXY_STAND_IN_IMPLEMENTATION`. Runtime code rather than a compiled concrete, so no pinned
/// pragma reaches the abstracts that import this library; a test holds it to the test-only
/// `BeaconProxyStandInBeacon` compiled under this repo's settings.
bytes constant BEACON_PROXY_STAND_IN_BEACON_RUNTIME_CODE =
    hex"6080604052348015600e575f80fd5b50600436106026575f3560e01c80635c60da1b14602a575b5f80fd5b604080517335bde2e333e6569b296b58650da50650dbcaa30b815290519081900360200190f3";

/// @dev Etched at `BEACON_PROXY_STAND_IN_IMPLEMENTATION` during a local deploy: its `initialize(bytes)`
/// returns the `ICloneableV2` success value for any data and reads no storage. A test holds it to the
/// test-only `BeaconProxyStandInImplementation`.
bytes constant BEACON_PROXY_STAND_IN_IMPLEMENTATION_RUNTIME_CODE =
    hex"6080604052348015600e575f80fd5b50600436106026575f3560e01c8063439fab9114602a575b5f80fd5b605c6035366004606e565b7fe0e57eda3f08f2a93bbe980d3df7f9c315eac41181f58b865a13d917fe769fc392915050565b60405190815260200160405180910390f35b5f8060208385031215607e575f80fd5b823567ffffffffffffffff808211156094575f80fd5b818501915085601f83011260a6575f80fd5b81358181111560b3575f80fd5b86602082850101111560c3575f80fd5b6020929092019691955090935050505056";

/// One contract a repo deploys as a beacon proxy, as a beacon proxy repo declares it.
/// The proxy's address does not commit to the implementation that runs `initialize(data)`: anyone may deploy it
/// while the beacon serves any implementation, and a broadcast that finds code there skips it unchecked. Every
/// implementation the beacon serves while the proxy is undeployed MUST give the same `initialize(data)` result, or
/// revert, as `ICloneableFactoryV5` requires.
struct BeaconProxyDeploy {
    /// The suite key, held to the key alphabet and to uniqueness like any other.
    string suite;
    /// The `ICloneableFactoryV5` that deploys the proxy.
    address factory;
    /// The beacon the proxy reads its implementation from.
    address beacon;
    /// The init data on every network.
    bytes data;
    /// Whether the init data is `initData` per network rather than `data` on every network.
    bool initDataPerNetwork;
    /// The init data on the network with the given chain id.
    function(uint256) view returns (bytes memory) initData;
    /// The caller-chosen salt, before the factory's beacon-proxy domain tag and `keccak256(data)`
    /// are hashed in with it.
    bytes32 salt;
    /// What MUST already be on a network, with exactly this code, before the proxy is broadcast
    /// there. MUST include the factory and the beacon.
    DeployDependency[] dependencies;
}

/// @title LibRainDeployBeaconProxy
/// @notice The BEACON_PROXY mechanism. A `CloneTarget`'s `implementation` holds the beacon.
library LibRainDeployBeaconProxy {
    /// Thrown when the factory on a network does not derive the address this package derives for
    /// the same beacon proxy.
    /// @param network The network whose factory was read.
    /// @param factory The factory that was asked.
    /// @param expected The address this package derives.
    /// @param predicted The address the factory says it would deploy to.
    error BeaconProxyFactoryPredictionMismatch(string network, address factory, address expected, address predicted);

    /// Thrown when a beacon proxy deployed on the fork answers `owner()` with a first word whose
    /// low 160 bits are the deploy key.
    /// Only `owner()` is read: roles, `AccessControl` admins, pending owners and admin slots the implementation's
    /// `initialize` grants to `tx.origin` are not, and the deploy key keeps them. The implementation MUST NOT grant
    /// the origin any authority, or the declaring repo's tests MUST assert it does not.
    /// @param network The network.
    /// @param proxy The proxy.
    error BeaconProxySeatsDeployKey(string network, address proxy);

    /// The proxy's creation code.
    /// @param beacon The beacon.
    /// @return The creation code, with the beacon as its constructor argument.
    function beaconProxyCreationCode(address beacon) internal pure returns (bytes memory) {
        return LibICloneableFactoryV5.beaconProxyCreationCode(beacon);
    }

    /// The proxy's runtime code.
    /// @param beacon The beacon.
    /// @return `BEACON_PROXY_CREATION_CODE` from `BEACON_PROXY_RUNTIME_OFFSET`, with the beacon's
    /// word at `BEACON_PROXY_BEACON_IMMUTABLE_OFFSET`.
    function beaconProxyRuntimeCode(address beacon) internal pure returns (bytes memory) {
        bytes memory creation = BEACON_PROXY_CREATION_CODE;
        bytes memory runtime = new bytes(creation.length - BEACON_PROXY_RUNTIME_OFFSET);
        for (uint256 i = 0; i < runtime.length; i++) {
            runtime[i] = creation[i + BEACON_PROXY_RUNTIME_OFFSET];
        }
        bytes32 word = bytes32(uint256(uint160(beacon)));
        for (uint256 i = 0; i < 0x20; i++) {
            runtime[BEACON_PROXY_BEACON_IMMUTABLE_OFFSET + i] = word[i];
        }
        return runtime;
    }

    /// The code hash a deployed proxy reports.
    /// @param beacon The beacon.
    /// @return `keccak256` of the runtime code.
    function beaconProxyDeployedCodehash(address beacon) internal pure returns (bytes32) {
        return keccak256(beaconProxyRuntimeCode(beacon));
    }

    /// The address the proxy lands at.
    /// @param target The proxy, its `implementation` the beacon.
    /// @return The predicted proxy address.
    function beaconProxyDeployedAddress(CloneTarget memory target) internal pure returns (address) {
        return LibICloneableFactoryV5.predictBeaconProxyAddress(
            target.factory,
            target.implementation,
            LibICloneableFactoryV5.effectiveBeaconProxyOpenSalt(target.salt, target.data)
        );
    }

    /// The BEACON_PROXY mechanism as a `LibRainDeploy.deployStepToNetworks` step.
    /// @param vm The Vm instance to broadcast with.
    /// @param network The network being deployed to.
    /// @param deployer The deployer address to broadcast as.
    /// @param targetData The `abi.encode`d `CloneTarget`.
    /// @return The address the factory deployed the proxy to.
    function beaconProxyDeployStep(Vm vm, string memory network, address deployer, bytes memory targetData)
        internal
        returns (address)
    {
        CloneTarget memory target = abi.decode(targetData, (CloneTarget));

        console2.log(" - Beacon Proxy Factory:", target.factory);
        address expectedAddress = beaconProxyDeployedAddress(target);
        address factoryPredictedAddress = ICloneableFactoryV5(target.factory)
            .predictBeaconProxyAddressOpenSalt(target.implementation, target.data, target.salt);
        if (factoryPredictedAddress != expectedAddress) {
            revert BeaconProxyFactoryPredictionMismatch(
                network, target.factory, expectedAddress, factoryPredictedAddress
            );
        }

        console2.log(" - Beacon proxy of beacon:", target.implementation);
        vm.startBroadcast(deployer);
        address proxy = ICloneableFactoryV5(target.factory)
            .beaconProxyDeterministicOpenSalt(target.implementation, target.data, target.salt);
        vm.stopBroadcast();

        // slither-disable-next-line low-level-calls
        (bool answered, bytes memory owner) = proxy.staticcall(abi.encodeCall(IERC5313.owner, ()));
        if (answered && owner.length >= 0x20 && address(uint160(abi.decode(owner, (uint256)))) == deployer) {
            revert BeaconProxySeatsDeployKey(network, proxy);
        }
        return proxy;
    }
}
