{
  description = "Flake for development workflows.";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    # Pinned to the rev the rainix reusable workflows run, not to rainix HEAD.
    # Every job in `rainix.yaml` executes
    # `nix develop github:rainlanguage/rainix/$RAINIX_SHA#sol-shell -c <task>`,
    # where `RAINIX_SHA` is a single constant shared across every reusable in
    # rainix. `devShells.default` here is that same `sol-shell`, so matching the
    # rev is what makes a local run of a gate the same run CI does; anything
    # else silently ships a second, differently-versioned toolchain that the
    # merge gate does not use. An unpinned url does not avoid a pin — the lock
    # file pins it regardless — it only makes the pinned rev arbitrary.
    #
    # Bump this whenever rainix moves `RAINIX_SHA`. Current value from
    # https://github.com/rainlanguage/rainix/blob/main/.github/workflows/rainix-sol-static.yaml
    rainix.url = "github:rainlanguage/rainix/53e96a7d0a97d7c7c75c3b2412521324776fdac6";
    rain.url = "github:rainlanguage/rain.cli";
  };

  outputs =
    {
      flake-utils,
      rainix,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (system: {
      packages = rainix.packages.${system};
      devShells.default = rainix.devShells.${system}.sol-shell;
    });
}
