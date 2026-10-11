// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {ADDRESS_REGISTRY_ROOT} from "../../../src/concrete/AddressRegistry.sol";
import {IAddressRegistryV1} from "../../../src/interface/IAddressRegistryV1.sol";
import {LibAddressRegistryDeploy} from "../../../src/lib/LibAddressRegistryDeploy.sol";
import {LibAddressRegistryRegister} from "../../../src/lib/LibAddressRegistryRegister.sol";
import {LibRainDeploy, SupportedNetwork} from "../../../src/lib/LibRainDeploy.sol";

/// @title LibAddressRegistryRegisterOnForksTest
/// The fork loops of `LibAddressRegistryRegister`, against every supported
/// network's live registry: a bind simulated on each network's fork, the
/// simulation check on those forks, and the confirmed check on fresh forks —
/// which have not seen the simulated bind and so must refuse it.
///
/// The name is fresh per run, so no live binding can satisfy or contradict
/// anything here.
contract LibAddressRegistryRegisterOnForksTest is Test {
    function externalCheckRegisteredOnForks(
        string[] memory networks,
        uint256[] memory forkIds,
        string memory name,
        address account
    ) external {
        LibAddressRegistryRegister.checkRegisteredOnForks(vm, networks, networks, forkIds, name, account);
    }

    function externalCheckRegisteredOnNetworks(string[] memory networks, string memory name, address account) external {
        LibAddressRegistryRegister.checkRegisteredOnNetworks(vm, networks, networks, name, account);
    }

    /// Binds a fresh name on every supported network's fork from root, reads
    /// it back on each, and shows the confirmed check reads the chains rather
    /// than the simulation.
    function testRegisterOnEveryNetwork() external {
        string memory name = string.concat("rain.deploy.register-test.", vm.toString(vm.randomUint()));
        bytes32 hashed = keccak256(bytes(name));
        address account = vm.randomAddress();
        vm.assume(account != address(0));
        string[] memory networks = LibRainDeploy.supportedNetworks();
        SupportedNetwork[] memory configs = LibRainDeploy.declaredNetworkConfigs(networks);

        uint256[] memory forkIds =
            LibAddressRegistryRegister.registerOnNetworks(vm, networks, networks, ADDRESS_REGISTRY_ROOT, name, account);
        assertEq(forkIds.length, networks.length);

        for (uint256 i = 0; i < forkIds.length; i++) {
            vm.selectFork(forkIds[i]);
            assertEq(block.chainid, configs[i].chainId, networks[i]);
            (address bound,) =
                IAddressRegistryV1(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS).get(hashed);
            assertEq(bound, account, networks[i]);
        }

        LibAddressRegistryRegister.checkRegisteredOnForks(vm, networks, networks, forkIds, name, account);

        address other = address(uint160(account) ^ 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistryRegister.UnexpectedBinding.selector, networks[0], hashed, other, account
            )
        );
        this.externalCheckRegisteredOnForks(networks, forkIds, name, other);

        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, hashed));
        this.externalCheckRegisteredOnNetworks(networks, name, account);
    }

    /// A subset binds on exactly the networks selected, in selection order.
    function testRegisterOnSubset() external {
        string memory name = string.concat("rain.deploy.register-test.", vm.toString(vm.randomUint()));
        bytes32 hashed = keccak256(bytes(name));
        address account = vm.randomAddress();
        vm.assume(account != address(0));
        string[] memory networks = new string[](2);
        networks[0] = LibRainDeploy.BASE;
        networks[1] = LibRainDeploy.ARBITRUM_ONE;

        uint256[] memory forkIds = LibAddressRegistryRegister.registerOnNetworks(
            vm, networks, LibRainDeploy.supportedNetworks(), ADDRESS_REGISTRY_ROOT, name, account
        );
        assertEq(forkIds.length, 2);
        vm.selectFork(forkIds[0]);
        assertEq(block.chainid, 8453);
        vm.selectFork(forkIds[1]);
        assertEq(block.chainid, 42161);
        LibAddressRegistryRegister.checkRegisteredOnForks(vm, networks, networks, forkIds, name, account);
        (address bound,) = IAddressRegistryV1(LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS).get(hashed);
        assertEq(bound, account);
    }
}
