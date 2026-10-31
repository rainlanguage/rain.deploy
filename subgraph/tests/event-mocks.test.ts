// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd

import { newMockEvent } from "matchstick-as";
import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";

/**
 * Shared mock-log builders. Every builder takes the emitting contract, the
 * event's own params, a block number and a log index, and returns a bare
 * `ethereum.Event` for the caller to `changetype` into the generated class its
 * handler expects — `graph codegen` emits a separate class per (data source,
 * ABI) pair, so there is no one type these could return.
 *
 * Block number and log index are always explicit because the recorders stamp
 * every history row with the block and key it on transaction hash ++ log index:
 * two logs left on matchstick's defaults would collapse onto the same row and
 * hide exactly the bugs these tests are for.
 */

/** The transaction every mock log here is emitted from. */
export const TX_HASH: Bytes = Bytes.fromHexString(
  "0xdeadbeef00000000000000000000000000000000000000000000000000000001",
);

/** The EOA that submitted that transaction — `RoleGrant.transactionFrom`. */
export const TX_FROM: Address = Address.fromString(
  "0x00000000000000000000000000000000000000ff",
);

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

/**
 * `RoleGranted(bytes32,address,address)` or `RoleRevoked(bytes32,address,address)`
 * — the two carry the same three params, and which one it is is decided by the
 * handler the caller hands it to.
 */
export function roleChangeLog(
  contract: Address,
  role: Bytes,
  account: Address,
  sender: Address,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(contract, blockNumber, logIndex, [
    new ethereum.EventParam("role", ethereum.Value.fromFixedBytes(role)),
    new ethereum.EventParam("account", ethereum.Value.fromAddress(account)),
    new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)),
  ]);
}

/** `RoleAdminChanged(bytes32,bytes32,bytes32)`. */
export function roleAdminChangedLog(
  contract: Address,
  role: Bytes,
  previousAdminRole: Bytes,
  newAdminRole: Bytes,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(contract, blockNumber, logIndex, [
    new ethereum.EventParam("role", ethereum.Value.fromFixedBytes(role)),
    new ethereum.EventParam(
      "previousAdminRole",
      ethereum.Value.fromFixedBytes(previousAdminRole),
    ),
    new ethereum.EventParam(
      "newAdminRole",
      ethereum.Value.fromFixedBytes(newAdminRole),
    ),
  ]);
}

/** `OwnershipTransferred(address,address)`. */
export function ownershipTransferredLog(
  contract: Address,
  previousOwner: Address,
  newOwner: Address,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(contract, blockNumber, logIndex, [
    new ethereum.EventParam(
      "previousOwner",
      ethereum.Value.fromAddress(previousOwner),
    ),
    new ethereum.EventParam("newOwner", ethereum.Value.fromAddress(newOwner)),
  ]);
}

/** `Upgraded(address)`, as emitted by an `UpgradeableBeacon`. */
export function upgradedLog(
  contract: Address,
  implementation: Address,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(contract, blockNumber, logIndex, [
    new ethereum.EventParam(
      "implementation",
      ethereum.Value.fromAddress(implementation),
    ),
  ]);
}

/** `Deployment(address,address,address)` from the receipt vault deployer. */
export function receiptVaultDeploymentLog(
  deployer: Address,
  sender: Address,
  offchainAssetReceiptVault: Address,
  receipt: Address,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(deployer, blockNumber, logIndex, [
    new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)),
    new ethereum.EventParam(
      "offchainAssetReceiptVault",
      ethereum.Value.fromAddress(offchainAssetReceiptVault),
    ),
    new ethereum.EventParam("receipt", ethereum.Value.fromAddress(receipt)),
  ]);
}

