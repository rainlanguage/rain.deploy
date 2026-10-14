// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {ADDRESS_REGISTRY_ROOT} from "../../src/concrete/AddressRegistry.sol";
import {IAddressRegistryV1} from "../../src/interface/IAddressRegistryV1.sol";
import {LibAddressRegistryRegister} from "../../src/lib/LibAddressRegistryRegister.sol";
import {RegisterAddress} from "../../script/RegisterAddress.sol";

/// @title RegisterAddressTest
/// The script's wiring: which variables it reads, that the signer is the
/// script's `msg.sender`, and that both entries default to every supported
/// network. `LibAddressRegistryRegister`'s own tests cover what it does with
/// them.
///
/// ONE test function, because it writes process-wide environment variables and
/// forge runs test functions concurrently. Nothing else in the suite reads or
/// writes these names, and the unset-networks cases run before the variable is
/// first set, since a set variable cannot be unset.
contract RegisterAddressTest is Test {
    function testWiring() external {
        RegisterAddress script = new RegisterAddress();
        string memory name = string.concat("rain.deploy.register-test.", vm.toString(vm.randomUint()));

        vm.setEnv("ADDRESS_REGISTRY_NAME", "Not.Canonical");
        vm.setEnv("ADDRESS_REGISTRY_ACCOUNT", vm.toString(address(1)));
        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistryRegister.NonCanonicalName.selector, "Not.Canonical"));
        script.run();

        vm.setEnv("ADDRESS_REGISTRY_NAME", name);
        vm.setEnv("ADDRESS_REGISTRY_ACCOUNT", vm.toString(address(0)));
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.ZeroAccount.selector, keccak256(bytes(name))));
        script.run();

        // Networks unset: the default is every declared network, which is a
        // valid selection, so the refusal reached is the sender — this test
        // contract, as the script's `msg.sender`.
        vm.setEnv("ADDRESS_REGISTRY_ACCOUNT", vm.toString(address(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistryRegister.SenderNotRoot.selector, address(this), ADDRESS_REGISTRY_ROOT
            )
        );
        script.run();

        // The confirmed check forks every declared network fresh, where the
        // fresh name is bound nowhere.
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV1.NameNotRegistered.selector, keccak256(bytes(name))));
        script.verify();

        vm.setEnv("ADDRESS_REGISTRY_NETWORKS", "base,nowhere");
        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        script.run();
        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistryRegister.NetworkNotDeclared.selector, "nowhere"));
        script.verify();

        vm.setEnv("ADDRESS_REGISTRY_NAME", "Not.Canonical");
        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistryRegister.NonCanonicalName.selector, "Not.Canonical"));
        script.verify();
    }
}
