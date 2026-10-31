// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd

import { afterEach, assert, clearStore, describe, test } from "matchstick-as";
import { Address, Bytes } from "@graphprotocol/graph-ts";
import { RegistryDelegate } from "../generated/schema";
import {
  Approved,
  Migrated,
  Revoked,
} from "../generated/MigrationRegistry/MigrationRegistry";
import { Approved as ConfigApproved } from "../generated/ConfigRegistry/ConfigRegistry";
import {
  handleMigrationRegistryApproved,
  handleMigrationRegistryMigrated,
  handleMigrationRegistryRevoked,
} from "../src/migrationregistry";
import { handleConfigRegistryApproved } from "../src/configregistry";
import {
  delegateChangeLog,
  migratedLog,
  mockRowId,
  TX_FROM,
  TX_HASH,
} from "./event-mocks.test";

const REGISTRY = "0x5a48e719785e11c4643ea4056d0861a6a69e91a0";
const CONFIG_REGISTRY = "0x2f1f82c65cce305df3950f8af8fa5ad6d9a815e8";
/** st0x `LibStoxMigrations.WRITER`. */
const WRITER = "0x0b300013cd54a8f1ac40981f80faaa18b8cc1e4c";
const OTHER_WRITER = "0x00000000000000000000000000000000000000a9";
const SAFE = "0x00000000000000000000000000000000000000d1";
const TIMELOCK = "0x00000000000000000000000000000000000000d2";
/** `keccak256("st0x.deploy")`, from `cast keccak`: `LibStoxMigrations.NAMESPACE`. */
const NAMESPACE =
  "0xd9cec8396b568ba46ea521970e5edeac9163854e75287e989c213c3e9e84bda4";
const OTHER_NAMESPACE =
  "0x00000000000000000000000000000000000000000000000000000000000000ee";
/** `MIGRATION_HEAD_GENESIS`, `keccak256("rain.migration-registry.head.genesis")`, from `cast keccak`. */
const GENESIS =
  "0xd85a7f14bb19a07649810ac09029cc9c29667e4059cb83e258bc52e213365d3f";
const MIGRATION_1 =
  "0x0000000000000000000000000000000000000000000000000000000000000001";
const MIGRATION_2 =
  "0x0000000000000000000000000000000000000000000000000000000000000002";
const MIGRATION_3 =
  "0x0000000000000000000000000000000000000000000000000000000000000003";

/** The schema's `MigrationLine.id`: registry ++ writer ++ namespace. */
function lineId(registry: string, writer: string, namespace: string): string {
  return registry.concat(writer.slice(2)).concat(namespace.slice(2));
}

/** The schema's `RegistryDelegate.id`: registry ++ account ++ scope ++ delegate. */
function delegateId(
  registry: string,
  account: string,
  scope: string,
  delegate: string,
): string {
  return registry
    .concat(account.slice(2))
    .concat(scope.slice(2))
    .concat(delegate.slice(2));
}

function migrate(
  sender: string,
  writer: string,
  namespace: string,
  migration: string,
  appliedAt: i32,
  blockNumber: i32,
  logIndex: i32,
): void {
  handleMigrationRegistryMigrated(
    changetype<Migrated>(
      migratedLog(
        Address.fromString(REGISTRY),
        Address.fromString(sender),
        Address.fromString(writer),
        Bytes.fromHexString(namespace),
        Bytes.fromHexString(migration),
        appliedAt,
        blockNumber,
        logIndex,
      ),
    ),
  );
}

function approve(
  sender: string,
  scope: string,
  delegate: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  handleMigrationRegistryApproved(
    changetype<Approved>(
      delegateChangeLog(
        Address.fromString(REGISTRY),
        Address.fromString(sender),
        Bytes.fromHexString(scope),
        Address.fromString(delegate),
        blockNumber,
        logIndex,
      ),
    ),
  );
}

function revoke(
  sender: string,
  scope: string,
  delegate: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  handleMigrationRegistryRevoked(
    changetype<Revoked>(
      delegateChangeLog(
        Address.fromString(REGISTRY),
        Address.fromString(sender),
        Bytes.fromHexString(scope),
        Address.fromString(delegate),
        blockNumber,
        logIndex,
      ),
    ),
  );
}

