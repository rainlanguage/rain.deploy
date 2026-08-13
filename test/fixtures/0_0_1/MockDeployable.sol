// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

// Hand-written fixture, deliberately shaped exactly like the frozen per-release
// snapshot a deploy repo generates at `src/generated/<tag>/<Contract>.sol`.
// It exists so the verification abstracts are exercised against the real shape
// consumers have — four literal constants and no reference to any source
// contract — rather than only against values re-derived at test time, which
// would check the derivation against itself.
//
// A released snapshot is FROZEN. `CREATION_CODE` is a literal here rather than
// `type(MockDeployable).creationCode` for exactly the reason a released tag is
// never anchored to current source: the snapshot records what was deployed, and
// nothing requires the contract that produced it to still exist.
//
// The values are `MockDeployable` under this repo's pinned compiler settings.
// They are pins, so a settings change moves them and turns the suite red until
// they follow, which is the point.

/// @dev Hash of the known bytecode.
bytes32 constant BYTECODE_HASH = bytes32(0x0cff4019cbc9f3009ec77b6438233bbe4c5d991a5766aa56c97dbb593feb3663);

/// @dev The deterministic deploy address of the contract when deployed via
/// the Zoltu factory.
address constant DEPLOYED_ADDRESS = address(0x0c04367b381F8Ca252aD2516F1Eac2b9B2ca928F);

/// @dev The creation bytecode of the contract.
bytes constant CREATION_CODE =
    hex"6080604052602a5f553480156012575f80fd5b50604380601e5f395ff3fe6080604052348015600e575f80fd5b50600436106026575f3560e01c80633fa4f24514602a575b5f80fd5b60315f5481565b60405190815260200160405180910390f3";

/// @dev The runtime bytecode of the contract.
bytes constant RUNTIME_CODE =
    hex"6080604052348015600e575f80fd5b50600436106026575f3560e01c80633fa4f24514602a575b5f80fd5b60315f5481565b60405190815260200160405180910390f3";
