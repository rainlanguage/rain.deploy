import { afterEach, assert, clearStore, describe, test } from "matchstick-as";
import { Address, Bytes } from "@graphprotocol/graph-ts";
import { RegistryDelegate } from "../generated/schema";
import {
  Approved,
  Register,
  Revoked,
} from "../generated/ConfigRegistry/ConfigRegistry";
import {
  handleConfigRegistryApproved,
  handleConfigRegistryRegister,
  handleConfigRegistryRevoked,
} from "../src/configregistry";
import {
  delegateChangeLog,
  mockRowId,
  registerLog,
  TX_FROM,
  TX_HASH,
} from "./event-mocks.test";

const REGISTRY = "0x2f1f82c65cce305df3950f8af8fa5ad6d9a815e8";
const OTHER_REGISTRY = "0x0000000000000000000000000000000000000c02";
/** st0x `LibStoxMigrations.WRITER`, the root authority. */
const AUTHORITY = "0x0b300013cd54a8f1ac40981f80faaa18b8cc1e4c";
const OTHER_AUTHORITY = "0x00000000000000000000000000000000000000a9";
const DELEGATE = "0x00000000000000000000000000000000000000d1";
const OTHER_DELEGATE = "0x00000000000000000000000000000000000000d2";
/** `keccak256("st0x.rbac.us.v1")`, from `cast keccak`. */
const US_NAME =
  "0xb046f6b844b680f0dcfc7a139f126e7e13d58023f8d26c15e3229eb4fff8499f";
/** `keccak256("st0x.rbac.eu.v1")`, from `cast keccak`. */
const EU_NAME =
  "0x560e679773d4bf1a3dee3d913c31185111a3bcc57b6d93366936fc3526985ad5";
const VALUE_A =
  "0x0000000000000000000000000000000000000000000000000000000000000a01";
const VALUE_B = "0xbb02";

