// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd

import { afterEach, assert, clearStore, describe, test } from "matchstick-as";
import { Address, Bytes } from "@graphprotocol/graph-ts";
import { RegistryMeta } from "../generated/schema";
import {
  Approved,
  ApprovedUnscoped,
  MetaV1_2,
  Migrated as MigratedV5,
  Revoked,
  RevokedUnscoped,
} from "../generated/MigrationRegistryV5/MigrationRegistryV5";
import {
  handleMigrationRegistryV5Approved,
  handleMigrationRegistryV5ApprovedUnscoped,
  handleMigrationRegistryV5MetaV1_2,
  handleMigrationRegistryV5Migrated,
  handleMigrationRegistryV5Revoked,
  handleMigrationRegistryV5RevokedUnscoped,
} from "../src/migrationregistry";
import {
  delegateChangeLog,
  metaV1_2Log,
  migratedLog,
  mockRowId,
  TX_FROM,
  TX_HASH,
  unscopedDelegateChangeLog,
} from "./event-mocks.test";

const REGISTRY = "0x1a4b89828eb2dd5f3a353bd98472512f371ce408";
const WRITER = "0x0b300013cd54a8f1ac40981f80faaa18b8cc1e4c";
const SAFE = "0x00000000000000000000000000000000000000d1";
/** `keccak256("st0x.deploy")`, from `cast keccak`: `LibStoxMigrations.NAMESPACE`. */
const NAMESPACE =
  "0xd9cec8396b568ba46ea521970e5edeac9163854e75287e989c213c3e9e84bda4";
/** `MIGRATION_HEAD_GENESIS`, from `cast keccak`. */
const GENESIS =
  "0xd85a7f14bb19a07649810ac09029cc9c29667e4059cb83e258bc52e213365d3f";
const MIGRATION_1 =
  "0x0000000000000000000000000000000000000000000000000000000000000001";
const MIGRATION_2 =
  "0x0000000000000000000000000000000000000000000000000000000000000002";
/** `keccak256(abi.encode(WRITER, NAMESPACE, MIGRATION_1))`, from `cast keccak $(cast abi-encode "f(address,bytes32,bytes32)" …)`. */
const SUBJECT_1 =
  "0x0b7c43b417d2da831de8bf4c0ddf35ac27334572da1b915eb3863a9b7f65fe6a";
/** An empty rain meta document: just the `RainMetaDocumentV1` magic. */
const META = "0xff0a89c674ee7874";
/** `keccak256("st0x.deploy.v4-registries")`, from `cast keccak`. */
const MIGRATION_NAMED =
  "0xee8fc583fd5fffb64f1c51ed7277ef0ef797d2f9b2e1e639d669000d340bf6c9";
/** `keccak256(abi.encode(WRITER, NAMESPACE, MIGRATION_NAMED))`, from `cast keccak $(cast abi-encode "f(address,bytes32,bytes32)" …)`. */
const SUBJECT_NAMED =
  "0x2dc27d3c481964e1f5751e6affc732327f92c2111eb6db6bd4db577638a4f1ef";
/** From `RainMetaDocumentV1Item::cbor_encode_seq` (rain.metadata). */
const P = "0xff0a89c674ee7874";
const NAMESPACE_ITEM = "a2004b737430782e6465706c6f79011bff82e354bb91c055";
const MIGRATION_ITEM =
  "a2005819737430782e6465706c6f792e76342d72656769737472696573011bffae12bf8892cc25";
const OTHER_MIGRATION_ITEM =
  "a20051737430782e6465706c6f792e6f74686572011bffae12bf8892cc25";
/** The namespace and migration preimages under the config registry magics. */
const CONFIG_ITEMS =
  "a2004b737430782e6465706c6f79011bffcdcfae6227d5e9a2005819737430782e6465706c6f792e76342d72656769737472696573011bffcdb2cc1b1d53be";

function lineId(registry: string): string {
  return registry.concat(WRITER.slice(2)).concat(NAMESPACE.slice(2));
}

function migrate(migration: string, blockNumber: i32, logIndex: i32): void {
  handleMigrationRegistryV5Migrated(
    changetype<MigratedV5>(
      migratedLog(
        Address.fromString(REGISTRY),
        Address.fromString(SAFE),
        Address.fromString(WRITER),
        Bytes.fromHexString(NAMESPACE),
        Bytes.fromHexString(migration),
        1000,
        blockNumber,
        logIndex,
      ),
    ),
  );
}

