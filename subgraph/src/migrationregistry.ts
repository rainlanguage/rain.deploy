import {
  BigInt,
  ByteArray,
  Bytes,
  crypto,
  ethereum,
} from "@graphprotocol/graph-ts";
import {
  Approved,
  Migrated,
  Revoked,
} from "../generated/MigrationRegistry/MigrationRegistry";
import {
  Approved as ApprovedV5,
  ApprovedUnscoped,
  MetaV1_2,
  Migrated as MigratedV5,
  Revoked as RevokedV5,
  RevokedUnscoped,
} from "../generated/MigrationRegistryV5/MigrationRegistryV5";
import { MigrationLine, MigrationRecord } from "../generated/schema";
import { ContractKind, getOrCreateContract } from "./lib/contract";
import { logRowId } from "./lib/event";
import {
  addressWord,
  recordDelegateChange,
  recordUnscopedDelegateChange,
  recordMetaSubjectRecord,
  recordRegistryMeta,
  registryMetaSubject,
} from "./lib/registry";

/** `MIGRATION_HEAD_GENESIS`: the head of a line with no records. */
export function migrationHeadGenesis(): Bytes {
  return Bytes.fromByteArray(
    crypto.keccak256(
      ByteArray.fromUTF8("rain.migration-registry.head.genesis"),
    ),
  );
}

/** `MigrationLine.id`: registry ++ writer ++ the `bytes32` namespace. */
export function migrationLineId(
  registry: Bytes,
  writer: Bytes,
  namespace: Bytes,
): Bytes {
  return registry.concat(writer).concat(namespace);
}

/**
 * The `IMigrationRegistryV5` `MetaV1_2` subject for a record:
 * `keccak256(abi.encode(writer, namespace, migration))`.
 */
export function migrationMetaSubject(
  writer: Bytes,
  namespace: Bytes,
  migration: Bytes,
): Bytes {
  return registryMetaSubject(
    addressWord(writer).concat(namespace).concat(migration),
  );
}

/**
 * Record one `Migrated` as the next record in its line. The registry refuses
 * any write not applied onto the line's current head, so log order is line
 * order: the record's `appliedOnto` is the head before it and it becomes the
 * new head. A replay of a log already recorded returns null before touching
 * the line, so `index` and `recordCount` count each log once.
 */
function recordMigrated(
  kind: string,
  event: ethereum.Event,
  sender: Bytes,
  writer: Bytes,
  namespace: Bytes,
  migration: Bytes,
  appliedAt: BigInt,
  metaSubject: Bytes | null,
): MigrationRecord | null {
  let rowId = logRowId(event);
  if (MigrationRecord.load(rowId) !== null) {
    return null;
  }
  let registry = getOrCreateContract(event.address, kind, event.block.number);
  let id = migrationLineId(registry.id, writer, namespace);
  let line = MigrationLine.load(id);
  let appliedOnto = migrationHeadGenesis();
  let index = 0;
  if (line === null) {
    line = new MigrationLine(id);
    line.registry = registry.id;
    line.writer = writer;
    line.namespace = namespace;
  } else {
    appliedOnto = line.head;
    index = line.recordCount;
  }

  let row = new MigrationRecord(rowId);
  row.line = id;
  row.index = index;
  row.migration = migration;
  row.appliedOnto = appliedOnto;
  row.appliedAt = appliedAt;
  row.sender = sender;
  row.blockNumber = event.block.number;
  row.blockTimestamp = event.block.timestamp;
  row.transactionHash = event.transaction.hash;
  row.transactionFrom = event.transaction.from;
  row.logIndex = event.logIndex;
  row.metaSubject = metaSubject;
  row.save();

  line.head = migration;
  line.headRecord = rowId;
  line.recordCount = index + 1;
  line.save();
  return row;
}

export function handleMigrationRegistryMigrated(event: Migrated): void {
  recordMigrated(
    ContractKind.MIGRATION_REGISTRY,
    event,
    event.params.sender,
    event.params.writer,
    event.params.namespace,
    event.params.migration,
    event.params.appliedAt,
    null,
  );
}

export function handleMigrationRegistryV5Migrated(event: MigratedV5): void {
  let subject = migrationMetaSubject(
    event.params.writer,
    event.params.namespace,
    event.params.migration,
  );
  let row = recordMigrated(
    ContractKind.MIGRATION_REGISTRY_V5,
    event,
    event.params.sender,
    event.params.writer,
    event.params.namespace,
    event.params.migration,
    event.params.appliedAt,
    subject,
  );
  if (row !== null) {
    recordMetaSubjectRecord(event.address, subject, row.id);
  }
}

export function handleMigrationRegistryApproved(event: Approved): void {
  recordDelegateChange(
    ContractKind.MIGRATION_REGISTRY,
    event,
    event.params.sender,
    event.params.scope,
    event.params.delegate,
    true,
  );
}

export function handleMigrationRegistryRevoked(event: Revoked): void {
  recordDelegateChange(
    ContractKind.MIGRATION_REGISTRY,
    event,
    event.params.sender,
    event.params.scope,
    event.params.delegate,
    false,
  );
}

export function handleMigrationRegistryV5Approved(event: ApprovedV5): void {
  recordDelegateChange(
    ContractKind.MIGRATION_REGISTRY_V5,
    event,
    event.params.sender,
    event.params.scope,
    event.params.delegate,
    true,
  );
}

export function handleMigrationRegistryV5Revoked(event: RevokedV5): void {
  recordDelegateChange(
    ContractKind.MIGRATION_REGISTRY_V5,
    event,
    event.params.sender,
    event.params.scope,
    event.params.delegate,
    false,
  );
}

export function handleMigrationRegistryV5MetaV1_2(event: MetaV1_2): void {
  recordRegistryMeta(
    ContractKind.MIGRATION_REGISTRY_V5,
    event,
    event.params.sender,
    event.params.subject,
    event.params.meta,
  );
}

export function handleMigrationRegistryV5ApprovedUnscoped(
  event: ApprovedUnscoped,
): void {
  recordUnscopedDelegateChange(
    ContractKind.MIGRATION_REGISTRY_V5,
    event,
    event.params.sender,
    event.params.delegate,
    true,
  );
}

export function handleMigrationRegistryV5RevokedUnscoped(
  event: RevokedUnscoped,
): void {
  recordUnscopedDelegateChange(
    ContractKind.MIGRATION_REGISTRY_V5,
    event,
    event.params.sender,
    event.params.delegate,
    false,
  );
}
