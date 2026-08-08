# rain.deploy

Tooling to deploy Solidity contracts deterministically across EVM networks via
the Zoltu deployment proxy.

Fundamentally Rain code is EVM-compatible and permissionlessly deployable
anywhere, but only a curated subset of networks are active deploy targets for
the Rain organisation. This library provides shared infrastructure for that
subset.

It answers:

- Are the dependencies of the current deployment available on this network?
- Does this deployment match other deployments on other networks?
- Have I deployed successfully to all expected networks?
- How do I track deployments over time and share addresses with other people?
- How do I ensure deployed code is bytecode-equivalent to local compilations?
- How does a deployment get a configured address — an owner, say — without
  baking one into its creation code, where changing it would move every future
  deployment?

Approach:

- Zoltu deterministic deployment proxy: same address on every supported network.
- Caller-provided supported-network and dependency lists.
- Hard guards against deploying to networks where dependencies are missing.
- Pre-calculated addresses asserted against the creation code before deploying,
  and against the chain after: silent failures fail loudly.
- Bytecode integrity checks (e.g. via the Rain Extrospection lib) supported
  post-deploy.
- A write-once address registry, read at run time rather than compiled in, and
  gated across every target network before a deploy.

## Address registry

`IAddressRegistryV1` binds an opaque `bytes32` name to an address. An immutable
root authority binds a name that is unbound; nothing, root included, can change
one after; and reading an unbound name reverts rather than answering with the
zero address. There is no rotation, no removal and no admin surface, because a
binding that can move is not worth checking before a deploy.

`LibAddressRegistry.resolve` reads it, verifying the registry's code hash first,
the same way `LibRainDeploy` verifies the Zoltu factory's. It resolves a name to
an address and stops there — what a consumer does with the address, and when, is
the consumer's business.

`LibRainDeploy.checkRegisteredAddressesOnNetworks` is the deploy-time gate:
every name must resolve to the address the deployment expects, on every target
network, before anything is broadcast. Because bindings are write-once, that
pre-flight is exactly as strong as checking inline — an answer that exists
cannot change, and one that does not exist reverts.

The implementation, `AddressRegistry`, lives in
[rain.factory.deploy](https://github.com/rainlanguage/rain.factory.deploy);
`LibAddressRegistry` pins its deterministic address and code hash.

## Install

Via [soldeer](https://soldeer.xyz):

```sh
forge soldeer install rain-deploy~<version>
```

## Develop

This repo uses [nix](https://nixos.org/download.html). The default shell is the
slim `sol-shell` from [rainix](https://github.com/rainlanguage/rainix).

```sh
nix develop          # enter the shell
forge soldeer install # install deps declared in foundry.toml
forge test
```

Tasks:

- `rainix-sol-test` — `forge test`
- `rainix-sol-static` — slither
- `rainix-sol-legal` — `reuse lint`

Use the nix-pinned `forge` for all development.

## Publish

Tag `v<x.y.z>` on `main`. The
[`Publish to Soldeer`](.github/workflows/publish-soldeer.yaml) wrapper delegates
to rainix's reusable workflow, which derives the package name from the repo name
(`rain.deploy` → `rain-deploy`).

## License

DecentraLicense 1.0 (DCL-1.0) — full text in
[`LICENSES/`](LICENSES/LicenseRef-DCL-1.0.txt). Roughly `CAL-1.0`
([opensource.org](https://opensource.org/license/cal-1-0)) plus user-data
disclosure obligations consistent with permissionless-blockchain assumptions.

This repo is [REUSE 3.2](https://reuse.software/spec-3.2/) compliant. Verify
locally:

```sh
nix develop -c rainix-sol-legal
```

## Contributions

Welcome under the same license. Contributors warrant that their contributions
are compliant.