describe("MigrationRegistry lines", () => {
  afterEach(clearStore);

  test("a first record is applied onto genesis and becomes the head", () => {
    migrate(SAFE, WRITER, NAMESPACE, MIGRATION_1, 900, 1000, 7);

    let id = lineId(REGISTRY, WRITER, NAMESPACE);
    let row = mockRowId(7);
    assert.entityCount("MigrationLine", 1);
    assert.fieldEquals("MigrationLine", id, "registry", REGISTRY);
    assert.fieldEquals("MigrationLine", id, "writer", WRITER);
    assert.fieldEquals("MigrationLine", id, "namespace", NAMESPACE);
    assert.fieldEquals("MigrationLine", id, "head", MIGRATION_1);
    assert.fieldEquals("MigrationLine", id, "headRecord", row);
    assert.fieldEquals("MigrationLine", id, "recordCount", "1");

    assert.entityCount("MigrationRecord", 1);
    assert.fieldEquals("MigrationRecord", row, "line", id);
    assert.fieldEquals("MigrationRecord", row, "index", "0");
    assert.fieldEquals("MigrationRecord", row, "migration", MIGRATION_1);
    assert.fieldEquals("MigrationRecord", row, "appliedOnto", GENESIS);
    assert.fieldEquals("MigrationRecord", row, "appliedAt", "900");
    assert.fieldEquals("MigrationRecord", row, "sender", SAFE);
    assert.fieldEquals("MigrationRecord", row, "blockNumber", "1000");
    assert.fieldEquals("MigrationRecord", row, "blockTimestamp", "12000");
    assert.fieldEquals(
      "MigrationRecord",
      row,
      "transactionHash",
      TX_HASH.toHexString(),
    );
    assert.fieldEquals(
      "MigrationRecord",
      row,
      "transactionFrom",
      TX_FROM.toHexString(),
    );
    assert.fieldEquals("MigrationRecord", row, "logIndex", "7");

    assert.entityCount("Contract", 1);
    assert.fieldEquals("Contract", REGISTRY, "kind", "MIGRATION_REGISTRY");
    assert.fieldEquals("Contract", REGISTRY, "firstIndexedBlock", "1000");
  });

  test("each later record is applied onto the record before it", () => {
    migrate(SAFE, WRITER, NAMESPACE, MIGRATION_1, 900, 1000, 7);
    migrate(TIMELOCK, WRITER, NAMESPACE, MIGRATION_2, 1500, 1500, 2);
    migrate(SAFE, WRITER, NAMESPACE, MIGRATION_3, 1400, 1600, 0);

    let id = lineId(REGISTRY, WRITER, NAMESPACE);
    assert.entityCount("MigrationLine", 1);
    assert.fieldEquals("MigrationLine", id, "head", MIGRATION_3);
    assert.fieldEquals("MigrationLine", id, "headRecord", mockRowId(0));
    assert.fieldEquals("MigrationLine", id, "recordCount", "3");

    assert.entityCount("MigrationRecord", 3);
    assert.fieldEquals("MigrationRecord", mockRowId(7), "index", "0");
    assert.fieldEquals("MigrationRecord", mockRowId(7), "appliedOnto", GENESIS);
    assert.fieldEquals("MigrationRecord", mockRowId(2), "index", "1");
    assert.fieldEquals(
      "MigrationRecord",
      mockRowId(2),
      "appliedOnto",
      MIGRATION_1,
    );
    assert.fieldEquals("MigrationRecord", mockRowId(2), "sender", TIMELOCK);
    assert.fieldEquals("MigrationRecord", mockRowId(0), "index", "2");
    assert.fieldEquals(
      "MigrationRecord",
      mockRowId(0),
      "appliedOnto",
      MIGRATION_2,
    );
    // `appliedAt` is carried as emitted, not taken from the block.
    assert.fieldEquals("MigrationRecord", mockRowId(0), "appliedAt", "1400");
    assert.fieldEquals("Contract", REGISTRY, "firstIndexedBlock", "1000");
  });

  test("a replayed record moves neither the head nor the count", () => {
    migrate(SAFE, WRITER, NAMESPACE, MIGRATION_1, 900, 1000, 7);
    migrate(SAFE, WRITER, NAMESPACE, MIGRATION_2, 1500, 1500, 2);
    migrate(SAFE, WRITER, NAMESPACE, MIGRATION_1, 900, 1000, 7);

    let id = lineId(REGISTRY, WRITER, NAMESPACE);
    assert.fieldEquals("MigrationLine", id, "head", MIGRATION_2);
    assert.fieldEquals("MigrationLine", id, "headRecord", mockRowId(2));
    assert.fieldEquals("MigrationLine", id, "recordCount", "2");
    assert.entityCount("MigrationRecord", 2);
    assert.fieldEquals("MigrationRecord", mockRowId(7), "index", "0");
    assert.fieldEquals("MigrationRecord", mockRowId(7), "appliedOnto", GENESIS);
  });

  test("a replay of the only record leaves the line at one", () => {
    migrate(SAFE, WRITER, NAMESPACE, MIGRATION_1, 900, 1000, 7);
    migrate(SAFE, WRITER, NAMESPACE, MIGRATION_1, 900, 1000, 7);

    let id = lineId(REGISTRY, WRITER, NAMESPACE);
    assert.fieldEquals("MigrationLine", id, "recordCount", "1");
    assert.fieldEquals("MigrationRecord", mockRowId(7), "index", "0");
    assert.fieldEquals("MigrationRecord", mockRowId(7), "appliedOnto", GENESIS);
    assert.entityCount("MigrationRecord", 1);
  });

  test("another namespace or writer is its own line from genesis", () => {
    migrate(SAFE, WRITER, NAMESPACE, MIGRATION_1, 900, 1000, 0);
    migrate(SAFE, WRITER, OTHER_NAMESPACE, MIGRATION_2, 900, 1001, 1);
    migrate(OTHER_WRITER, OTHER_WRITER, NAMESPACE, MIGRATION_3, 900, 1002, 2);

    assert.entityCount("MigrationLine", 3);
    assert.fieldEquals(
      "MigrationLine",
      lineId(REGISTRY, WRITER, NAMESPACE),
      "head",
      MIGRATION_1,
    );
    assert.fieldEquals(
      "MigrationLine",
      lineId(REGISTRY, WRITER, NAMESPACE),
      "recordCount",
      "1",
    );
    assert.fieldEquals(
      "MigrationLine",
      lineId(REGISTRY, WRITER, OTHER_NAMESPACE),
      "namespace",
      OTHER_NAMESPACE,
    );
    assert.fieldEquals(
      "MigrationLine",
      lineId(REGISTRY, OTHER_WRITER, NAMESPACE),
      "writer",
      OTHER_WRITER,
    );
    assert.fieldEquals("MigrationRecord", mockRowId(1), "appliedOnto", GENESIS);
    assert.fieldEquals("MigrationRecord", mockRowId(1), "index", "0");
    assert.fieldEquals("MigrationRecord", mockRowId(2), "appliedOnto", GENESIS);
    assert.fieldEquals("MigrationRecord", mockRowId(2), "index", "0");
  });
});

