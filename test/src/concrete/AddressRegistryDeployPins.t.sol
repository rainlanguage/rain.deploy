// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {LibRainDeploy} from "../../../src/lib/LibRainDeploy.sol";
import {LibAddressRegistryDeploy} from "../../../src/lib/LibAddressRegistryDeploy.sol";
import {AddressRegistry} from "../../../src/concrete/AddressRegistry.sol";

/// @title AddressRegistryDeployPinsTest
/// @notice `LibAddressRegistryDeploy` pins the deterministic address and code
/// hash of `AddressRegistry`, and `LibAddressRegistry` resolves names through
/// those pins. Both are a pure function of the creation code, which is a pure
/// function of this repo's compiler settings — and the contract, the settings
/// and the pins are all in this repo, so this suite closes the loop rather than
/// asserting across a boundary.
///
/// The root authority is a constant in that creation code, so changing the root
/// moves both pins and turns this suite red until they follow.
contract AddressRegistryDeployPinsTest is Test {
    /// The pins MUST be derivable from this source without deploying anything:
    /// the Zoltu factory is `CREATE2` over its calldata with a zero salt, so the
    /// address is a pure function of the creation code, and the code hash is
    /// `keccak256` of the runtime code that creation code leaves behind.
    function testAddressRegistryPinsDeriveFromThisSource() external pure {
        assertEq(
            LibRainDeploy.zoltuAddress(type(AddressRegistry).creationCode),
            LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS
        );
        assertEq(
            keccak256(type(AddressRegistry).runtimeCode), LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH
        );
    }

    /// Actually deploying this contract's creation code through the Zoltu
    /// factory MUST land at the pinned address with the pinned code hash, so the
    /// derivation is checked against the factory rather than only against
    /// itself.
    function testAddressRegistryDeploysToPinnedAddress() external {
        LibRainDeploy.etchZoltuFactory(vm);

        address deployed = LibRainDeploy.deployZoltu(type(AddressRegistry).creationCode);

        assertEq(deployed, LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_ADDRESS);
        assertEq(deployed.codehash, LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH);
        assertEq(keccak256(deployed.code), LibAddressRegistryDeploy.ADDRESS_REGISTRY_DEPLOYED_CODEHASH);
    }
}
