// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd

import { Bytes, crypto, ethereum } from "@graphprotocol/graph-ts";
import {
  ConfigBinding,
  ConfigRegister,
  MigrationLine,
  MigrationRecord,
  RegistryDelegate,
  RegistryDelegateChange,
  RegistryMeta,
  RegistryMetaSubject,
  RegistryUnscopedDelegate,
  RegistryUnscopedDelegateChange,
} from "../../generated/schema";
import { getOrCreateContract } from "./contract";
import { logRowId } from "./event";
import {
  CONFIG_REGISTRY_NAME_V1,
  CONFIG_REGISTRY_VALUE_TYPE_V1,
  MIGRATION_REGISTRY_MIGRATION_V1,
  MIGRATION_REGISTRY_NAMESPACE_V1,
  PreimageCheck,
  verifyPreimages,
} from "./rainmeta";

/** `RegistryDelegate.id`: registry ++ account ++ the `bytes32` scope ++ delegate. */
export function registryDelegateId(
  registry: Bytes,
  account: Bytes,
  scope: Bytes,
  delegate: Bytes,
): Bytes {
  return registry.concat(account).concat(scope).concat(delegate);
}

/**
 * Record one `IRegistryDelegatesV1` `Approved` (`approved` true) or `Revoked`
 * (false). Both registries emit either log whatever the prior state, so the log
 * sets `approved` rather than toggling it. A replay of a log already recorded
 * returns before touching the approval, so an older log cannot roll it back.
 */
export function recordDelegateChange(
  kind: string,
  event: ethereum.Event,
  account: Bytes,
  scope: Bytes,
  delegate: Bytes,
  approved: boolean,
): void {
  let rowId = logRowId(event);
  if (RegistryDelegateChange.load(rowId) !== null) {
    return;
  }
  let registry = getOrCreateContract(event.address, kind, event.block.number);
  let id = registryDelegateId(registry.id, account, scope, delegate);
  let entity = RegistryDelegate.load(id);
  if (entity === null) {
    entity = new RegistryDelegate(id);
    entity.registry = registry.id;
    entity.account = account;
    entity.scope = scope;
    entity.delegate = delegate;
  }
  entity.approved = approved;
  if (approved) {
    entity.approvedAtBlock = event.block.number;
    entity.approvedAtTimestamp = event.block.timestamp;
  } else {
    entity.revokedAtBlock = event.block.number;
    entity.revokedAtTimestamp = event.block.timestamp;
  }
  entity.save();

  let row = new RegistryDelegateChange(rowId);
  row.registryDelegate = id;
  row.approved = approved;
  row.blockNumber = event.block.number;
  row.blockTimestamp = event.block.timestamp;
  row.transactionHash = event.transaction.hash;
  row.transactionFrom = event.transaction.from;
  row.logIndex = event.logIndex;
  row.save();
}

/** `RegistryUnscopedDelegate.id`: registry ++ account ++ delegate. */
export function registryUnscopedDelegateId(
  registry: Bytes,
  account: Bytes,
  delegate: Bytes,
): Bytes {
  return registry.concat(account).concat(delegate);
}

/**
 * Record one `IRegistryDelegatesV3` `ApprovedUnscoped` (`approved` true) or
 * `RevokedUnscoped` (false). Either log is emitted whatever the prior state, so
 * the log sets `approved`, and a replay returns before touching it, as
 * `recordDelegateChange` does for the scoped logs.
 */
export function recordUnscopedDelegateChange(
  kind: string,
  event: ethereum.Event,
  account: Bytes,
  delegate: Bytes,
  approved: boolean,
): void {
  let rowId = logRowId(event);
  if (RegistryUnscopedDelegateChange.load(rowId) !== null) {
    return;
  }
  let registry = getOrCreateContract(event.address, kind, event.block.number);
  let id = registryUnscopedDelegateId(registry.id, account, delegate);
  let entity = RegistryUnscopedDelegate.load(id);
  if (entity === null) {
    entity = new RegistryUnscopedDelegate(id);
    entity.registry = registry.id;
    entity.account = account;
    entity.delegate = delegate;
  }
  entity.approved = approved;
  if (approved) {
    entity.approvedAtBlock = event.block.number;
    entity.approvedAtTimestamp = event.block.timestamp;
  } else {
    entity.revokedAtBlock = event.block.number;
    entity.revokedAtTimestamp = event.block.timestamp;
  }
  entity.save();

  let row = new RegistryUnscopedDelegateChange(rowId);
  row.registryUnscopedDelegate = id;
  row.approved = approved;
  row.blockNumber = event.block.number;
  row.blockTimestamp = event.block.timestamp;
  row.transactionHash = event.transaction.hash;
  row.transactionFrom = event.transaction.from;
  row.logIndex = event.logIndex;
  row.save();
}

