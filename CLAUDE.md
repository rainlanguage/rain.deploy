<!-- SPDX-License-Identifier: LicenseRef-DCL-1.0 -->
<!-- SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd -->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

rain.deploy is a Solidity library for deploying Rain Protocol contracts via the Zoltu deterministic deployment proxy to multiple EVM networks. It ensures identical contract addresses across all supported chains (Arbitrum, Base, Flare, Polygon) because the Zoltu proxy is deployed at the same address on every chain and uses CREATE with a predictable nonce.

## Build & Development

This project uses **Foundry** (forge) for Solidity development and **Nix** for environment management.

```bash
# Enter the nix dev shell (provides forge and all tooling)
nix develop

# Build
nix develop -c forge build

# Run tests
nix develop -c rainix-sol-test

# Run a single test
nix develop -c forge test --match-test "testName"

# Static analysis / linting
nix develop -c rainix-sol-static

# License/legal checks (REUSE compliance)
nix develop -c rainix-sol-legal
```

CI runs three matrix tasks: `rainix-sol-legal`, `rainix-sol-test`, `rainix-sol-static`.

## Architecture

The entire library is a single file: `src/lib/LibRainDeploy.sol`.

**LibRainDeploy** provides:
- `deployZoltu(bytes creationCode)` — deploys creation code via the Zoltu factory (`0x7A0D94F55792C434d74a40883C6ed8545E406D12`) using low-level `call`, returns the deployed address
- `supportedNetworks()` — returns the list of Rain-supported network names (used as foundry RPC config aliases)
- `deployAndBroadcastToSupportedNetworks(...)` — the main entry point: forks each network, checks dependencies exist, deploys via Zoltu, verifies the deployed address and code hash match expectations

The library is designed to be called from Foundry scripts (`forge script`) in consuming repos, not directly. Consuming repos provide their own creation code, expected addresses, expected code hashes, and dependency lists.

## Key Design Patterns

- **Deterministic addresses**: Zoltu proxy ensures same address on every chain. Deployments fail if the resulting address doesn't match `expectedAddress`.
- **Code hash verification**: Post-deploy bytecode integrity is verified against `expectedCodeHash`.
- **Dependency checking**: Before deploying to any network, all dependencies (contract addresses) are verified to have code on-chain.
- **Idempotent deploys**: If code already exists at the expected address, deployment is skipped for that network.

## License

DecentraLicense 1.0 (LicenseRef-DCL-1.0). All source files must have SPDX headers. REUSE compliance is enforced in CI.
