// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev The creation code of `AddressRegistry`, the `IAddressRegistryV1`
/// implementation in
/// [rain.factory.deploy](https://github.com/rainlanguage/rain.factory.deploy),
/// as compiled by that repo (`solc 0.8.25`, optimizer on at 100,000 runs, evm
/// version `cancun`, no metadata):
///
/// ```sh
/// forge inspect src/concrete/AddressRegistry.sol:AddressRegistry bytecode
/// ```
///
/// This library cannot depend on that repo — it depends on this one — so the
/// creation code is carried here instead, and it is what makes the pins in
/// `LibAddressRegistry` checkable rather than asserted: deploying this through
/// the Zoltu factory MUST land at `ADDRESS_REGISTRY` with
/// `ADDRESS_REGISTRY_CODEHASH`. If the registry's source changes — and the root
/// authority baked into it is part of that source — this blob and both pins
/// change together, and the test that deploys it says so.
bytes constant ADDRESS_REGISTRY_CREATION_CODE =
    hex"6080604052348015600e575f80fd5b506102e68061001c5f395ff3fe608060405234801561000f575f80fd5b5060043610610034575f3560e01c80638eaa6ac014610038578063d22057a914610074575b5f80fd5b61004b610046366004610289565b610089565b60405173ffffffffffffffffffffffffffffffffffffffff909116815260200160405180910390f35b6100876100823660046102a0565b6100f1565b005b5f8181526020819052604090205473ffffffffffffffffffffffffffffffffffffffff16806100ec576040517fe9b7924f000000000000000000000000000000000000000000000000000000008152600481018390526024015b60405180910390fd5b919050565b3373deaddeaddeaddeaddeaddeaddeaddeaddeaddead14610140576040517f8c7257830000000000000000000000000000000000000000000000000000000081523360048201526024016100e3565b73ffffffffffffffffffffffffffffffffffffffff8116610190576040517f657fb0ff000000000000000000000000000000000000000000000000000000008152600481018390526024016100e3565b5f8281526020819052604090205473ffffffffffffffffffffffffffffffffffffffff16801561020b576040517f7887e8c00000000000000000000000000000000000000000000000000000000081526004810184905273ffffffffffffffffffffffffffffffffffffffff821660248201526044016100e3565b5f8381526020819052604080822080547fffffffffffffffffffffffff00000000000000000000000000000000000000001673ffffffffffffffffffffffffffffffffffffffff86169081179091559051909185917f1082cda15f9606da555bb7e9bf4eeee2f8e34abe85d3924bf9bacb716f8feca69190a3505050565b5f60208284031215610299575f80fd5b5035919050565b5f80604083850312156102b1575f80fd5b82359150602083013573ffffffffffffffffffffffffffffffffffffffff811681146102db575f80fd5b80915050925092905056";

/// @dev The root authority baked into `ADDRESS_REGISTRY_CREATION_CODE`, needed
/// to bind a name in a test. Currently the placeholder `rain.factory.deploy`
/// carries until a human supplies the real root; when that happens the creation
/// code above and both `LibAddressRegistry` pins change with it.
address constant ADDRESS_REGISTRY_ROOT = address(0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD);
