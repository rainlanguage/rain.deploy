// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

// Hand-written fixture in the frozen per-release snapshot shape, as
// `0_0_1/MockDeployable.pointers.sol` explains. A SECOND release, for two
// reasons neither of which one release covers.
//
// It is a different contract from `0_0_1`, so the two releases derive different
// addresses, which is what a repo with a version history actually looks like.
//
// It records the same creation code the candidate compiles, which is the
// ordinary state of a deploy repo between a release and the next source change:
// the newest release and the candidate ARE the same bytes, so they derive the
// same address, and a derivation that could not run twice for one address would
// break on the common case rather than an exotic one.

/// @dev Hash of the known bytecode.
bytes32 constant BYTECODE_HASH = bytes32(0xf80fdab74d5f11f3901f56541fc0b1242013dbca435f771819dbc09022d1d604);

/// @dev The deterministic deploy address of the contract when deployed via
/// the Zoltu factory.
address constant DEPLOYED_ADDRESS = address(0xE19c2335AdbFAD3250FA150739cC5C11cE5935eD);

/// @dev The creation bytecode of the contract.
bytes constant CREATION_CODE =
    hex"6080604052602b5f5560636001553480156017575f80fd5b5060558060235f395ff3fe6080604052348015600e575f80fd5b50600436106030575f3560e01c80633fa4f2451460345780638529587714604d575b5f80fd5b603b5f5481565b60405190815260200160405180910390f35b603b6001548156";

/// @dev The runtime bytecode of the contract.
bytes constant RUNTIME_CODE =
    hex"6080604052348015600e575f80fd5b50600436106030575f3560e01c80633fa4f2451460345780638529587714604d575b5f80fd5b603b5f5481565b60405190815260200160405180910390f35b603b6001548156";
