// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {ConfigBinding} from "../../src/lib/LibConfigRegistryRegister.sol";

/// @dev The value type the config tests bind and resolve as. The registry never
/// checks a value against it, so one type serves every test value.
string constant VALUE_TYPE = "address";

/// @dev `keccak256` of `VALUE_TYPE`, as `getV5` answers it.
bytes32 constant VALUE_TYPE_HASH = keccak256(bytes(VALUE_TYPE));

/// @dev A binding of `name` to `value` as `VALUE_TYPE`, with no metadata.
/// @param name The name as a consumer writes it.
/// @param value The ABI-encoded value.
/// @return The binding.
function configBinding(string memory name, bytes memory value) pure returns (ConfigBinding memory) {
    return ConfigBinding({name: name, valueType: VALUE_TYPE, value: value, meta: ""});
}