/** `Deployment(address,address,address)` from the orchestrator deployer. */
export function orchestratorDeploymentLog(
  deployer: Address,
  sender: Address,
  orchestrator: Address,
  owner: Address,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(deployer, blockNumber, logIndex, [
    new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)),
    new ethereum.EventParam(
      "orchestrator",
      ethereum.Value.fromAddress(orchestrator),
    ),
    new ethereum.EventParam("owner", ethereum.Value.fromAddress(owner)),
  ]);
}

/**
 * `CallScheduled(bytes32,uint256,address,uint256,bytes,bytes32,uint256)` from
 * the governance timelock. `scheduleBatch` emits one per call, all with the same
 * `id` and an `index` counting up from zero.
 */
export function callScheduledLog(
  timelock: Address,
  id: Bytes,
  index: i32,
  target: Address,
  value: i32,
  data: Bytes,
  predecessor: Bytes,
  delay: i32,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(timelock, blockNumber, logIndex, [
    new ethereum.EventParam("id", ethereum.Value.fromFixedBytes(id)),
    new ethereum.EventParam(
      "index",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(index)),
    ),
    new ethereum.EventParam("target", ethereum.Value.fromAddress(target)),
    new ethereum.EventParam(
      "value",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(value)),
    ),
    new ethereum.EventParam("data", ethereum.Value.fromBytes(data)),
    new ethereum.EventParam(
      "predecessor",
      ethereum.Value.fromFixedBytes(predecessor),
    ),
    new ethereum.EventParam(
      "delay",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(delay)),
    ),
  ]);
}

/** `CallExecuted(bytes32,uint256,address,uint256,bytes)`, one per call executed. */
export function callExecutedLog(
  timelock: Address,
  id: Bytes,
  index: i32,
  target: Address,
  value: i32,
  data: Bytes,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(timelock, blockNumber, logIndex, [
    new ethereum.EventParam("id", ethereum.Value.fromFixedBytes(id)),
    new ethereum.EventParam(
      "index",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(index)),
    ),
    new ethereum.EventParam("target", ethereum.Value.fromAddress(target)),
    new ethereum.EventParam(
      "value",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(value)),
    ),
    new ethereum.EventParam("data", ethereum.Value.fromBytes(data)),
  ]);
}

/** `CallSalt(bytes32,bytes32)`, emitted once per scheduling with a non-zero salt. */
export function callSaltLog(
  timelock: Address,
  id: Bytes,
  salt: Bytes,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(timelock, blockNumber, logIndex, [
    new ethereum.EventParam("id", ethereum.Value.fromFixedBytes(id)),
    new ethereum.EventParam("salt", ethereum.Value.fromFixedBytes(salt)),
  ]);
}

/** `Cancelled(bytes32)`. */
export function cancelledLog(
  timelock: Address,
  id: Bytes,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(timelock, blockNumber, logIndex, [
    new ethereum.EventParam("id", ethereum.Value.fromFixedBytes(id)),
  ]);
}

/** `SafeSetup(address,address[],uint256,address,address)`. */
export function safeSetupLog(
  safe: Address,
  owners: Array<Address>,
  threshold: i32,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  let zero = Address.zero();
  return mockLog(safe, blockNumber, logIndex, [
    new ethereum.EventParam("initiator", ethereum.Value.fromAddress(zero)),
    new ethereum.EventParam("owners", ethereum.Value.fromAddressArray(owners)),
    new ethereum.EventParam(
      "threshold",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(threshold)),
    ),
    new ethereum.EventParam("initializer", ethereum.Value.fromAddress(zero)),
    new ethereum.EventParam(
      "fallbackHandler",
      ethereum.Value.fromAddress(zero),
    ),
  ]);
}

/** `ChangedThreshold(uint256)`. */
export function changedThresholdLog(
  safe: Address,
  threshold: i32,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(safe, blockNumber, logIndex, [
    new ethereum.EventParam(
      "threshold",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(threshold)),
    ),
  ]);
}

/** `AddedOwner(address)` or `RemovedOwner(address)`: one `owner` param each. */
export function ownerChangeLog(
  safe: Address,
  owner: Address,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(safe, blockNumber, logIndex, [
    new ethereum.EventParam("owner", ethereum.Value.fromAddress(owner)),
  ]);
}

