// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @title LibRegistryAuthority
/// @notice The root authority of the `ConfigRegistry` and the
/// `MigrationRegistry`, the same account on every network.
library LibRegistryAuthority {
    address constant ROOT_AUTHORITY = 0x0b300013CD54a8F1aC40981f80FaaA18b8Cc1E4c;
}