function meta(
  subject: string,
  metaHex: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  handleMigrationRegistryV5MetaV1_2(
    changetype<MetaV1_2>(
      metaV1_2Log(
        Address.fromString(REGISTRY),
        Address.fromString(SAFE),
        Bytes.fromHexString(subject),
        Bytes.fromHexString(metaHex),
        blockNumber,
        logIndex,
      ),
    ),
  );
}

describe("MigrationRegistryV5 Migrated", () => {
  afterEach(clearStore);

  test("a first Migrated records onto genesis under the V5 registry, with its meta subject", () => {
    migrate(MIGRATION_1, 100, 2);

    let row = mockRowId(2);
    assert.fieldEquals("MigrationRecord", row, "line", lineId(REGISTRY));
    assert.fieldEquals("MigrationRecord", row, "index", "0");
    assert.fieldEquals("MigrationRecord", row, "migration", MIGRATION_1);
    assert.fieldEquals("MigrationRecord", row, "appliedOnto", GENESIS);
    assert.fieldEquals("MigrationRecord", row, "appliedAt", "1000");
    assert.fieldEquals("MigrationRecord", row, "sender", SAFE);
    assert.fieldEquals("MigrationRecord", row, "metaSubject", SUBJECT_1);
    assert.fieldEquals("MigrationLine", lineId(REGISTRY), "head", MIGRATION_1);
    assert.fieldEquals("MigrationLine", lineId(REGISTRY), "recordCount", "1");
    assert.fieldEquals("Contract", REGISTRY, "kind", "MIGRATION_REGISTRY_V5");
  });

  test("a second Migrated chains onto the first and a replay counts once", () => {
    migrate(MIGRATION_1, 100, 2);
    migrate(MIGRATION_2, 101, 0);
    migrate(MIGRATION_2, 101, 0);

    assert.fieldEquals("MigrationRecord", mockRowId(0), "index", "1");
    assert.fieldEquals(
      "MigrationRecord",
      mockRowId(0),
      "appliedOnto",
      MIGRATION_1,
    );
    assert.fieldEquals("MigrationLine", lineId(REGISTRY), "head", MIGRATION_2);
    assert.fieldEquals("MigrationLine", lineId(REGISTRY), "recordCount", "2");
    assert.entityCount("MigrationRecord", 2);
  });
});

describe("MigrationRegistryV5 MetaV1_2", () => {
  afterEach(clearStore);

  test("a write's meta links to its record, raw", () => {
    migrate(MIGRATION_1, 100, 2);
    meta(SUBJECT_1, META, 100, 3);

    let row = mockRowId(3);
    assert.entityCount("RegistryMeta", 1);
    assert.fieldEquals("RegistryMeta", row, "registry", REGISTRY);
    assert.fieldEquals("RegistryMeta", row, "sender", SAFE);
    assert.fieldEquals("RegistryMeta", row, "subject", SUBJECT_1);
    assert.fieldEquals("RegistryMeta", row, "meta", META);
    assert.fieldEquals("RegistryMeta", row, "migrationRecord", mockRowId(2));
    assert.fieldEquals("RegistryMeta", row, "verified", "false");
    assert.fieldEquals("RegistryMeta", row, "blockNumber", "100");
    assert.fieldEquals(
      "RegistryMeta",
      row,
      "transactionHash",
      TX_HASH.toHexString(),
    );
    assert.fieldEquals(
      "RegistryMeta",
      row,
      "transactionFrom",
      TX_FROM.toHexString(),
    );
    assert.fieldEquals("RegistryMeta", row, "logIndex", "3");
    let entity = RegistryMeta.load(Bytes.fromHexString(row))!;
    assert.assertTrue(entity.configBinding === null);
    assert.assertTrue(entity.configRegister === null);
  });

  test("a meta whose subject no record has is kept, unlinked", () => {
    migrate(MIGRATION_1, 100, 2);
    meta(MIGRATION_2, META, 100, 3);

    let entity = RegistryMeta.load(Bytes.fromHexString(mockRowId(3)))!;
    assert.assertTrue(entity.migrationRecord === null);
    assert.fieldEquals("RegistryMeta", mockRowId(3), "meta", META);
  });

  test("a meta seen before any record names its registry a V5 migration registry", () => {
    meta(SUBJECT_1, META, 100, 3);

    assert.fieldEquals("Contract", REGISTRY, "kind", "MIGRATION_REGISTRY_V5");
  });

  test("a replayed meta writes one row", () => {
    migrate(MIGRATION_1, 100, 2);
    meta(SUBJECT_1, META, 100, 3);
    meta(SUBJECT_1, META, 100, 3);

    assert.entityCount("RegistryMeta", 1);
  });
});

