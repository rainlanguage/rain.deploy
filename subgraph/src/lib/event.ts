import { Bytes, ethereum } from "@graphprotocol/graph-ts";

/**
 * The id every immutable history row in this subgraph is keyed by: the
 * transaction hash followed by the log index. That pair identifies a log
 * uniquely on a single chain, which is what makes the recorders idempotent —
 * graph-node replaying a block after a reorg rewrites the same rows instead of
 * appending duplicates of them.
 */
export function logRowId(event: ethereum.Event): Bytes {
  return event.transaction.hash.concatI32(event.logIndex.toI32());
}
