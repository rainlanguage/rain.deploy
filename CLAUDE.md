<!-- SPDX-License-Identifier: LicenseRef-DCL-1.0 -->
<!-- SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd -->

# CLAUDE.md

Only what an agent working here would get WRONG, never what it would merely take
a moment to find. Everything discoverable — the layout, what each contract does,
the verification design, the commands CI runs — is deliberately absent and stays
absent (rainlanguage/rainix#298). Path-scoped detail lives in `.claude/rules/`.

- **Broadcasting is key custody and real money.** Nothing automatic ever
  broadcasts: `Manual sol artifacts` is `workflow_dispatch` only, and no merge,
  tag or schedule may be given a path to it.
- **A `sol-v*` tag is the sole release trigger.** `[package].version` in
  `foundry.toml` is the version of the LAST Soldeer publish, not a next-version
  slot, so an ordinary PR does not bump it.
- **`src/generated/<tag>/` is an append-only record.** `cutRelease()` writes a
  tag directory once. A cut tag can never be un-cut and consumers pin what it
  holds, so a frozen record is never edited, renamed or deleted.
- **`ADDRESS_REGISTRY_ROOT == address(0)` is INTENDED.** It is the rollout
  state, not a defect: nothing calls from the zero address, so the registry is
  inert and fails loudly in both directions. Do not "fix" it. The root is welded
  into the creation code, so setting a real one moves the deploy address, the
  code hash and the snapshot together, as an ordinary source change.