describe("MigrationRegistryV5 delegates", () => {
  afterEach(clearStore);

  test("Approved then Revoked move an approval under the V5 registry", () => {
    handleMigrationRegistryV5Approved(
      changetype<Approved>(
        delegateChangeLog(
          Address.fromString(REGISTRY),
          Address.fromString(WRITER),
          Bytes.fromHexString(NAMESPACE),
          Address.fromString(SAFE),
          300,
          4,
        ),
      ),
    );
    let id = REGISTRY.concat(WRITER.slice(2))
      .concat(NAMESPACE.slice(2))
      .concat(SAFE.slice(2));
    assert.fieldEquals("RegistryDelegate", id, "approved", "true");
    assert.fieldEquals("Contract", REGISTRY, "kind", "MIGRATION_REGISTRY_V5");

    handleMigrationRegistryV5Revoked(
      changetype<Revoked>(
        delegateChangeLog(
          Address.fromString(REGISTRY),
          Address.fromString(WRITER),
          Bytes.fromHexString(NAMESPACE),
          Address.fromString(SAFE),
          400,
          2,
        ),
      ),
    );
    assert.fieldEquals("RegistryDelegate", id, "approved", "false");
    assert.fieldEquals("RegistryDelegate", id, "revokedAtBlock", "400");
    assert.entityCount("RegistryDelegateChange", 2);
  });
});

function approveUnscoped(blockNumber: i32, logIndex: i32): void {
  handleMigrationRegistryV5ApprovedUnscoped(
    changetype<ApprovedUnscoped>(
      unscopedDelegateChangeLog(
        Address.fromString(REGISTRY),
        Address.fromString(WRITER),
        Address.fromString(SAFE),
        blockNumber,
        logIndex,
      ),
    ),
  );
}

function revokeUnscoped(blockNumber: i32, logIndex: i32): void {
  handleMigrationRegistryV5RevokedUnscoped(
    changetype<RevokedUnscoped>(
      unscopedDelegateChangeLog(
        Address.fromString(REGISTRY),
        Address.fromString(WRITER),
        Address.fromString(SAFE),
        blockNumber,
        logIndex,
      ),
    ),
  );
}

const UNSCOPED_ID = REGISTRY.concat(WRITER.slice(2)).concat(SAFE.slice(2));

describe("MigrationRegistryV5 unscoped delegates", () => {
  afterEach(clearStore);

  test("ApprovedUnscoped then RevokedUnscoped move an unscoped approval", () => {
    approveUnscoped(300, 4);
    assert.fieldEquals(
      "RegistryUnscopedDelegate",
      UNSCOPED_ID,
      "approved",
      "true",
    );
    assert.fieldEquals(
      "RegistryUnscopedDelegate",
      UNSCOPED_ID,
      "account",
      WRITER,
    );
    assert.fieldEquals(
      "RegistryUnscopedDelegate",
      UNSCOPED_ID,
      "delegate",
      SAFE,
    );
    assert.fieldEquals(
      "RegistryUnscopedDelegate",
      UNSCOPED_ID,
      "approvedAtBlock",
      "300",
    );
    assert.fieldEquals("Contract", REGISTRY, "kind", "MIGRATION_REGISTRY_V5");

    revokeUnscoped(400, 2);
    assert.fieldEquals(
      "RegistryUnscopedDelegate",
      UNSCOPED_ID,
      "approved",
      "false",
    );
    assert.fieldEquals(
      "RegistryUnscopedDelegate",
      UNSCOPED_ID,
      "revokedAtBlock",
      "400",
    );
    assert.fieldEquals(
      "RegistryUnscopedDelegate",
      UNSCOPED_ID,
      "approvedAtBlock",
      "300",
    );
    assert.entityCount("RegistryUnscopedDelegateChange", 2);
    assert.fieldEquals(
      "RegistryUnscopedDelegateChange",
      mockRowId(2),
      "approved",
      "false",
    );
    assert.fieldEquals(
      "RegistryUnscopedDelegateChange",
      mockRowId(2),
      "registryUnscopedDelegate",
      UNSCOPED_ID,
    );
    assert.entityCount("RegistryDelegate", 0);
  });

  test("a replayed ApprovedUnscoped after a RevokedUnscoped leaves the revoke standing", () => {
    approveUnscoped(300, 4);
    revokeUnscoped(400, 2);
    approveUnscoped(300, 4);
    assert.fieldEquals(
      "RegistryUnscopedDelegate",
      UNSCOPED_ID,
      "approved",
      "false",
    );
    assert.entityCount("RegistryUnscopedDelegateChange", 2);
  });

  test("RevokedUnscoped leaves a scoped approval of the same delegate standing", () => {
    handleMigrationRegistryV5Approved(
      changetype<Approved>(
        delegateChangeLog(
          Address.fromString(REGISTRY),
          Address.fromString(WRITER),
          Bytes.fromHexString(NAMESPACE),
          Address.fromString(SAFE),
          300,
          1,
        ),
      ),
    );
    approveUnscoped(300, 2);
    revokeUnscoped(400, 3);
    let scoped = REGISTRY.concat(WRITER.slice(2))
      .concat(NAMESPACE.slice(2))
      .concat(SAFE.slice(2));
    assert.fieldEquals("RegistryDelegate", scoped, "approved", "true");
    assert.fieldEquals(
      "RegistryUnscopedDelegate",
      UNSCOPED_ID,
      "approved",
      "false",
    );
    assert.entityCount("RegistryDelegateChange", 1);
    assert.entityCount("RegistryUnscopedDelegateChange", 2);
  });
});

