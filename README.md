# rain.deploy

Tooling to deploy Solidity code managed with foundry and nix to production using
the Zoltu deterministic deployment proxy to supported networks.

Fundamentally Rain code is EVM compatible so can be deployed to any EVM network.
All code is open source and permissionlessly deployable and useable, but only a
subset of all possible networks will be active deploy targets for the Rain
organisation/ecosystem based on use cases and demand.

Additionally, because Rain is expected to operate across many networks, several
questions naturally arise:

- Are the dependencies of the current deployment available on this network?
- Does this deployment match other deployments on other networks?
- Have I deployed sucessfully to all expected networks?
- How do I track deployments over time and share addresses with other people?
- How do I ensure the deployed code is bytecode equivalent to local compilations?

This repo helps to tool and answer these questions in as foolproof a way as
possible, without overreliance on processes that can be forgotten or
misunderstood.

- The Zoltu deterministic deployment proxy is used to ensure that addresses are
  the same across all networks.
- The interface into the library allows lists of supported networks and
  dependencies to be provided by the caller.
- Standard error handling and guards are provided to prevent deployments to
  networks missing dependencies and other silent failures in the deployment.
- Deployments only succeed if the resulting address matches a precalculated
  address (ideally committed to a repo somewhere)
- Post-deploy bytecode integrity checks are supported, such as those provided by
  the Rain Extrospection lib.