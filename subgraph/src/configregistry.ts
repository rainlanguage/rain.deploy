// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd

import { Bytes, crypto } from "@graphprotocol/graph-ts";
import {
  Approved,
  ConfigRegistryV5,
  ApprovedUnscoped,
  MetaV1_2,
  Register,
  Revoked,
  RevokedUnscoped,
} from "../generated/ConfigRegistryV5/ConfigRegistryV5";
import { ConfigBinding, ConfigRegister } from "../generated/schema";
import { ContractKind, getOrCreateContract } from "./lib/contract";
import { logRowId } from "./lib/event";
import {
  addressWord,
  recordDelegateChange,
  recordUnscopedDelegateChange,
  recordRegistryMeta,
  recordMetaSubjectBinding,
  registryMetaSubject,
} from "./lib/registry";

/** `ConfigBinding.id`: registry ++ authority ++ the `bytes32` name. */
export function configBindingId(
  registry: Bytes,
  authority: Bytes,
  name: Bytes,
): Bytes {
  return registry.concat(authority).concat(name);
}

export function configMetaSubject(authority: Bytes, name: Bytes): Bytes {
  return registryMetaSubject(addressWord(authority).concat(name));
}

export function handleConfigRegistryV5Register(event: Register): void {
  let rowId = logRowId(event);
  if (ConfigRegister.load(rowId) !== null) {
    return;
  }
  let authority = event.params.authority;
  let name = event.params.name;
  let valueTypeHash = ConfigRegistryV5.bind(event.address)
    .getV5(authority, name).value2;
  let valueType: string | null = event.params.valueType;
  if (
    !Bytes.fromByteArray(
      crypto.keccak256(Bytes.fromUTF8(event.params.valueType)),
    ).equals(valueTypeHash)
  ) {
    valueType = null;
  }
  let subject = configMetaSubject(authority, name);
  let registry = getOrCreateContract(
    event.address,
    ContractKind.CONFIG_REGISTRY_V5,
    event.block.number,
  );
  let id = configBindingId(registry.id, authority, name);
  let binding = ConfigBinding.load(id);
  if (binding === null) {
    binding = new ConfigBinding(id);
    binding.registry = registry.id;
    binding.authority = authority;
    binding.name = name;
    binding.metaSubject = subject;
    binding.registerCount = 0;
  }
  binding.value = event.params.value;
  binding.valueType = valueType;
  binding.valueTypeHash = valueTypeHash;
  binding.sender = event.params.sender;
  binding.boundAtBlock = event.block.number;
  binding.boundAtTimestamp = event.block.timestamp;
  binding.registerCount = binding.registerCount + 1;
  binding.save();

  let row = new ConfigRegister(rowId);
  row.binding = id;
  row.sender = event.params.sender;
  row.value = event.params.value;
  row.valueType = valueType;
  row.valueTypeHash = valueTypeHash;
  row.blockNumber = event.block.number;
  row.blockTimestamp = event.block.timestamp;
  row.transactionHash = event.transaction.hash;
  row.transactionFrom = event.transaction.from;
  row.logIndex = event.logIndex;
  row.save();

  recordMetaSubjectBinding(event.address, subject, id, rowId);
}

export function handleConfigRegistryV5Approved(event: Approved): void {
  recordDelegateChange(
    ContractKind.CONFIG_REGISTRY_V5,
    event,
    event.params.sender,
    event.params.scope,
    event.params.delegate,
    true,
  );
}

export function handleConfigRegistryV5Revoked(event: Revoked): void {
  recordDelegateChange(
    ContractKind.CONFIG_REGISTRY_V5,
    event,
    event.params.sender,
    event.params.scope,
    event.params.delegate,
    false,
  );
}

export function handleConfigRegistryV5MetaV1_2(event: MetaV1_2): void {
  recordRegistryMeta(
    ContractKind.CONFIG_REGISTRY_V5,
    event,
    event.params.sender,
    event.params.subject,
    event.params.meta,
  );
}

export function handleConfigRegistryV5ApprovedUnscoped(
  event: ApprovedUnscoped,
): void {
  recordUnscopedDelegateChange(
    ContractKind.CONFIG_REGISTRY_V5,
    event,
    event.params.sender,
    event.params.delegate,
    true,
  );
}

export function handleConfigRegistryV5RevokedUnscoped(
  event: RevokedUnscoped,
): void {
  recordUnscopedDelegateChange(
    ContractKind.CONFIG_REGISTRY_V5,
    event,
    event.params.sender,
    event.params.delegate,
    false,
  );
}
