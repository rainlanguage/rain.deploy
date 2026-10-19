# Known false positives

## Equivalent mutants

- `LibRainDeployMechanism.deployAndBroadcast`: `UnverifiableSource`'s entry
  address read from `deploys.derivedAddresses[0]` instead of
  `deploys.expectedAddresses[0]` (Z7). `deployStepToNetworks` refuses any
  network whose derived address differs from its expected one before the event,
  so the two are equal there.
- `LibRainDeploySnapshot.declarationValue`: the value read as
  `tokens[tokens.length - 1]` instead of `tokens[4]` (D7), or the final
  `tokens.length != 5` loosened to `> 5` (T5G, D4). The count is already pinned
  to exactly 5 when the value is read, and a line reaching that check never
  holds fewer than five tokens: an unwrapped line holding exactly four takes the
  wrapped branch, and a wrapped line's four-space prefix splits into four empty
  tokens before its value.
