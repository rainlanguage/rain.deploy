// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd

import { newMockEvent } from "matchstick-as";
import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";

export const TX_HASH: Bytes = Bytes.fromHexString(
  "0xdeadbeef00000000000000000000000000000000000000000000000000000001",
);

export const TX_FROM: Address = Address.fromString(
  "0x00000000000000000000000000000000000000ff",
);

// Block and log index are explicit: rows key on tx hash ++ log index, so defaults would collapse distinct logs.
function mockLog(
  contract: Address,
  blockNumber: i32,
  logIndex: i32,
  params: Array<ethereum.EventParam>,
): ethereum.Event {
  let event = newMockEvent();
  event.address = contract;
  event.logIndex = BigInt.fromI32(logIndex);
  event.block.number = BigInt.fromI32(blockNumber);
  event.block.timestamp = BigInt.fromI32(blockNumber * 12);
  event.transaction.hash = TX_HASH;
  event.transaction.from = TX_FROM;
  event.parameters = params;
  return event;
}

/** `IConfigRegistryV5` `Register(address,address,bytes32,string,bytes)`. */
export function registerV5Log(
  registry: Address,
  sender: Address,
  authority: Address,
  name: Bytes,
  valueType: string,
  value: Bytes,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(registry, blockNumber, logIndex, [
    new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)),
    new ethereum.EventParam("authority", ethereum.Value.fromAddress(authority)),
    new ethereum.EventParam("name", ethereum.Value.fromFixedBytes(name)),
    new ethereum.EventParam("valueType", ethereum.Value.fromString(valueType)),
    new ethereum.EventParam("value", ethereum.Value.fromBytes(value)),
  ]);
}

/** `IMetaV1_2` `MetaV1_2(address,bytes32,bytes)`. */
export function metaV1_2Log(
  registry: Address,
  sender: Address,
  subject: Bytes,
  meta: Bytes,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(registry, blockNumber, logIndex, [
    new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)),
    new ethereum.EventParam("subject", ethereum.Value.fromFixedBytes(subject)),
    new ethereum.EventParam("meta", ethereum.Value.fromBytes(meta)),
  ]);
}

/** `event`, moved into the transaction `hash`. */
export function inTx(event: ethereum.Event, hash: Bytes): ethereum.Event {
  event.transaction.hash = hash;
  return event;
}

/** `Approved(address,bytes32,address)` or `Revoked(address,bytes32,address)`. */
export function delegateChangeLog(
  registry: Address,
  sender: Address,
  scope: Bytes,
  delegate: Address,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(registry, blockNumber, logIndex, [
    new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)),
    new ethereum.EventParam("scope", ethereum.Value.fromFixedBytes(scope)),
    new ethereum.EventParam("delegate", ethereum.Value.fromAddress(delegate)),
  ]);
}

/** `ApprovedUnscoped(address,address)` or `RevokedUnscoped(address,address)`. */
export function unscopedDelegateChangeLog(
  registry: Address,
  sender: Address,
  delegate: Address,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(registry, blockNumber, logIndex, [
    new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)),
    new ethereum.EventParam("delegate", ethereum.Value.fromAddress(delegate)),
  ]);
}

/** `Migrated(address,address,bytes32,bytes32,uint256)`. */
export function migratedLog(
  registry: Address,
  sender: Address,
  writer: Address,
  namespace: Bytes,
  migration: Bytes,
  appliedAt: i32,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(registry, blockNumber, logIndex, [
    new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)),
    new ethereum.EventParam("writer", ethereum.Value.fromAddress(writer)),
    new ethereum.EventParam(
      "namespace",
      ethereum.Value.fromFixedBytes(namespace),
    ),
    new ethereum.EventParam(
      "migration",
      ethereum.Value.fromFixedBytes(migration),
    ),
    new ethereum.EventParam(
      "appliedAt",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(appliedAt)),
    ),
  ]);
}

// Spelled out (TX_HASH ++ little-endian i32 log index) rather than via `concatI32`, so a row keyed any other way fails; log indices stay below 256.
export function mockRowId(logIndex: i32): string {
  let low = logIndex.toString(16);
  if (low.length < 2) {
    low = "0".concat(low);
  }
  return TX_HASH.toHexString().concat(low).concat("000000");
}