describe("MigrationRegistry delegates", () => {
  afterEach(clearStore);

  test("Approved records the writer's delegate for the namespace", () => {
    approve(WRITER, NAMESPACE, SAFE, 800, 3);

    let id = delegateId(REGISTRY, WRITER, NAMESPACE, SAFE);
    assert.fieldEquals("RegistryDelegate", id, "registry", REGISTRY);
    assert.fieldEquals("RegistryDelegate", id, "account", WRITER);
    assert.fieldEquals("RegistryDelegate", id, "scope", NAMESPACE);
    assert.fieldEquals("RegistryDelegate", id, "delegate", SAFE);
    assert.fieldEquals("RegistryDelegate", id, "approved", "true");
    assert.fieldEquals("RegistryDelegate", id, "approvedAtBlock", "800");
    assert.fieldEquals("RegistryDelegate", id, "approvedAtTimestamp", "9600");
    let entity = RegistryDelegate.load(Bytes.fromHexString(id))!;
    assert.assertTrue(entity.revokedAtBlock === null);

    assert.fieldEquals(
      "RegistryDelegateChange",
      mockRowId(3),
      "registryDelegate",
      id,
    );
    assert.fieldEquals(
      "RegistryDelegateChange",
      mockRowId(3),
      "approved",
      "true",
    );
    assert.fieldEquals("Contract", REGISTRY, "kind", "MIGRATION_REGISTRY");
  });

  test("Revoked clears the approval and keeps the approve", () => {
    approve(WRITER, NAMESPACE, SAFE, 800, 3);
    revoke(WRITER, NAMESPACE, SAFE, 850, 1);

    let id = delegateId(REGISTRY, WRITER, NAMESPACE, SAFE);
    assert.fieldEquals("RegistryDelegate", id, "approved", "false");
    assert.fieldEquals("RegistryDelegate", id, "approvedAtBlock", "800");
    assert.fieldEquals("RegistryDelegate", id, "revokedAtBlock", "850");
    assert.fieldEquals("RegistryDelegate", id, "revokedAtTimestamp", "10200");
    assert.entityCount("RegistryDelegateChange", 2);
    assert.fieldEquals(
      "RegistryDelegateChange",
      mockRowId(1),
      "approved",
      "false",
    );
  });

  test("Revoked with no prior approval leaves approvedAt unset", () => {
    revoke(WRITER, NAMESPACE, TIMELOCK, 850, 1);

    let id = delegateId(REGISTRY, WRITER, NAMESPACE, TIMELOCK);
    assert.fieldEquals("RegistryDelegate", id, "approved", "false");
    let entity = RegistryDelegate.load(Bytes.fromHexString(id))!;
    assert.assertTrue(entity.approvedAtBlock === null);
    assert.fieldEquals("Contract", REGISTRY, "kind", "MIGRATION_REGISTRY");
  });

  test("the two registries hold separate approvals of the same triple", () => {
    handleConfigRegistryApproved(
      changetype<ConfigApproved>(
        delegateChangeLog(
          Address.fromString(CONFIG_REGISTRY),
          Address.fromString(WRITER),
          Bytes.fromHexString(NAMESPACE),
          Address.fromString(SAFE),
          800,
          0,
        ),
      ),
    );
    revoke(WRITER, NAMESPACE, SAFE, 801, 1);

    assert.entityCount("RegistryDelegate", 2);
    assert.fieldEquals(
      "RegistryDelegate",
      delegateId(CONFIG_REGISTRY, WRITER, NAMESPACE, SAFE),
      "approved",
      "true",
    );
    assert.fieldEquals(
      "RegistryDelegate",
      delegateId(REGISTRY, WRITER, NAMESPACE, SAFE),
      "approved",
      "false",
    );
    assert.fieldEquals("Contract", CONFIG_REGISTRY, "kind", "CONFIG_REGISTRY");
    assert.fieldEquals("Contract", REGISTRY, "kind", "MIGRATION_REGISTRY");
  });
});