const VERIFIED = "true|st0x.deploy|st0x.deploy.v4-registries";
const UNVERIFIED = "false|null|null";
function verifiedFor(metaHex: string): string {
  migrate(MIGRATION_NAMED, 100, 2);
  meta(SUBJECT_NAMED, metaHex, 100, 3);
  let row = RegistryMeta.load(Bytes.fromHexString(mockRowId(3)))!;
  let namespace = row.namespaceString;
  let migration = row.migrationString;
  return (row.verified ? "true|" : "false|")
    .concat(namespace === null ? "null" : namespace!)
    .concat("|")
    .concat(migration === null ? "null" : migration!);
}

describe("MigrationRegistryV5 MetaV1_2 verification", () => {
  afterEach(clearStore);

  test("namespace and migration preimages that hash to the record verify", () => {
    assert.stringEquals(
      verifiedFor(P.concat(NAMESPACE_ITEM).concat(MIGRATION_ITEM)),
      VERIFIED,
    );
  });

  test("a migration preimage that hashes elsewhere does not verify", () => {
    assert.stringEquals(
      verifiedFor(P.concat(NAMESPACE_ITEM).concat(OTHER_MIGRATION_ITEM)),
      UNVERIFIED,
    );
  });

  test("a missing namespace or migration item does not verify", () => {
    assert.stringEquals(verifiedFor(P.concat(MIGRATION_ITEM)), UNVERIFIED);
    clearStore();
    assert.stringEquals(verifiedFor(P.concat(NAMESPACE_ITEM)), UNVERIFIED);
  });

  test("a meta for a record its line has moved past verifies against that record", () => {
    migrate(MIGRATION_NAMED, 100, 2);
    migrate(MIGRATION_2, 101, 4);
    meta(
      SUBJECT_NAMED,
      P.concat(NAMESPACE_ITEM).concat(MIGRATION_ITEM),
      101,
      5,
    );

    assert.fieldEquals("MigrationLine", lineId(REGISTRY), "head", MIGRATION_2);
    assert.fieldEquals("RegistryMeta", mockRowId(5), "verified", "true");
  });

  test("config registry items do not verify a migration", () => {
    assert.stringEquals(verifiedFor(P.concat(CONFIG_ITEMS)), UNVERIFIED);
  });

  test("malformed meta does not verify", () => {
    let ok = P.concat(NAMESPACE_ITEM).concat(MIGRATION_ITEM);
    assert.stringEquals(verifiedFor(ok.slice(0, ok.length - 2)), UNVERIFIED);
    clearStore();
    assert.stringEquals(verifiedFor(META), UNVERIFIED);
  });

  test("meta whose subject names no record does not verify", () => {
    meta(
      SUBJECT_NAMED,
      P.concat(NAMESPACE_ITEM).concat(MIGRATION_ITEM),
      100,
      3,
    );
    assert.fieldEquals("RegistryMeta", mockRowId(3), "verified", "false");
  });
});
