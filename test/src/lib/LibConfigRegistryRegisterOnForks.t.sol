// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {CONFIG_REGISTRY_ROOT} from "../../../src/concrete/ConfigRegistry.sol";
import {IConfigRegistryV1} from "../../../src/interface/IConfigRegistryV1.sol";
import {LibConfigRegistryDeploy} from "../../../src/lib/LibConfigRegistryDeploy.sol";
import {LibConfigRegistryRegister} from "../../../src/lib/LibConfigRegistryRegister.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";
import {LibConfigRegistryFork} from "../../lib/LibConfigRegistryFork.sol";

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
    function externalRegisterOnNetworks(string[] memory networks, string memory name, bytes memory value)
        external
        returns (uint256[] memory)
    {
        return LibConfigRegistryRegister.registerOnNetworks(vm, networks, networks, CONFIG_REGISTRY_ROOT, name, value);
    }

    function externalCheckRegisteredOnForks(
        string[] memory networks,
        uint256[] memory forkIds,
        string memory name,
        bytes memory value
    ) external {
        LibConfigRegistryRegister.checkRegisteredOnForks(vm, networks, networks, forkIds, name, value);
    }

    function externalCheckRegisteredOnNetworks(string[] memory networks, string memory name, bytes memory value)
        external
    {
        LibConfigRegistryRegister.checkRegisteredOnNetworks(vm, networks, networks, name, value);
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

    /// Binds a fresh name on every supported network's fork from root, reads
    /// it back on each, and shows the confirmed check reads the chains rather
    /// than the simulation.
    function testRegisterOnEveryNetwork() external {
        (string memory name, bytes32 hashed, bytes memory value) = fresh();
        string[] memory networks = LibRainDeploy.supportedNetworks();
        SupportedNetwork[] memory configs = LibRainDeploy.declaredNetworkConfigs(networks);

        uint256[] memory forkIds = forksWithRegistry(networks);
        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            (bool broadcast,) =
                LibConfigRegistryRegister.registerOnSelectedChain(vm, configs[i], CONFIG_REGISTRY_ROOT, hashed, value);
            assertTrue(broadcast);
        }

        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            assertEq(block.chainid, configs[i].chainId, networks[i]);
            (bytes memory bound,) =
                IConfigRegistryV1(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS).getV1(hashed);
            assertEq(bound, value, networks[i]);
        }

        LibConfigRegistryRegister.checkRegisteredOnForks(vm, networks, networks, forkIds, name, value);

        bytes memory other = abi.encodePacked(value, bytes1(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistryRegister.UnexpectedBinding.selector, networks[0], hashed, other, value
            )
        );
        this.externalCheckRegisteredOnForks(networks, forkIds, name, other);

        vm.selectFork(vm.createFork(networks[0]));
        vm.expectRevert(LibConfigRegistryFork.unboundResolveRevert(hashed));
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
                refusal = LibConfigRegistryFork.unboundResolveRevert(hashed);
                break;
            }
        }

        if (refusal.length > 0) {
            vm.expectRevert(refusal);
            this.externalRegisterOnNetworks(networks, name, value);
            return;
        }
        uint256[] memory forkIds = this.externalRegisterOnNetworks(networks, name, value);
        assertEq(forkIds.length, networks.length);
        LibConfigRegistryRegister.checkRegisteredOnForks(vm, networks, networks, forkIds, name, value);
    }

    /// `registerOnNetworks` binds on every selected network, each on its own
    /// chain. The registry is persistent, so each fork it creates holds it.
    function testRegisterOnNetworksBindsEverySelected() external {
        (string memory name,, bytes memory value) = fresh();
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.BASE;
        networks[1] = LibRainDeploy.ARBITRUM_ONE;

        vm.createSelectFork(networks[0]);
        LibConfigRegistryFork.ensureDeployed(vm);
        vm.makePersistent(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS);

        uint256[] memory forkIds = this.externalRegisterOnNetworks(networks, name, value);
        assertEq(forkIds.length, 2);
        LibConfigRegistryRegister.checkRegisteredOnForks(vm, networks, networks, forkIds, name, value);
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
            LibConfigRegistryRegister.registerOnSelectedChain(vm, configs[i], CONFIG_REGISTRY_ROOT, hashed, value);
        }
        vm.selectFork(forkIds[0]);
        assertEq(block.chainid, 8453);
        vm.selectFork(forkIds[1]);
        assertEq(block.chainid, 42161);
        LibConfigRegistryRegister.checkRegisteredOnForks(vm, networks, networks, forkIds, name, value);

        // Forks paired with the wrong networks are refused on the chain id,
        // even though both registries hold the binding.
        uint256[] memory swapped = new uint256[](2);
        swapped[0] = forkIds[1];
        swapped[1] = forkIds[0];
        vm.expectRevert(
            abi.encodeWithSelector(LibConfigRegistryRegister.UnexpectedChainId.selector, "base", 8453, 42161)
        );
        this.externalCheckRegisteredOnForks(networks, swapped, name, value);
        (bytes memory bound,) = IConfigRegistryV1(LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_ADDRESS).getV1(hashed);
        assertEq(bound, value);
    }
}
