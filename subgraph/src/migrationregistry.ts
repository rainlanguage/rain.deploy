// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd

import { ByteArray, Bytes, crypto } from "@graphprotocol/graph-ts";
import {
  Approved,
  ApprovedUnscoped,
  MetaV1_2,
  Migrated,
  Revoked,
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

export function migrationMetaSubject(
  writer: Bytes,
  namespace: Bytes,
  migration: Bytes,
): Bytes {
  return registryMetaSubject(
    addressWord(writer).concat(namespace).concat(migration),
  );
}

export function handleMigrationRegistryV5Migrated(event: Migrated): void {
  let rowId = logRowId(event);
  if (MigrationRecord.load(rowId) !== null) {
    return;
  }
  let writer = event.params.writer;
  let namespace = event.params.namespace;
  let migration = event.params.migration;
  let subject = migrationMetaSubject(writer, namespace, migration);
  let registry = getOrCreateContract(
    event.address,
    ContractKind.MIGRATION_REGISTRY_V5,
    event.block.number,
  );
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
  row.appliedAt = event.params.appliedAt;
  row.sender = event.params.sender;
  row.blockNumber = event.block.number;
  row.blockTimestamp = event.block.timestamp;
  row.transactionHash = event.transaction.hash;
  row.transactionFrom = event.transaction.from;
  row.logIndex = event.logIndex;
  row.metaSubject = subject;
  row.save();

  line.head = migration;
  line.headRecord = rowId;
  line.recordCount = index + 1;
  line.save();

  recordMetaSubjectRecord(event.address, subject, rowId);
}

export function handleMigrationRegistryV5Approved(event: Approved): void {
  recordDelegateChange(
    ContractKind.MIGRATION_REGISTRY_V5,
    event,
    event.params.sender,
    event.params.scope,
    event.params.delegate,
    true,
  );
}

export function handleMigrationRegistryV5Revoked(event: Revoked): void {
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
