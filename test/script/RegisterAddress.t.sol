// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {ADDRESS_REGISTRY_ROOT} from "../../src/concrete/AddressRegistry.sol";
import {IAddressRegistryV2} from "../../src/interface/IAddressRegistryV2.sol";
import {LibRainDeploy} from "../../src/lib/LibRainDeploy.sol";
import {LibAddressRegistryRegister} from "../../src/lib/LibAddressRegistryRegister.sol";
import {RegisterAddress} from "../../script/RegisterAddress.sol";
import {LibAddressRegistryFork} from "../lib/LibAddressRegistryFork.sol";

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
        vm.setEnv("ADDRESS_REGISTRY_VALUE", vm.toString(abi.encode(address(1))));
        vm.expectRevert(abi.encodeWithSelector(LibAddressRegistryRegister.NonCanonicalName.selector, "Not.Canonical"));
        script.run();

        vm.setEnv("ADDRESS_REGISTRY_NAME", name);
        vm.setEnv("ADDRESS_REGISTRY_VALUE", "0x");
        vm.expectRevert(abi.encodeWithSelector(IAddressRegistryV2.EmptyValue.selector, keccak256(bytes(name))));
        script.run();

        // Networks unset: the default is every declared network, which is a
        // valid selection, so the refusal reached is the sender — this test
        // contract, as the script's `msg.sender`.
        vm.setEnv("ADDRESS_REGISTRY_VALUE", vm.toString(abi.encode(address(1))));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibAddressRegistryRegister.SenderNotRoot.selector, address(this), ADDRESS_REGISTRY_ROOT
            )
        );
        script.run();

        // The confirmed check forks every declared network fresh, where the
        // fresh name is bound nowhere. The first network fails first, so its
        // fork says which refusal that is.
        vm.makePersistent(address(script));
        vm.createSelectFork(LibRainDeploy.supportedNetworks()[0]);
        vm.expectRevert(LibAddressRegistryFork.unboundResolveRevert(keccak256(bytes(name))));
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