/** `ConfigRegistry` `Register(address,address,bytes32,bytes)`. */
export function registerLog(
  registry: Address,
  sender: Address,
  authority: Address,
  name: Bytes,
  value: Bytes,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(registry, blockNumber, logIndex, [
    new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)),
    new ethereum.EventParam("authority", ethereum.Value.fromAddress(authority)),
    new ethereum.EventParam("name", ethereum.Value.fromFixedBytes(name)),
    new ethereum.EventParam("value", ethereum.Value.fromBytes(value)),
  ]);
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
/**
 * `IRegistryDelegatesV1` `Approved(address,bytes32,address)` or
 * `Revoked(address,bytes32,address)`: the same three params, and which one it
 * is is decided by the handler the caller hands it to.
 */
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

/**
 * `IRegistryDelegatesV3` `ApprovedUnscoped(address,address)` or
 * `RevokedUnscoped(address,address)`: the same two params.
 */
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

/** `MigrationRegistry` `Migrated(address,address,bytes32,bytes32,uint256)`. */
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

/** `ICloneableFactoryV5` `NewBeaconProxy(address,address,address,bytes32,bytes)`. */
export function newBeaconProxyLog(
  factory: Address,
  sender: Address,
  beacon: Address,
  proxy: Address,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(factory, blockNumber, logIndex, [
    new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)),
    new ethereum.EventParam("beacon", ethereum.Value.fromAddress(beacon)),
    new ethereum.EventParam("proxy", ethereum.Value.fromAddress(proxy)),
    new ethereum.EventParam(
      "salt",
      ethereum.Value.fromFixedBytes(Bytes.fromUint8Array(new Uint8Array(32))),
    ),
    new ethereum.EventParam("data", ethereum.Value.fromBytes(Bytes.empty())),
  ]);
}

/**
 * `ICloneableFactoryV6`
 * `NewRegistryBeaconProxy(address,address,address,bytes32,address,address,bytes32,bytes)`.
 */
export function newRegistryBeaconProxyLog(
  factory: Address,
  sender: Address,
  beacon: Address,
  proxy: Address,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return mockLog(factory, blockNumber, logIndex, [
    new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender)),
    new ethereum.EventParam(
      "registry",
      ethereum.Value.fromAddress(
        Address.fromString("0x2F1f82c65cce305Df3950F8aF8Fa5aD6D9a815e8"),
      ),
    ),
    new ethereum.EventParam(
      "authority",
      ethereum.Value.fromAddress(
        Address.fromString("0x0b300013CD54a8F1aC40981f80FaaA18b8Cc1E4c"),
      ),
    ),
    new ethereum.EventParam(
      "beaconName",
      ethereum.Value.fromFixedBytes(Bytes.fromUint8Array(new Uint8Array(32))),
    ),
    new ethereum.EventParam("beacon", ethereum.Value.fromAddress(beacon)),
    new ethereum.EventParam("proxy", ethereum.Value.fromAddress(proxy)),
    new ethereum.EventParam(
      "salt",
      ethereum.Value.fromFixedBytes(Bytes.fromUint8Array(new Uint8Array(32))),
    ),
    new ethereum.EventParam("data", ethereum.Value.fromBytes(Bytes.empty())),
  ]);
}

/**
 * The id of the history row a mock log here writes: `TX_HASH` then the log
 * index as four little-endian bytes, which is `ByteArray.fromI32`'s order.
 * Spelled out rather than built with `concatI32`, so a row keyed any other way
 * fails to match. Log indices here stay below 256.
 */
export function mockRowId(logIndex: i32): string {
  let low = logIndex.toString(16);
  if (low.length < 2) {
    low = "0".concat(low);
  }
  return TX_HASH.toHexString().concat(low).concat("000000");
}