/** `keccak256` of an `abi.encode` of static words: a V5 `MetaV1_2` subject. */
export function registryMetaSubject(encoded: Bytes): Bytes {
  return Bytes.fromByteArray(crypto.keccak256(encoded));
}

/** One `abi.encode` word for an address: left-padded to 32 bytes. */
export function addressWord(account: Bytes): Bytes {
  return Bytes.fromUint8Array(new Uint8Array(12)).concat(account);
}

/** `RegistryMetaSubject.id`: registry ++ subject. */
function metaSubjectId(registry: Bytes, subject: Bytes): Bytes {
  return registry.concat(subject);
}

/**
 * Point a V5 config registry's subject at the binding and the `Register` that
 * most recently wrote it. The registry emits a write's `MetaV1_2` after its
 * `Register` in the same call, so the subject always resolves by then.
 */
export function recordMetaSubjectBinding(
  registry: Bytes,
  subject: Bytes,
  binding: Bytes,
  register: Bytes,
): void {
  let id = metaSubjectId(registry, subject);
  let entity = RegistryMetaSubject.load(id);
  if (entity === null) {
    entity = new RegistryMetaSubject(id);
  }
  entity.configBinding = binding;
  entity.configRegister = register;
  entity.save();
}

/** Point a V5 migration registry's subject at the record it names. */
export function recordMetaSubjectRecord(
  registry: Bytes,
  subject: Bytes,
  record: Bytes,
): void {
  let entity = new RegistryMetaSubject(metaSubjectId(registry, subject));
  entity.migrationRecord = record;
  entity.save();
}

/**
 * Record one `MetaV1_2` log from a V5 registry, linked to whatever its subject
 * names. A config subject is shared by every bind of the name, so the meta
 * links to the binding's latest `Register` only when that `Register` is in the
 * same transaction: a name is bound at most once per block.
 */
export function recordRegistryMeta(
  kind: string,
  event: ethereum.Event,
  sender: Bytes,
  subject: Bytes,
  meta: Bytes,
): void {
  let rowId = logRowId(event);
  if (RegistryMeta.load(rowId) !== null) {
    return;
  }
  let registry = getOrCreateContract(event.address, kind, event.block.number);
  let row = new RegistryMeta(rowId);
  row.registry = registry.id;
  row.sender = sender;
  row.subject = subject;
  row.meta = meta;
  let link = RegistryMetaSubject.load(metaSubjectId(registry.id, subject));
  if (link !== null) {
    row.configBinding = link.configBinding;
    row.migrationRecord = link.migrationRecord;
    let registerId = link.configRegister;
    if (registerId !== null) {
      let register = ConfigRegister.load(registerId);
      if (
        register !== null &&
        register.transactionHash.equals(event.transaction.hash)
      ) {
        row.configRegister = registerId;
      }
    }
  }
  verifyMeta(row);
  row.blockNumber = event.block.number;
  row.blockTimestamp = event.block.timestamp;
  row.transactionHash = event.transaction.hash;
  row.transactionFrom = event.transaction.from;
  row.logIndex = event.logIndex;
  row.save();
}

/** The key preimage checks for the write `row` is linked to, if any. */
function preimageChecks(row: RegistryMeta): PreimageCheck[] | null {
  let registerId = row.configRegister;
  if (registerId !== null) {
    let register = ConfigRegister.load(registerId)!;
    let binding = ConfigBinding.load(register.binding)!;
    let valueTypeHash = register.valueTypeHash;
    if (valueTypeHash === null) {
      return null;
    }
    return [
      new PreimageCheck(CONFIG_REGISTRY_NAME_V1, binding.name),
      new PreimageCheck(CONFIG_REGISTRY_VALUE_TYPE_V1, valueTypeHash),
    ];
  }
  let recordId = row.migrationRecord;
  if (recordId !== null) {
    let record = MigrationRecord.load(recordId)!;
    let line = MigrationLine.load(record.line)!;
    return [
      new PreimageCheck(MIGRATION_REGISTRY_NAMESPACE_V1, line.namespace),
      new PreimageCheck(MIGRATION_REGISTRY_MIGRATION_V1, record.migration),
    ];
  }
  return null;
}

function verifyMeta(row: RegistryMeta): void {
  let checks = preimageChecks(row);
  let preimages: Bytes[] | null = null;
  if (checks !== null) {
    preimages = verifyPreimages(row.meta, checks);
  }
  row.verified = preimages !== null;
  if (preimages === null) {
    return;
  }
  if (row.configRegister !== null) {
    row.nameString = preimages[0].toString();
  } else {
    row.namespaceString = preimages[0].toString();
    row.migrationString = preimages[1].toString();
  }
}
