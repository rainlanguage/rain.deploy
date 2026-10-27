// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";

import {IConfigRegistryV4} from "../../../src/interface/IConfigRegistryV4.sol";
import {LibConfigRegistryDeploy} from "../../../src/lib/LibConfigRegistryDeploy.sol";
import {LibConfigRegistryRegister} from "../../../src/lib/LibConfigRegistryRegister.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {LibConfigRegistryFork} from "../../lib/LibConfigRegistryFork.sol";
import {LibConfigRegistryRead} from "../../lib/LibConfigRegistryRead.sol";
import {LibResolvedReadFixture} from "../../lib/LibResolvedReadFixture.sol";
import {configBinding} from "../../lib/ConfigTestBinding.sol";

/// @title LibConfigRegistryRegisterOnForksTest
/// The fork loops of `LibConfigRegistryRegister`, against every supported
/// network: a bind simulated on each network's fork, the simulation check on
/// those forks, and the confirmed check on fresh forks — which have not seen
/// the simulated bind and so must refuse it.
///
/// The candidate registry is live only once a release carrying it has been
/// deployed. The simulated binds run on forks the candidate is deployed onto
/// where it is absent, which is the state that deploy leaves; the entry point
/// that forks for itself is run against the chains as they are, and the
/// refusals expected on fresh forks are read off those chains.
///
/// The name is fresh per run, so no live binding can satisfy or contradict
/// anything here.
contract LibConfigRegistryRegisterOnForksTest is Test {
    /// The authority every run here binds under and reads under. Any account
    /// is one.
    address internal constant AUTHORITY = address(0xA11CE);

    function externalRegisterOnNetworks(string[] memory networks, string memory name, bytes memory value)
        external
        returns (uint256[] memory, string memory)
    {
        return LibConfigRegistryRegister.registerOnNetworks(vm, networks, networks, AUTHORITY, AUTHORITY, configBinding(name, value));
    }

    function externalRegisterOnForks(
        string[] memory networks,
        uint256[] memory forkIds,
        string memory name,
        bytes memory value
    ) external {
        LibConfigRegistryRegister.registerOnForks(vm, networks, networks, forkIds, AUTHORITY, AUTHORITY, configBinding(name, value));
    }

    function externalRegisterOnForksFrom(
        string[] memory networks,
        uint256[] memory forkIds,
        address sender,
        string memory name,
        bytes memory value
    ) external {
        LibConfigRegistryRegister.registerOnForks(vm, networks, networks, forkIds, sender, AUTHORITY, configBinding(name, value));
    }

    function externalCheckRegisteredOnForks(
        string[] memory networks,
        uint256[] memory forkIds,
        string memory name,
        bytes memory value
    ) external {
        LibConfigRegistryRegister.checkRegisteredOnForks(vm, networks, networks, forkIds, AUTHORITY, configBinding(name, value));
    }

    function externalCheckRegisteredOnNetworks(string[] memory networks, string memory name, bytes memory value)
        external
    {
        LibConfigRegistryRegister.checkRegisteredOnNetworks(vm, networks, networks, AUTHORITY, configBinding(name, value));
    }

    /// A fresh name, its hash, and a fresh address value.
    function fresh() internal view returns (string memory, bytes32, bytes memory) {
        string memory name = string.concat("rain.deploy.register-test.", vm.toString(vm.randomUint()));
        return (name, keccak256(bytes(name)), abi.encode(vm.randomAddress()));
    }

    /// One fork per network, each holding the candidate registry.
    function forksWithRegistry(string[] memory networks) internal returns (uint256[] memory) {
        uint256[] memory forkIds = LibRainDeploy.createForks(vm, networks);
        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            LibConfigRegistryFork.ensureDeployed(vm);
        }
        return forkIds;
    }

    /// Binds a fresh name on every supported network's fork from the
    /// authority, reads it back on each, and shows the confirmed check reads the
    /// chains rather than the simulation.
    function testRegisterOnEveryNetwork() external {
        (string memory name, bytes32 hashed, bytes memory value) = fresh();
        string[] memory networks = LibRainDeploy.supportedNetworks();
        SupportedNetwork[] memory configs = LibRainDeploy.declaredNetworkConfigs(networks);

        uint256[] memory forkIds = forksWithRegistry(networks);
        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            (bool broadcast,) =
                LibConfigRegistryRegister.registerOnSelectedChain(vm, configs[i], AUTHORITY, AUTHORITY, hashed, configBinding("", value));
            assertTrue(broadcast);
        }

        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            assertEq(vm.getChainId(), configs[i].chainId, networks[i]);
            assertEq(
                LibConfigRegistryRead.getValue(
                    IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS), AUTHORITY, hashed
                ),
                value,
                networks[i]
            );
        }

        LibConfigRegistryRegister.checkRegisteredOnForks(vm, networks, networks, forkIds, AUTHORITY, configBinding(name, value));

        bytes memory other = abi.encodePacked(value, bytes1(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryRegister.UnexpectedBinding.selector, networks[0], AUTHORITY, hashed, other, value
            )
        );
        this.externalCheckRegisteredOnForks(networks, forkIds, name, other);

        vm.selectFork(vm.createFork(networks[0]));
        vm.expectRevert(LibConfigRegistryFork.unboundResolveRevert(AUTHORITY, hashed));
        this.externalCheckRegisteredOnNetworks(networks, name, value);
    }

    /// `registerOnNetworks`, which forks for itself, against the chains as they
    /// are: it binds on every network when the candidate is deployed on every
    /// one, and otherwise refuses on the code hash at the first network it is
    /// missing from, having bound nothing anyone could read.
    function testRegisterOnNetworksAgainstLiveChains() external {
        (string memory name, bytes32 hashed, bytes memory value) = fresh();
        string[] memory networks = LibRainDeploy.supportedNetworks();

        uint256[] memory probes = LibRainDeploy.createForks(vm, networks);
        bytes memory refusal = "";
        for (uint256 i = 0; i < probes.length; i++) {
            vm.selectFork(probes[i]);
            if (!LibConfigRegistryFork.isDeployed()) {
                refusal = LibConfigRegistryFork.unboundResolveRevert(AUTHORITY, hashed);
                break;
            }
        }

        if (refusal.length > 0) {
            vm.expectRevert(refusal);
            this.externalRegisterOnNetworks(networks, name, value);
            return;
        }
        (uint256[] memory forkIds, string memory record) = this.externalRegisterOnNetworks(networks, name, value);
        assertEq(forkIds.length, networks.length);
        (,, string memory inputs) =
            LibConfigRegistryRegister.checkInputs(vm, networks, networks, AUTHORITY, AUTHORITY, configBinding(name, value));
        assertEq(record, inputs);
        LibConfigRegistryRegister.checkRegisteredOnForks(vm, networks, networks, forkIds, AUTHORITY, configBinding(name, value));
    }

    /// `registerOnNetworks` forks every selected network in declaration order;
    /// the persistent registry carries the first fork's bind to the rest,
    /// which skip.
    function testRegisterOnNetworksBindsEverySelected() external {
        (string memory name,, bytes memory value) = fresh();
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.BASE;
        networks[1] = LibRainDeploy.ARBITRUM_ONE;

        vm.createSelectFork(networks[0]);
        LibConfigRegistryFork.ensureDeployed(vm);
        vm.makePersistent(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);

        (,, string memory inputs) =
            LibConfigRegistryRegister.checkInputs(vm, networks, networks, AUTHORITY, AUTHORITY, configBinding(name, value));
        (uint256[] memory forkIds, string memory record) = this.externalRegisterOnNetworks(networks, name, value);
        assertEq(forkIds.length, 2);
        assertEq(record, inputs);
        LibConfigRegistryRegister.checkRegisteredOnForks(vm, networks, networks, forkIds, AUTHORITY, configBinding(name, value));
    }

    /// `registerOnForks` binds on every given fork's own registry, with
    /// nothing persistent: one `Register` log per network, and each fork's
    /// registry holds the value bound at that fork's own moment.
    function testRegisterOnForksBindsOnEachFork() external {
        (string memory name, bytes32 hashed, bytes memory value) = fresh();
        string[] memory networks = LibRainDeploy.supportedNetworks();
        uint256[] memory forkIds = forksWithRegistry(networks);
        IConfigRegistryV4 registry = IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);

        vm.recordLogs();
        this.externalRegisterOnForks(networks, forkIds, name, value);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 registers = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(registry) && logs[i].topics[0] == IConfigRegistryV4.Register.selector) {
                assertEq(logs[i].topics.length, 1);
                assertEq(logs[i].data, abi.encode(AUTHORITY, AUTHORITY, hashed, value));
                registers++;
            }
        }
        assertEq(registers, networks.length);

        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            assertEq(LibConfigRegistryRead.getValue(registry, AUTHORITY, hashed), value, networks[i]);
            assertEq(LibConfigRegistryRead.getMoment(registry, AUTHORITY, hashed), vm.getBlockTimestamp(), networks[i]);
        }
    }

    /// `registerOnForks` refuses fork ids not paired one to one with the
    /// selected networks, before selecting any fork.
    function testRegisterOnForksRefusesUnpairedForkIds() external {
        (string memory name,, bytes memory value) = fresh();
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.BASE;
        networks[1] = LibRainDeploy.ARBITRUM_ONE;
        uint256[] memory forkIds = new uint256[](1);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.ForkIdsLengthMismatch.selector, 2, 1));
        this.externalRegisterOnForks(networks, forkIds, name, value);
        forkIds = new uint256[](3);
        vm.expectRevert(abi.encodeWithSelector(LibRainDeploy.ForkIdsLengthMismatch.selector, 2, 3));
        this.externalRegisterOnForks(networks, forkIds, name, value);
    }

    /// `registerOnForks` refuses a value that is not whole words as
    /// `checkInputs` does, before selecting any fork.
    function testRegisterOnForksRefusesInputsBeforeSelecting() external {
        (string memory name,, bytes memory value) = fresh();
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.BASE;
        networks[1] = LibRainDeploy.ARBITRUM_ONE;
        uint256[] memory forkIds = LibResolvedReadFixture.unselectableForkIds(2);
        bytes memory unaligned = abi.encodePacked(value, bytes1(0));
        vm.expectRevert(abi.encodeWithSelector(LibConfigRegistryRegister.NonCanonicalValue.selector, unaligned));
        this.externalRegisterOnForksFrom(networks, forkIds, AUTHORITY, name, unaligned);
    }

    /// A subset binds on exactly the networks selected, in selection order.
    function testRegisterOnSubset() external {
        (string memory name, bytes32 hashed, bytes memory value) = fresh();
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.BASE;
        networks[1] = LibRainDeploy.ARBITRUM_ONE;
        SupportedNetwork[] memory configs =
            LibConfigRegistryRegister.selectNetworks(networks, LibRainDeploy.supportedNetworks());

        uint256[] memory forkIds = forksWithRegistry(networks);
        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            LibConfigRegistryRegister.registerOnSelectedChain(vm, configs[i], AUTHORITY, AUTHORITY, hashed, configBinding("", value));
        }
        vm.selectFork(forkIds[0]);
        assertEq(vm.getChainId(), 8453);
        vm.selectFork(forkIds[1]);
        assertEq(vm.getChainId(), 42161);
        LibConfigRegistryRegister.checkRegisteredOnForks(vm, networks, networks, forkIds, AUTHORITY, configBinding(name, value));

        // Forks paired with the wrong networks are refused on the chain id,
        // even though both registries hold the binding.
        uint256[] memory swapped = new uint256[](2);
        swapped[0] = forkIds[1];
        swapped[1] = forkIds[0];
        vm.expectRevert(
            abi.encodeWithSelector(LibConfigRegistryRegister.UnexpectedChainId.selector, "base", 8453, 42161)
        );
        this.externalCheckRegisteredOnForks(networks, swapped, name, value);
        assertEq(
            LibConfigRegistryRead.getValue(
                IConfigRegistryV4(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS), AUTHORITY, hashed
            ),
            value
        );
    }
}