/** The schema's `ConfigBinding.id`: registry ++ authority ++ name, as hex. */
function bindingId(registry: string, authority: string, name: string): string {
  return registry.concat(authority.slice(2)).concat(name.slice(2));
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

function register(
  registry: string,
  sender: string,
  authority: string,
  name: string,
  value: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  handleConfigRegistryRegister(
    changetype<Register>(
      registerLog(
        Address.fromString(registry),
        Address.fromString(sender),
        Address.fromString(authority),
        Bytes.fromHexString(name),
        Bytes.fromHexString(value),
        blockNumber,
        logIndex,
      ),
    ),
  );
}

function approve(
  registry: string,
  sender: string,
  scope: string,
  delegate: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  handleConfigRegistryApproved(
    changetype<Approved>(
      delegateChangeLog(
        Address.fromString(registry),
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
  registry: string,
  sender: string,
  scope: string,
  delegate: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  handleConfigRegistryRevoked(
    changetype<Revoked>(
      delegateChangeLog(
        Address.fromString(registry),
        Address.fromString(sender),
        Bytes.fromHexString(scope),
        Address.fromString(delegate),
        blockNumber,
        logIndex,
      ),
    ),
  );
}

describe("ConfigRegistry bindings", () => {
  afterEach(clearStore);

  test("a first Register binds the name at its value", () => {
    register(REGISTRY, AUTHORITY, AUTHORITY, US_NAME, VALUE_A, 100, 3);

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    assert.entityCount("ConfigBinding", 1);
    assert.fieldEquals("ConfigBinding", id, "registry", REGISTRY);
    assert.fieldEquals("ConfigBinding", id, "authority", AUTHORITY);
    assert.fieldEquals("ConfigBinding", id, "name", US_NAME);
    assert.fieldEquals("ConfigBinding", id, "value", VALUE_A);
    assert.fieldEquals("ConfigBinding", id, "sender", AUTHORITY);
    assert.fieldEquals("ConfigBinding", id, "boundAtBlock", "100");
    assert.fieldEquals("ConfigBinding", id, "boundAtTimestamp", "1200");
    assert.fieldEquals("ConfigBinding", id, "registerCount", "1");

    assert.entityCount("ConfigRegister", 1);
    let row = mockRowId(3);
    assert.fieldEquals("ConfigRegister", row, "binding", id);
    assert.fieldEquals("ConfigRegister", row, "sender", AUTHORITY);
    assert.fieldEquals("ConfigRegister", row, "value", VALUE_A);
    assert.fieldEquals("ConfigRegister", row, "blockNumber", "100");
    assert.fieldEquals("ConfigRegister", row, "blockTimestamp", "1200");
    assert.fieldEquals(
      "ConfigRegister",
      row,
      "transactionHash",
      TX_HASH.toHexString(),
    );
    assert.fieldEquals(
      "ConfigRegister",
      row,
      "transactionFrom",
      TX_FROM.toHexString(),
    );
    assert.fieldEquals("ConfigRegister", row, "logIndex", "3");

    assert.entityCount("Contract", 1);
    assert.fieldEquals("Contract", REGISTRY, "kind", "CONFIG_REGISTRY");
    assert.fieldEquals("Contract", REGISTRY, "firstIndexedBlock", "100");
  });

  test("a delegate's first Register binds under the authority, not the delegate", () => {
    register(REGISTRY, DELEGATE, AUTHORITY, US_NAME, VALUE_A, 100, 3);

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    assert.entityCount("ConfigBinding", 1);
    assert.fieldEquals("ConfigBinding", id, "authority", AUTHORITY);
    assert.fieldEquals("ConfigBinding", id, "sender", DELEGATE);
  });

  test("a rebind moves value, sender and age, and keeps the first row", () => {
    register(REGISTRY, AUTHORITY, AUTHORITY, US_NAME, VALUE_A, 100, 3);
    register(REGISTRY, DELEGATE, AUTHORITY, US_NAME, VALUE_B, 250, 1);

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    assert.entityCount("ConfigBinding", 1);
    assert.fieldEquals("ConfigBinding", id, "value", VALUE_B);
    assert.fieldEquals("ConfigBinding", id, "sender", DELEGATE);
    assert.fieldEquals("ConfigBinding", id, "boundAtBlock", "250");
    assert.fieldEquals("ConfigBinding", id, "boundAtTimestamp", "3000");
    assert.fieldEquals("ConfigBinding", id, "registerCount", "2");
    // The authority is the one bound under, not the caller.
    assert.fieldEquals("ConfigBinding", id, "authority", AUTHORITY);

    assert.entityCount("ConfigRegister", 2);
    assert.fieldEquals("ConfigRegister", mockRowId(3), "value", VALUE_A);
    assert.fieldEquals("ConfigRegister", mockRowId(3), "sender", AUTHORITY);
    assert.fieldEquals("ConfigRegister", mockRowId(1), "value", VALUE_B);
    assert.fieldEquals("ConfigRegister", mockRowId(1), "sender", DELEGATE);
    // The registry row keeps the block it was first seen at.
    assert.fieldEquals("Contract", REGISTRY, "firstIndexedBlock", "100");
  });

  test("a replayed Register neither counts again nor rolls the value back", () => {
    register(REGISTRY, AUTHORITY, AUTHORITY, US_NAME, VALUE_A, 100, 3);
    register(REGISTRY, AUTHORITY, AUTHORITY, US_NAME, VALUE_B, 250, 1);
    register(REGISTRY, AUTHORITY, AUTHORITY, US_NAME, VALUE_A, 100, 3);

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    assert.fieldEquals("ConfigBinding", id, "value", VALUE_B);
    assert.fieldEquals("ConfigBinding", id, "boundAtBlock", "250");
    assert.fieldEquals("ConfigBinding", id, "registerCount", "2");
    assert.entityCount("ConfigRegister", 2);
  });

  test("a replay of the only Register leaves the count at one", () => {
    register(REGISTRY, AUTHORITY, AUTHORITY, US_NAME, VALUE_A, 100, 3);
    register(REGISTRY, AUTHORITY, AUTHORITY, US_NAME, VALUE_A, 100, 3);

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    assert.fieldEquals("ConfigBinding", id, "registerCount", "1");
    assert.entityCount("ConfigRegister", 1);
  });

  test("names, authorities and registries each key their own binding", () => {
    register(REGISTRY, AUTHORITY, AUTHORITY, US_NAME, VALUE_A, 100, 0);
    register(REGISTRY, AUTHORITY, AUTHORITY, EU_NAME, VALUE_B, 101, 1);
    register(
      REGISTRY,
      OTHER_AUTHORITY,
      OTHER_AUTHORITY,
      US_NAME,
      VALUE_B,
      102,
      2,
    );
    register(OTHER_REGISTRY, AUTHORITY, AUTHORITY, US_NAME, VALUE_B, 103, 3);

    assert.entityCount("ConfigBinding", 4);
    assert.fieldEquals(
      "ConfigBinding",
      bindingId(REGISTRY, AUTHORITY, US_NAME),
      "value",
      VALUE_A,
    );
    assert.fieldEquals(
      "ConfigBinding",
      bindingId(REGISTRY, AUTHORITY, US_NAME),
      "registerCount",
      "1",
    );
    assert.fieldEquals(
      "ConfigBinding",
      bindingId(REGISTRY, AUTHORITY, EU_NAME),
      "name",
      EU_NAME,
    );
    assert.fieldEquals(
      "ConfigBinding",
      bindingId(REGISTRY, OTHER_AUTHORITY, US_NAME),
      "authority",
      OTHER_AUTHORITY,
    );
    assert.fieldEquals(
      "ConfigBinding",
      bindingId(OTHER_REGISTRY, AUTHORITY, US_NAME),
      "registry",
      OTHER_REGISTRY,
    );
    assert.entityCount("Contract", 2);
  });
});

describe("ConfigRegistry delegates", () => {
  afterEach(clearStore);

  test("Approved records a standing approval and its log", () => {
    approve(REGISTRY, AUTHORITY, US_NAME, DELEGATE, 300, 4);

    let id = delegateId(REGISTRY, AUTHORITY, US_NAME, DELEGATE);
    assert.entityCount("RegistryDelegate", 1);
    assert.fieldEquals("RegistryDelegate", id, "registry", REGISTRY);
    assert.fieldEquals("RegistryDelegate", id, "account", AUTHORITY);
    assert.fieldEquals("RegistryDelegate", id, "scope", US_NAME);
    assert.fieldEquals("RegistryDelegate", id, "delegate", DELEGATE);
    assert.fieldEquals("RegistryDelegate", id, "approved", "true");
    assert.fieldEquals("RegistryDelegate", id, "approvedAtBlock", "300");
    assert.fieldEquals("RegistryDelegate", id, "approvedAtTimestamp", "3600");
    let entity = RegistryDelegate.load(Bytes.fromHexString(id))!;
    assert.assertTrue(entity.revokedAtBlock === null);
    assert.assertTrue(entity.revokedAtTimestamp === null);

    assert.entityCount("RegistryDelegateChange", 1);
    let row = mockRowId(4);
    assert.fieldEquals("RegistryDelegateChange", row, "registryDelegate", id);
    assert.fieldEquals("RegistryDelegateChange", row, "approved", "true");
    assert.fieldEquals("RegistryDelegateChange", row, "blockNumber", "300");
    assert.fieldEquals("RegistryDelegateChange", row, "blockTimestamp", "3600");
    assert.fieldEquals(
      "RegistryDelegateChange",
      row,
      "transactionHash",
      TX_HASH.toHexString(),
    );
    assert.fieldEquals(
      "RegistryDelegateChange",
      row,
      "transactionFrom",
      TX_FROM.toHexString(),
    );
    assert.fieldEquals("RegistryDelegateChange", row, "logIndex", "4");

    assert.fieldEquals("Contract", REGISTRY, "kind", "CONFIG_REGISTRY");
  });

  test("Revoked after Approved clears the approval and keeps both logs", () => {
    approve(REGISTRY, AUTHORITY, US_NAME, DELEGATE, 300, 4);
    revoke(REGISTRY, AUTHORITY, US_NAME, DELEGATE, 400, 2);

    let id = delegateId(REGISTRY, AUTHORITY, US_NAME, DELEGATE);
    assert.entityCount("RegistryDelegate", 1);
    assert.fieldEquals("RegistryDelegate", id, "approved", "false");
    assert.fieldEquals("RegistryDelegate", id, "approvedAtBlock", "300");
    assert.fieldEquals("RegistryDelegate", id, "revokedAtBlock", "400");
    assert.fieldEquals("RegistryDelegate", id, "revokedAtTimestamp", "4800");

    assert.entityCount("RegistryDelegateChange", 2);
    assert.fieldEquals(
      "RegistryDelegateChange",
      mockRowId(4),
      "approved",
      "true",
    );
    assert.fieldEquals(
      "RegistryDelegateChange",
      mockRowId(2),
      "approved",
      "false",
    );
    assert.fieldEquals(
      "RegistryDelegateChange",
      mockRowId(2),
      "registryDelegate",
      id,
    );
  });

  test("Revoked with no prior approval records a never-approved row", () => {
    revoke(REGISTRY, AUTHORITY, US_NAME, DELEGATE, 400, 2);

    let id = delegateId(REGISTRY, AUTHORITY, US_NAME, DELEGATE);
    assert.fieldEquals("RegistryDelegate", id, "approved", "false");
    assert.fieldEquals("RegistryDelegate", id, "revokedAtBlock", "400");
    let entity = RegistryDelegate.load(Bytes.fromHexString(id))!;
    assert.assertTrue(entity.approvedAtBlock === null);
    assert.assertTrue(entity.approvedAtTimestamp === null);
    assert.fieldEquals("Contract", REGISTRY, "kind", "CONFIG_REGISTRY");
  });

  test("Approved after Revoked stands again and keeps the revoke", () => {
    approve(REGISTRY, AUTHORITY, US_NAME, DELEGATE, 300, 4);
    revoke(REGISTRY, AUTHORITY, US_NAME, DELEGATE, 400, 2);
    approve(REGISTRY, AUTHORITY, US_NAME, DELEGATE, 500, 6);

    let id = delegateId(REGISTRY, AUTHORITY, US_NAME, DELEGATE);
    assert.fieldEquals("RegistryDelegate", id, "approved", "true");
    assert.fieldEquals("RegistryDelegate", id, "approvedAtBlock", "500");
    assert.fieldEquals("RegistryDelegate", id, "approvedAtTimestamp", "6000");
    assert.fieldEquals("RegistryDelegate", id, "revokedAtBlock", "400");
    assert.entityCount("RegistryDelegateChange", 3);
  });

  test("a replayed Approved after a Revoked leaves the revoke standing", () => {
    approve(REGISTRY, AUTHORITY, US_NAME, DELEGATE, 300, 4);
    revoke(REGISTRY, AUTHORITY, US_NAME, DELEGATE, 400, 2);
    approve(REGISTRY, AUTHORITY, US_NAME, DELEGATE, 300, 4);

    let id = delegateId(REGISTRY, AUTHORITY, US_NAME, DELEGATE);
    assert.fieldEquals("RegistryDelegate", id, "approved", "false");
    assert.fieldEquals("RegistryDelegate", id, "approvedAtBlock", "300");
    assert.entityCount("RegistryDelegateChange", 2);
  });

  test("scopes and delegates each key their own approval", () => {
    approve(REGISTRY, AUTHORITY, US_NAME, DELEGATE, 300, 0);
    approve(REGISTRY, AUTHORITY, EU_NAME, DELEGATE, 300, 1);
    approve(REGISTRY, AUTHORITY, US_NAME, OTHER_DELEGATE, 300, 2);
    revoke(REGISTRY, AUTHORITY, US_NAME, OTHER_DELEGATE, 301, 3);

    assert.entityCount("RegistryDelegate", 3);
    assert.fieldEquals(
      "RegistryDelegate",
      delegateId(REGISTRY, AUTHORITY, US_NAME, DELEGATE),
      "approved",
      "true",
    );
    assert.fieldEquals(
      "RegistryDelegate",
      delegateId(REGISTRY, AUTHORITY, EU_NAME, DELEGATE),
      "approved",
      "true",
    );
    assert.fieldEquals(
      "RegistryDelegate",
      delegateId(REGISTRY, AUTHORITY, US_NAME, OTHER_DELEGATE),
      "approved",
      "false",
    );
  });
});
