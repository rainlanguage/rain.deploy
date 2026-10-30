// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// @dev The Flare metaboard whose `MetaV1_2` log at `FLARE_EMISSION_BLOCK` is the emission.
address constant FLARE_META_BOARD = 0x8fD50fF9Db9835ba1B61394752A26F53D721D2a1;

/// @dev The emission's subject, which answers `describedByMetaV1()` with `FLARE_DESCRIBED_BY_META_HASH`.
address constant FLARE_DESCRIBED = 0x03e3f0C80332fB1b57EC884E9d481bAa58969883;

/// @dev The one Flare block holding the emission; the blocks either side hold no log at `FLARE_META_BOARD`.
uint256 constant FLARE_EMISSION_BLOCK = 69545712;

/// @dev `keccak256(FLARE_DESCRIBED_BY_META)`.
bytes32 constant FLARE_DESCRIBED_BY_META_HASH = 0xdde475220ea06da58884f3f7abbfc091637e02cb924b8b9a8a9d20dbd4ae703a;

/// @dev The meta the Flare emission carries, as logged.
bytes constant FLARE_DESCRIBED_BY_META =
    hex"ff0a89c674ee7874a400590155789cad924b4ec33010860b27991d20914a54a80b56541517283d00c699108bd40e9e712a2ec48a43328ed342e923a8d4cacaf6ffc8f81b1c5ed0737ede737edf237f42af6fc7a371a69d6dd073c62e5344c834f8d3eaf13ffb98265f8287d9348b49d0a8503150a93c12b0836073f4d5bbb12f90928730d11a6bd18cc0d83a30dd0197d809a5287ba519549e8b0381b2797bac162e580657acbc957c50544ef11066c8c15b821b7081c53239e25b308daa5064dfeaad3e1b467391a55991711602c59f5895bb20704bdb9df3dc4d92be085673bc1dab4ab31a352755dbb4dd6ea3641caf6821476d16aaa2589bc456e2e59677b1590e798cb8943ace5f418dbe355a4ff777760c3385d12a16b88665697409856a9cffd17bb8ff0577f091c67b1a3e3ed77c6c8f5dd8d809cdbff938fcc2bda8d8b07896b18bd106ca4753f298f4fb29496cc4edc4cb0929e9b28fa7e40b9008489e011bff52fe42f1a0509302706170706c69636174696f6e2f63626f7203676465666c617465";
