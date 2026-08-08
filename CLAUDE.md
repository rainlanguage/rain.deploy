<!-- SPDX-License-Identifier: LicenseRef-DCL-1.0 -->
<!-- SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd -->

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

rain.deploy is a Solidity library for deploying Rain Protocol contracts via the
Zoltu deterministic deployment proxy to multiple EVM networks. It ensures
identical contract addresses across all supported chains (Arbitrum, Base, Base
Sepolia, Flare, Polygon) because the Zoltu proxy is deployed at the same address
on every chain and deploys with `CREATE2` over its calldata under a zero salt,
so a contract's address is a pure function of its creation code.

## Build & Development

This project uses **Foundry** (forge) for Solidity development and **Nix** for
environment management.

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

CI runs three matrix tasks: `rainix-sol-legal`, `rainix-sol-test`,
`rainix-sol-static`.

## RPC Configuration

Fork tests require RPC endpoints defined in `.env` (gitignored):

```bash
ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc
BASE_RPC_URL=https://mainnet.base.org
FLARE_RPC_URL=https://flare-api.flare.network/ext/C/rpc
POLYGON_RPC_URL=https://polygon-rpc.com
```

These are referenced in `foundry.toml` under `[rpc_endpoints]`.

## Architecture

**`src/lib/LibRainDeploy.sol`** — the deploy library:

- `etchZoltuFactory(Vm)` — etches the Zoltu factory bytecode at the factory
  address (for networks where it isn't deployed)
- `zoltuAddress(bytes creationCode)` — derives the address the factory deploys
  creation code to, without deploying
- `deployZoltu(bytes creationCode)` — deploys creation code via the Zoltu
  factory (`0x7A0D94F55792C434d74a40883C6ed8545E406D12`) using low-level `call`,
  returns the deployed address
- `supportedNetworks()` — returns the list of Rain-supported network names (used
  as foundry RPC config aliases)
- `isStartBlock(...)` / `findDeployBlock(...)` — binary search a fork's history
  for the block a contract first appears at
- `checkResolvedAddresses(...)` — asserts an already-deployed contract holds the
  addresses the deployment expected, on the currently selected fork, via
  consumer-supplied static reads
- `checkResolvedAddressesOnNetworks(...)` — runs that check on every network. It
  runs AFTER the deploy, against state the deployment has already settled, which
  is the only point at which such a check means anything: registry bindings are
  mutable, so a pre-deploy check would read a source that can change before the
  constructor that consumes it
- `deployToNetworks(...)` — forks each network, verifies the factory and
  dependencies, deploys via Zoltu, verifies address and code hash
- `deployAndBroadcast(...)` — the main entry point: derives the deployer from a
  private key, then `deployToNetworks`

**`src/interface/IAddressRegistryV1.sol`** — the address registry interface: an
immutable root binds a `bytes32` name to an address (`register`), anyone reads a
bound name (`get`), and reading an unbound name reverts. Bindings are mutable so
an owning multisig can rotate without moving any consumer's deterministic
address; a consumer resolves once in its constructor and stores the answer, so a
re-binding never moves anything already deployed.

**`src/concrete/AddressRegistry.sol`** — the implementation. Two functions and
nothing else. `ADDRESS_REGISTRY_ROOT` is a compile-time constant and therefore
part of the creation code, so changing it moves the deterministic address and
code hash.

**`src/lib/LibAddressRegistryDeploy.sol`** — those pins, derived from the
creation code this repo compiles under this repo's own settings and checked
against it by `AddressRegistryDeployPinsTest`. Hand-written until the first
`sol-v*` release generates it from `src/generated/<tag>/`; no snapshot is frozen
while the root is a placeholder, because that directory is append-only.

**`src/lib/LibAddressRegistry.sol`** — reads that registry at its deterministic
address, verifying its code hash first, exactly as `LibRainDeploy` verifies
`ZOLTU_FACTORY_CODEHASH`. It resolves a name to an address and nothing more:
what a consumer resolves a name for, and when, is the consumer's business.

The libraries are designed to be called from Foundry scripts (`forge script`) in
consuming repos, not directly. Consuming repos provide their own creation code,
expected addresses, expected code hashes, and dependency lists.

## Key Design Patterns

- **Deterministic addresses**: Zoltu proxy ensures same address on every chain.
  Deployments fail if the resulting address doesn't match `expectedAddress`.
- **Code hash verification**: Post-deploy bytecode integrity is verified against
  `expectedCodeHash`. The address registry is verified the same way before it is
  read.
- **Dependency checking**: Before deploying to any network, all dependencies
  (contract addresses) are verified to have code on-chain.
- **Idempotent deploys**: If code already exists at the expected address,
  deployment is skipped for that network.
- **Resolve once, verify after**: registry bindings are mutable, so the
  meaningful check is not "does the registry say what I expect" before a deploy
  but "does the deployed contract hold what I expect" after one. A consumer
  resolves in its constructor; the deployment is then verified across every
  network before anything migrates onto it.
- **Deploy-repo lifecycle**: a manual `sol-v*` tag is the sole release trigger
  (`rainix-tag-release`), because this repo carries a deployed concrete whose
  pins consumers rely on. `[package].version` is the LAST released version and
  moves only in lockstep with its snapshot.

## License

DecentraLicense 1.0 (LicenseRef-DCL-1.0). All source files must have SPDX
headers. REUSE compliance is enforced in CI.
