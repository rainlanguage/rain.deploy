// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd

import {
  afterEach,
  assert,
  clearStore,
  createMockedFunction,
  describe,
  test,
} from "matchstick-as";
import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  ConfigBinding,
  ConfigRegister,
  RegistryMeta,
} from "../generated/schema";
import {
  Approved,
  ApprovedUnscoped,
  MetaV1_2,
  Register,
  Revoked,
  RevokedUnscoped,
} from "../generated/ConfigRegistryV5/ConfigRegistryV5";
import {
  handleConfigRegistryV5Approved,
  handleConfigRegistryV5ApprovedUnscoped,
  handleConfigRegistryV5MetaV1_2,
  handleConfigRegistryV5Register,
  handleConfigRegistryV5Revoked,
  handleConfigRegistryV5RevokedUnscoped,
} from "../src/configregistry";
import {
  delegateChangeLog,
  inTx,
  metaV1_2Log,
  mockRowId,
  registerV5Log,
  TX_FROM,
  TX_HASH,
  unscopedDelegateChangeLog,
} from "./event-mocks.test";

const REGISTRY = "0xdc3909127e51dcb3ab7d43eee585dd351f77c285";
const OTHER_REGISTRY = "0x00000000000000000000000000000000000000e5";
/** st0x `LibStoxConfig.ROOT_AUTHORITY`. */
const AUTHORITY = "0x0b300013cd54a8f1ac40981f80faaa18b8cc1e4c";
const DELEGATE = "0x00000000000000000000000000000000000000d1";
/** `keccak256("st0x.rbac.us.v1")`, from `cast keccak`. */
const US_NAME =
  "0xb046f6b844b680f0dcfc7a139f126e7e13d58023f8d26c15e3229eb4fff8499f";
/** `keccak256("st0x.rbac.eu.v1")`, from `cast keccak`. */
const EU_NAME =
  "0x560e679773d4bf1a3dee3d913c31185111a3bcc57b6d93366936fc3526985ad5";
/** `keccak256(abi.encode(AUTHORITY, US_NAME))`, from `cast keccak $(cast abi-encode "f(address,bytes32)" …)`. */
const US_SUBJECT =
  "0x912e9df27c27e1655d672dbb02f4a3b59883479b9595a4522ca493312e2cdd89";
/** `keccak256("address")`, from `cast keccak`. */
const ADDRESS_HASH =
  "0x421683f821a0574472445355be6d2b769119e8515f8376a1d7878523dfdecf7b";
/** `keccak256("(address,uint256)")`, from `cast keccak`. */
const TUPLE_HASH =
  "0x4c8216942579564ee54f26005a991364c7f94438571b448bf6d3278d139e0fdf";
/** `keccak256("uint256")`, from `cast keccak`. */
const UINT256_HASH =
  "0xec13d6d12b88433319b64e1065a96ea19cd330ef6603f5f6fb685dde3959a320";
/** `keccak256("address\0")`, from `cast keccak 0x6164647265737300`; graph-node decodes that type as "address". */
const ADDRESS_NUL_HASH =
  "0x10d5143a6a8e25b3b61a3d97a427cd32e5ae62c0df92e99ec1c3f99a6cf2a693";
const VALUE_A =
  "0x0000000000000000000000000000000000000000000000000000000000000a01";
const VALUE_B =
  "0x0000000000000000000000000000000000000000000000000000000000000b02000000000000000000000000000000000000000000000000000000000000000c";
/** An empty rain meta document: just the `RainMetaDocumentV1` magic. */
const META = "0xff0a89c674ee7874";
/*
 * Rain meta documents from `RainMetaDocumentV1Item::cbor_encode_seq` (rain.metadata),
 * items: config name, value type, unless named otherwise.
 */
const P = "0xff0a89c674ee7874";
const NAME_US = "a2004f737430782e726261632e75732e7631011bffcdcfae6227d5e9";
const NAME_EU = "a2004f737430782e726261632e65752e7631011bffcdcfae6227d5e9";
const TYPE_ADDRESS = "a2004761646472657373011bffcdb2cc1b1d53be";
const TYPE_UINT256 = "a2004775696e74323536011bffcdb2cc1b1d53be";
const TYPE_ADDRESS_NUL = "a200486164647265737300011bffcdb2cc1b1d53be";
const META_OK = P.concat(NAME_US).concat(TYPE_ADDRESS);
/** A rainlang source item, the type, then the name with `identity` encoding. */
const META_FOREIGN = P.concat("a200455f3a20313b011bff13109e41336ff2")
  .concat(TYPE_ADDRESS)
  .concat(
    "a3004f737430782e726261632e75732e7631011bffcdcfae6227d5e903686964656e74697479",
  );
/** The name deflated. */
const META_DEFLATE = P.concat(
  "a30057789c2b2e31a8d02b4a4a4cd62b2dd62b3304002ba10541011bffcdcfae6227d5e903676465666c617465",
).concat(TYPE_ADDRESS);
/**
 * Hand-built, accepted by `cbor_decode`: an indefinite foreign item map with a
 * tag, an indefinite byte string, a half float and a nested map.
 */
const META_EXOTIC = P.concat(
  "bf004161011bff13109e41336ff2059fc11a000000015f4161426263fff93c00a10180ffff",
)
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
/** Hand-built, each rejected by `cbor_decode`. */
const FOREIGN_KEY_5 = "a3004161011bff13109e41336ff205";
const META_RESERVED_INFO = P.concat(FOREIGN_KEY_5)
  .concat("1c")
  .concat("00".repeat(16))
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_TEXT_KEY = P.concat("a261304161011bff13109e41336ff2")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_DUPLICATE_KEY = P.concat("a3004161004162011bff13109e41336ff2")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_NO_MAGIC = P.concat("a1004161").concat(NAME_US).concat(TYPE_ADDRESS);
const META_NO_PAYLOAD = P.concat("a10100").concat(NAME_US).concat(TYPE_ADDRESS);
const META_TRAILING_BREAK = META_OK.concat("ff");
const META_TOO_DEEP = P.concat("a3004161011bff13109e41336ff205")
  .concat("81".repeat(200))
  .concat("00")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_INDEFINITE_INT = P.concat(FOREIGN_KEY_5)
  .concat("1f")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_MIXED_CHUNK = P.concat(FOREIGN_KEY_5)
  .concat("5f6141ff")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_INDEFINITE_TAG = P.concat(FOREIGN_KEY_5)
  .concat("df")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_LONE_BREAK = P.concat(FOREIGN_KEY_5)
  .concat("ff")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_EMPTY_TEXT_KEY = P.concat("a2604161011bff13109e41336ff2")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_NEGATIVE_MAGIC = P.concat("a20041610120")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
const META_TRUNCATED_ITEM = META_OK.concat("a2004161");
/** 2^63 map entries are 2^64 items, zero in u64. */
const META_MAP_COUNT_2_POW_63 = P.concat(FOREIGN_KEY_5)
  .concat("bb8000000000000000")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
/** Accepted by `cbor_decode`: a foreign item holding a definite map. */
const META_NESTED_MAP = P.concat(FOREIGN_KEY_5)
  .concat("a10102")
  .concat(NAME_US)
  .concat(TYPE_ADDRESS);
/** The name raw but declared `deflate`. */
const META_RAW_DECLARED_DEFLATE = P.concat(
  "a3004f737430782e726261632e75732e7631011bffcdcfae6227d5e903676465666c617465",
).concat(TYPE_ADDRESS);
const OTHER_TX =
  "0xdeadbeef00000000000000000000000000000000000000000000000000000002";

function bindingId(registry: string, authority: string, name: string): string {
  return registry.concat(authority.slice(2)).concat(name.slice(2));
}

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

/** `mockRowId` for a log in `tx` rather than `TX_HASH`. */
function rowIdIn(tx: string, logIndex: i32): string {
  let low = logIndex.toString(16);
  if (low.length < 2) {
    low = "0".concat(low);
  }
  return tx.concat(low).concat("000000");
}

// The hash the registry stores and `getV5` returns: keccak256 of the type's raw bytes.
function storedTypeHash(valueType: string): string {
  if (valueType == "address") return ADDRESS_HASH;
  if (valueType == "(address,uint256)") return TUPLE_HASH;
  assert.stringEquals(valueType, "uint256");
  return UINT256_HASH;
}

function registerStoring(
  tx: string,
  sender: string,
  name: string,
  valueType: string,
  typeHash: string,
  value: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  createMockedFunction(
    Address.fromString(REGISTRY),
    "getV5",
    "getV5(address,bytes32):(bytes,uint256,bytes32)",
  )
    .withArgs([
      ethereum.Value.fromAddress(Address.fromString(AUTHORITY)),
      ethereum.Value.fromFixedBytes(Bytes.fromHexString(name)),
    ])
    .returns([
      ethereum.Value.fromBytes(Bytes.fromHexString(value)),
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(blockNumber * 12)),
      ethereum.Value.fromFixedBytes(Bytes.fromHexString(typeHash)),
    ]);
  handleConfigRegistryV5Register(
    changetype<Register>(
      inTx(
        registerV5Log(
          Address.fromString(REGISTRY),
          Address.fromString(sender),
          Address.fromString(AUTHORITY),
          Bytes.fromHexString(name),
          valueType,
          Bytes.fromHexString(value),
          blockNumber,
          logIndex,
        ),
        Bytes.fromHexString(tx),
      ),
    ),
  );
}

function registerIn(
  tx: string,
  sender: string,
  name: string,
  valueType: string,
  value: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  registerStoring(
    tx,
    sender,
    name,
    valueType,
    storedTypeHash(valueType),
    value,
    blockNumber,
    logIndex,
  );
}

function register(
  sender: string,
  name: string,
  valueType: string,
  value: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  registerIn(
    TX_HASH.toHexString(),
    sender,
    name,
    valueType,
    value,
    blockNumber,
    logIndex,
  );
}

function metaEvent(
  subject: string,
  metaHex: string,
  blockNumber: i32,
  logIndex: i32,
): ethereum.Event {
  return metaV1_2Log(
    Address.fromString(REGISTRY),
    Address.fromString(DELEGATE),
    Bytes.fromHexString(subject),
    Bytes.fromHexString(metaHex),
    blockNumber,
    logIndex,
  );
}

function meta(
  subject: string,
  metaHex: string,
  blockNumber: i32,
  logIndex: i32,
): void {
  handleConfigRegistryV5MetaV1_2(
    changetype<MetaV1_2>(metaEvent(subject, metaHex, blockNumber, logIndex)),
  );
}

describe("ConfigRegistryV5 Register", () => {
  afterEach(clearStore);

  test("a first Register binds the value, its type and its type hash", () => {
    register(DELEGATE, US_NAME, "address", VALUE_A, 100, 3);

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    assert.entityCount("ConfigBinding", 1);
    assert.fieldEquals("ConfigBinding", id, "registry", REGISTRY);
    assert.fieldEquals("ConfigBinding", id, "authority", AUTHORITY);
    assert.fieldEquals("ConfigBinding", id, "name", US_NAME);
    assert.fieldEquals("ConfigBinding", id, "value", VALUE_A);
    assert.fieldEquals("ConfigBinding", id, "valueType", "address");
    assert.fieldEquals("ConfigBinding", id, "valueTypeHash", ADDRESS_HASH);
    assert.fieldEquals("ConfigBinding", id, "sender", DELEGATE);
    assert.fieldEquals("ConfigBinding", id, "boundAtBlock", "100");
    assert.fieldEquals("ConfigBinding", id, "boundAtTimestamp", "1200");
    assert.fieldEquals("ConfigBinding", id, "registerCount", "1");
    assert.fieldEquals("ConfigBinding", id, "metaSubject", US_SUBJECT);

    let row = mockRowId(3);
    assert.entityCount("ConfigRegister", 1);
    assert.fieldEquals("ConfigRegister", row, "binding", id);
    assert.fieldEquals("ConfigRegister", row, "sender", DELEGATE);
    assert.fieldEquals("ConfigRegister", row, "value", VALUE_A);
    assert.fieldEquals("ConfigRegister", row, "valueType", "address");
    assert.fieldEquals("ConfigRegister", row, "valueTypeHash", ADDRESS_HASH);
    assert.fieldEquals("ConfigRegister", row, "blockNumber", "100");
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

    assert.fieldEquals("Contract", REGISTRY, "kind", "CONFIG_REGISTRY_V5");
    assert.fieldEquals("Contract", REGISTRY, "firstIndexedBlock", "100");
  });

  test("a tuple type that hashes to the stored type hash is kept", () => {
    register(AUTHORITY, US_NAME, "(address,uint256)", VALUE_B, 100, 3);

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    assert.fieldEquals("ConfigBinding", id, "valueType", "(address,uint256)");
    assert.fieldEquals("ConfigBinding", id, "valueTypeHash", TUPLE_HASH);
    assert.fieldEquals(
      "ConfigRegister",
      mockRowId(3),
      "valueType",
      "(address,uint256)",
    );
    assert.fieldEquals(
      "ConfigRegister",
      mockRowId(3),
      "valueTypeHash",
      TUPLE_HASH,
    );
  });

  test("the type hash is the one getV5 returns, not keccak256 of the decoded type", () => {
    registerStoring(
      TX_HASH.toHexString(),
      AUTHORITY,
      US_NAME,
      "address",
      ADDRESS_NUL_HASH,
      VALUE_A,
      100,
      3,
    );

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    assert.fieldEquals("ConfigBinding", id, "valueTypeHash", ADDRESS_NUL_HASH);
    assert.fieldEquals(
      "ConfigRegister",
      mockRowId(3),
      "valueTypeHash",
      ADDRESS_NUL_HASH,
    );
  });

  test("a decoded type that does not hash to the stored type hash is null", () => {
    registerStoring(
      TX_HASH.toHexString(),
      AUTHORITY,
      US_NAME,
      "address",
      ADDRESS_NUL_HASH,
      VALUE_A,
      100,
      3,
    );

    let binding = ConfigBinding.load(
      Bytes.fromHexString(bindingId(REGISTRY, AUTHORITY, US_NAME)),
    )!;
    assert.assertNull<string | null>(binding.valueType);
    let row = ConfigRegister.load(Bytes.fromHexString(mockRowId(3)))!;
    assert.assertNull<string | null>(row.valueType);
    assert.bytesEquals(row.value, Bytes.fromHexString(VALUE_A));
  });

  test("a rebind whose decoded type misses the stored hash clears the binding's type", () => {
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    registerStoring(
      OTHER_TX,
      AUTHORITY,
      US_NAME,
      "address",
      ADDRESS_NUL_HASH,
      VALUE_B,
      250,
      1,
    );

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    let binding = ConfigBinding.load(Bytes.fromHexString(id))!;
    assert.assertNull<string | null>(binding.valueType);
    assert.fieldEquals("ConfigBinding", id, "valueTypeHash", ADDRESS_NUL_HASH);
    assert.fieldEquals("ConfigBinding", id, "value", VALUE_B);
    assert.fieldEquals("ConfigRegister", mockRowId(3), "valueType", "address");
    assert.fieldEquals(
      "ConfigRegister",
      mockRowId(3),
      "valueTypeHash",
      ADDRESS_HASH,
    );
    let rebind = ConfigRegister.load(Bytes.fromHexString(rowIdIn(OTHER_TX, 1)))!;
    assert.assertNull<string | null>(rebind.valueType);
  });

  test("a rebind as another type moves the type and keeps each row's own", () => {
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    register(DELEGATE, US_NAME, "(address,uint256)", VALUE_B, 250, 1);

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    assert.entityCount("ConfigBinding", 1);
    assert.fieldEquals("ConfigBinding", id, "value", VALUE_B);
    assert.fieldEquals("ConfigBinding", id, "valueType", "(address,uint256)");
    assert.fieldEquals("ConfigBinding", id, "valueTypeHash", TUPLE_HASH);
    assert.fieldEquals("ConfigBinding", id, "sender", DELEGATE);
    assert.fieldEquals("ConfigBinding", id, "boundAtBlock", "250");
    assert.fieldEquals("ConfigBinding", id, "registerCount", "2");

    assert.entityCount("ConfigRegister", 2);
    assert.fieldEquals("ConfigRegister", mockRowId(3), "valueType", "address");
    assert.fieldEquals(
      "ConfigRegister",
      mockRowId(3),
      "valueTypeHash",
      ADDRESS_HASH,
    );
    assert.fieldEquals(
      "ConfigRegister",
      mockRowId(1),
      "valueType",
      "(address,uint256)",
    );
    assert.fieldEquals(
      "ConfigRegister",
      mockRowId(1),
      "valueTypeHash",
      TUPLE_HASH,
    );
  });

  test("a replayed Register neither counts again nor rolls the type back", () => {
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    register(AUTHORITY, US_NAME, "(address,uint256)", VALUE_B, 250, 1);
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);

    let id = bindingId(REGISTRY, AUTHORITY, US_NAME);
    assert.fieldEquals("ConfigBinding", id, "valueType", "(address,uint256)");
    assert.fieldEquals("ConfigBinding", id, "valueTypeHash", TUPLE_HASH);
    assert.fieldEquals("ConfigBinding", id, "registerCount", "2");
    assert.entityCount("ConfigRegister", 2);
  });
});

describe("ConfigRegistryV5 MetaV1_2", () => {
  afterEach(clearStore);

  test("a bind's meta links to its binding and its Register, raw", () => {
    register(DELEGATE, US_NAME, "address", VALUE_A, 100, 3);
    meta(US_SUBJECT, META, 100, 4);

    let row = mockRowId(4);
    assert.entityCount("RegistryMeta", 1);
    assert.fieldEquals("RegistryMeta", row, "registry", REGISTRY);
    assert.fieldEquals("RegistryMeta", row, "sender", DELEGATE);
    assert.fieldEquals("RegistryMeta", row, "subject", US_SUBJECT);
    assert.fieldEquals("RegistryMeta", row, "meta", META);
    assert.fieldEquals(
      "RegistryMeta",
      row,
      "configBinding",
      bindingId(REGISTRY, AUTHORITY, US_NAME),
    );
    assert.fieldEquals("RegistryMeta", row, "configRegister", mockRowId(3));
    assert.fieldEquals("RegistryMeta", row, "verified", "false");
    assert.fieldEquals("RegistryMeta", row, "blockNumber", "100");
    assert.fieldEquals("RegistryMeta", row, "blockTimestamp", "1200");
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
    assert.fieldEquals("RegistryMeta", row, "logIndex", "4");
    let entity = RegistryMeta.load(Bytes.fromHexString(row))!;
    assert.assertTrue(entity.migrationRecord === null);
  });

  test("a rebind's meta links to the rebind's Register, not the first", () => {
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    meta(US_SUBJECT, META, 100, 4);
    registerIn(OTHER_TX, AUTHORITY, US_NAME, "(address,uint256)", VALUE_B, 250, 1);
    handleConfigRegistryV5MetaV1_2(
      changetype<MetaV1_2>(
        inTx(
          metaEvent(US_SUBJECT, META, 250, 2),
          Bytes.fromHexString(OTHER_TX),
        ),
      ),
    );

    let second = rowIdIn(OTHER_TX, 2);
    assert.entityCount("RegistryMeta", 2);
    assert.fieldEquals(
      "RegistryMeta",
      second,
      "configRegister",
      rowIdIn(OTHER_TX, 1),
    );
    assert.fieldEquals(
      "RegistryMeta",
      mockRowId(4),
      "configRegister",
      mockRowId(3),
    );
    assert.fieldEquals(
      "RegistryMeta",
      second,
      "configBinding",
      bindingId(REGISTRY, AUTHORITY, US_NAME),
    );
  });

  test("a meta outside its binding's latest Register transaction links the binding only", () => {
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    handleConfigRegistryV5MetaV1_2(
      changetype<MetaV1_2>(
        inTx(
          metaEvent(US_SUBJECT, META, 300, 0),
          Bytes.fromHexString(OTHER_TX),
        ),
      ),
    );

    let row = rowIdIn(OTHER_TX, 0);
    assert.fieldEquals(
      "RegistryMeta",
      row,
      "configBinding",
      bindingId(REGISTRY, AUTHORITY, US_NAME),
    );
    let entity = RegistryMeta.load(Bytes.fromHexString(row))!;
    assert.assertTrue(entity.configRegister === null);
  });

  test("a meta whose subject no Register has is kept, unlinked", () => {
    meta(EU_NAME, META, 100, 4);

    let entity = RegistryMeta.load(Bytes.fromHexString(mockRowId(4)))!;
    assert.assertTrue(entity.configBinding === null);
    assert.assertTrue(entity.configRegister === null);
    assert.assertTrue(entity.migrationRecord === null);
    assert.fieldEquals("RegistryMeta", mockRowId(4), "meta", META);
    assert.fieldEquals("Contract", REGISTRY, "kind", "CONFIG_REGISTRY_V5");
  });

  test("a replayed meta writes one row", () => {
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    meta(US_SUBJECT, META, 100, 4);
    meta(US_SUBJECT, META, 100, 4);

    assert.entityCount("RegistryMeta", 1);
  });

  test("a replayed meta keeps the Register it was first linked to", () => {
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    meta(US_SUBJECT, META_OK, 100, 4);
    registerIn(OTHER_TX, AUTHORITY, US_NAME, "address", VALUE_B, 250, 1);
    meta(US_SUBJECT, META_OK, 100, 4);

    assert.fieldEquals(
      "RegistryMeta",
      mockRowId(4),
      "configRegister",
      mockRowId(3),
    );
    assert.fieldEquals("RegistryMeta", mockRowId(4), "verified", "true");
  });

  test("a replayed Register leaves the subject on the latest Register", () => {
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    registerIn(OTHER_TX, AUTHORITY, US_NAME, "address", VALUE_B, 250, 1);
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    handleConfigRegistryV5MetaV1_2(
      changetype<MetaV1_2>(
        inTx(
          metaEvent(US_SUBJECT, META_OK, 250, 2),
          Bytes.fromHexString(OTHER_TX),
        ),
      ),
    );

    let row = rowIdIn(OTHER_TX, 2);
    assert.fieldEquals(
      "RegistryMeta",
      row,
      "configRegister",
      rowIdIn(OTHER_TX, 1),
    );
    assert.fieldEquals("RegistryMeta", row, "verified", "true");
  });

  test("a meta from another registry with the same subject is not linked", () => {
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    handleConfigRegistryV5MetaV1_2(
      changetype<MetaV1_2>(
        metaV1_2Log(
          Address.fromString(OTHER_REGISTRY),
          Address.fromString(DELEGATE),
          Bytes.fromHexString(US_SUBJECT),
          Bytes.fromHexString(META_OK),
          100,
          4,
        ),
      ),
    );

    let entity = RegistryMeta.load(Bytes.fromHexString(mockRowId(4)))!;
    assert.assertTrue(entity.configBinding === null);
    assert.assertTrue(entity.configRegister === null);
    assert.fieldEquals("RegistryMeta", mockRowId(4), "verified", "false");
  });
});

const VERIFIED = "true|st0x.rbac.us.v1";
const UNVERIFIED = "false|null";
function verifiedFor(metaHex: string, valueType: string): string {
  register(AUTHORITY, US_NAME, valueType, VALUE_A, 100, 3);
  meta(US_SUBJECT, metaHex, 100, 4);
  let row = RegistryMeta.load(Bytes.fromHexString(mockRowId(4)))!;
  let name = row.nameString;
  return (row.verified ? "true|" : "false|").concat(
    name === null ? "null" : name!,
  );
}

describe("ConfigRegistryV5 MetaV1_2 verification", () => {
  afterEach(clearStore);

  test("name and value type preimages that hash to the binding verify", () => {
    assert.stringEquals(verifiedFor(META_OK, "address"), VERIFIED);
  });

  test("a name preimage that hashes elsewhere does not verify", () => {
    assert.stringEquals(
      verifiedFor(P.concat(NAME_EU).concat(TYPE_ADDRESS), "address"),
      UNVERIFIED,
    );
  });

  test("a value type preimage that hashes elsewhere does not verify", () => {
    assert.stringEquals(
      verifiedFor(P.concat(NAME_US).concat(TYPE_UINT256), "address"),
      UNVERIFIED,
    );
  });

  test("the value type is checked against this Register's type", () => {
    assert.stringEquals(verifiedFor(META_OK, "uint256"), UNVERIFIED);
  });

  test("the value type preimage is checked against the stored type hash", () => {
    registerStoring(
      TX_HASH.toHexString(),
      AUTHORITY,
      US_NAME,
      "address",
      ADDRESS_NUL_HASH,
      VALUE_A,
      100,
      3,
    );
    meta(US_SUBJECT, P.concat(NAME_US).concat(TYPE_ADDRESS_NUL), 100, 4);
    meta(US_SUBJECT, META_OK, 100, 5);

    assert.fieldEquals("RegistryMeta", mockRowId(4), "verified", "true");
    assert.fieldEquals("RegistryMeta", mockRowId(5), "verified", "false");
  });

  test("a missing name or value type item does not verify", () => {
    assert.stringEquals(verifiedFor(P.concat(NAME_US), "address"), UNVERIFIED);
    clearStore();
    assert.stringEquals(
      verifiedFor(P.concat(TYPE_ADDRESS), "address"),
      UNVERIFIED,
    );
  });

  test("a second name item that hashes elsewhere does not verify", () => {
    assert.stringEquals(
      verifiedFor(
        P.concat(NAME_US).concat(NAME_EU).concat(TYPE_ADDRESS),
        "address",
      ),
      UNVERIFIED,
    );
  });

  test("foreign items are skipped and identity encoding is plain", () => {
    assert.stringEquals(verifiedFor(META_FOREIGN, "address"), VERIFIED);
    clearStore();
    assert.stringEquals(verifiedFor(META_EXOTIC, "address"), VERIFIED);
    clearStore();
    assert.stringEquals(verifiedFor(META_NESTED_MAP, "address"), VERIFIED);
  });

  test("a deflated preimage does not verify", () => {
    assert.stringEquals(verifiedFor(META_DEFLATE, "address"), UNVERIFIED);
  });

  test("a raw preimage declared deflated does not verify", () => {
    assert.stringEquals(
      verifiedFor(META_RAW_DECLARED_DEFLATE, "address"),
      UNVERIFIED,
    );
  });

  test("items under another document magic do not verify", () => {
    assert.stringEquals(
      verifiedFor(
        "0xffcdcfae6227d5e9".concat(NAME_US).concat(TYPE_ADDRESS),
        "address",
      ),
      UNVERIFIED,
    );
  });

  test("malformed meta does not verify", () => {
    let cases = [
      META,
      META_OK.slice(0, META_OK.length - 2),
      "0x".concat(META_OK.slice(18)),
      "0xff0a89c674ee78",
      "0x",
      META_RESERVED_INFO,
      META_TEXT_KEY,
      META_DUPLICATE_KEY,
      META_NO_MAGIC,
      META_NO_PAYLOAD,
      META_TRAILING_BREAK,
      META_TOO_DEEP,
      META_INDEFINITE_INT,
      META_MIXED_CHUNK,
      META_INDEFINITE_TAG,
      META_LONE_BREAK,
      META_EMPTY_TEXT_KEY,
      META_NEGATIVE_MAGIC,
      META_TRUNCATED_ITEM,
    ];
    for (let i = 0; i < cases.length; i++) {
      clearStore();
      assert.stringEquals(verifiedFor(cases[i], "address"), UNVERIFIED);
    }
  });

  test("a nested map counting 2^63 entries does not verify", () => {
    assert.stringEquals(
      verifiedFor(META_MAP_COUNT_2_POW_63, "address"),
      UNVERIFIED,
    );
  });

  test("meta with no Register in its transaction does not verify", () => {
    register(AUTHORITY, US_NAME, "address", VALUE_A, 100, 3);
    handleConfigRegistryV5MetaV1_2(
      changetype<MetaV1_2>(
        inTx(
          metaEvent(US_SUBJECT, META_OK, 300, 0),
          Bytes.fromHexString(OTHER_TX),
        ),
      ),
    );
    assert.fieldEquals(
      "RegistryMeta",
      rowIdIn(OTHER_TX, 0),
      "verified",
      "false",
    );
    assert.assertNull<string | null>(
      RegistryMeta.load(Bytes.fromHexString(rowIdIn(OTHER_TX, 0)))!.nameString,
    );
    clearStore();
    meta(EU_NAME, META_OK, 100, 4);
    assert.fieldEquals("RegistryMeta", mockRowId(4), "verified", "false");
    assert.assertNull<string | null>(
      RegistryMeta.load(Bytes.fromHexString(mockRowId(4)))!.nameString,
    );
  });
});

/** `P` the document prefix, `NAME`/`TYPE` the items, `RL`/`NM`/`SK` magics, `NP` the name. */
function corpusToken(word: string): string {
  if (word == "P") return P.slice(2);
  if (word == "NAME") return NAME_US;
  if (word == "TYPE") return TYPE_ADDRESS;
  if (word == "RL") return "1bff13109e41336ff2";
  if (word == "NM") return "1bffcdcfae6227d5e9";
  if (word == "NP") return "737430782e726261632e75732e7631";
  if (word == "SK") return "1bffa8e8a9b9cf4a31";
  return word;
}

/** Space-separated hex words; `w*n` repeats `w` n times. */
function hexOf(spec: string): string {
  let words = spec.split(" ");
  let out = "";
  for (let i = 0; i < words.length; i++) {
    let word = words[i];
    let star = word.indexOf("*");
    if (star >= 0) {
      out = out.concat(
        word.slice(0, star).repeat(I32.parseInt(word.slice(star + 1))),
      );
    } else {
      out = out.concat(corpusToken(word));
    }
  }
  return out;
}

/** `value`: key 5 of a foreign item; `item`: an item; `name`: the name item; `doc`: the whole meta. */
function documentOf(group: string, spec: string): string {
  let body = hexOf(spec);
  if (group == "value") {
    return P.concat(FOREIGN_KEY_5)
      .concat(body)
      .concat(NAME_US)
      .concat(TYPE_ADDRESS);
  }
  if (group == "item") {
    return P.concat(body).concat(NAME_US).concat(TYPE_ADDRESS);
  }
  if (group == "name") {
    return P.concat(body).concat(TYPE_ADDRESS);
  }
  assert.stringEquals(group, "doc");
  return "0x".concat(body);
}

/** Each `[group, spec, expected]` whose verification differs from rain.metadata `cbor_decode`'s. */
function diverging(cases: string[][]): string {
  let out = "";
  for (let i = 0; i < cases.length; i++) {
    clearStore();
    let got = verifiedFor(documentOf(cases[i][0], cases[i][1]), "address");
    if (got != cases[i][2]) {
      out = out
        .concat(cases[i][0])
        .concat(" ")
        .concat(cases[i][1])
        .concat(": oracle ")
        .concat(cases[i][2])
        .concat(", subgraph ")
        .concat(got)
        .concat("\n");
    }
  }
  return out;
}

describe("ConfigRegistryV5 MetaV1_2 rainmeta corpus", () => {
  afterEach(clearStore);

  test("a skipped integer or simple value verifies exactly when cbor_decode reads it", () => {
    assert.stringEquals(
      diverging([
        ["value", "00", VERIFIED],
        ["value", "17", VERIFIED],
        ["value", "1801", VERIFIED],
        ["value", "1817", VERIFIED],
        ["value", "190001", VERIFIED],
        ["value", "1a00000001", VERIFIED],
        ["value", "1b0000000000000001", VERIFIED],
        ["value", "1bffffffffffffffff", VERIFIED],
        ["value", "1c", UNVERIFIED],
        ["value", "1d", UNVERIFIED],
        ["value", "1e", UNVERIFIED],
        ["value", "1f", UNVERIFIED],
        ["value", "20", VERIFIED],
        ["value", "37", VERIFIED],
        ["value", "3801", VERIFIED],
        ["value", "39ffff", VERIFIED],
        ["value", "3affffffff", VERIFIED],
        ["value", "3b7fffffffffffffff", VERIFIED],
        ["value", "3b8000000000000000", VERIFIED],
        ["value", "3bffffffffffffffff", VERIFIED],
        ["value", "3c", UNVERIFIED],
        ["value", "3d", UNVERIFIED],
        ["value", "3e", UNVERIFIED],
        ["value", "3f", UNVERIFIED],
        ["value", "e0", UNVERIFIED],
        ["value", "f3", UNVERIFIED],
        ["value", "f4", VERIFIED],
        ["value", "f5", VERIFIED],
        ["value", "f6", VERIFIED],
        ["value", "f7", VERIFIED],
        ["value", "f800", UNVERIFIED],
        ["value", "f813", UNVERIFIED],
        ["value", "f818", UNVERIFIED],
        ["value", "f820", UNVERIFIED],
        ["value", "f8ff", UNVERIFIED],
        ["value", "f93c00", VERIFIED],
        ["value", "f97e00", VERIFIED],
        ["value", "fa3f800000", VERIFIED],
        ["value", "fb3ff0000000000000", VERIFIED],
        ["value", "fc", UNVERIFIED],
        ["value", "fd", UNVERIFIED],
        ["value", "fe", UNVERIFIED],
        ["value", "ff", UNVERIFIED],
      ]),
      "",
    );
  });

  test("a skipped byte or text string verifies exactly when cbor_decode reads it", () => {
    assert.stringEquals(
      diverging([
        ["value", "40", VERIFIED],
        ["value", "4161", VERIFIED],
        ["value", "5801 61", VERIFIED],
        ["value", "5800", VERIFIED],
        ["value", "590001 61", VERIFIED],
        ["value", "5a00000001 61", VERIFIED],
        ["value", "5b0000000000000001 61", VERIFIED],
        ["value", "5bffffffffffffffff", UNVERIFIED],
        ["value", "5c", UNVERIFIED],
        ["value", "5d", UNVERIFIED],
        ["value", "5e", UNVERIFIED],
        ["value", "5fff", VERIFIED],
        ["value", "5f 4161 ff", VERIFIED],
        ["value", "5f 40 ff", VERIFIED],
        ["value", "5f 4161 426263 ff", VERIFIED],
        ["value", "5f 5800 ff", VERIFIED],
        ["value", "5f 6161 ff", UNVERIFIED],
        ["value", "5f 5fff ff", UNVERIFIED],
        ["value", "5f c24161 ff", UNVERIFIED],
        ["value", "5f 00 ff", UNVERIFIED],
        ["value", "5f 5c ff", UNVERIFIED],
        ["value", "60", VERIFIED],
        ["value", "6161", VERIFIED],
        ["value", "61ff", UNVERIFIED],
        ["value", "61c3", UNVERIFIED],
        ["value", "6180", UNVERIFIED],
        ["value", "61fe", UNVERIFIED],
        ["value", "62c3a9", VERIFIED],
        ["value", "62c0af", UNVERIFIED],
        ["value", "62c1bf", UNVERIFIED],
        ["value", "62e0a0", UNVERIFIED],
        ["value", "63c3a961", VERIFIED],
        ["value", "63e08080", UNVERIFIED],
        ["value", "63e0a080", VERIFIED],
        ["value", "63eda080", UNVERIFIED],
        ["value", "63ed9fbf", VERIFIED],
        ["value", "63efbfbf", VERIFIED],
        ["value", "64f0808080", UNVERIFIED],
        ["value", "64f0908080", VERIFIED],
        ["value", "64f48fbfbf", VERIFIED],
        ["value", "64f4908080", UNVERIFIED],
        ["value", "64f5808080", UNVERIFIED],
        ["value", "7801 61", VERIFIED],
        ["value", "7b0000000000000001 61", VERIFIED],
        ["value", "7bffffffffffffffff", UNVERIFIED],
        ["value", "7c", UNVERIFIED],
        ["value", "7d", UNVERIFIED],
        ["value", "7e", UNVERIFIED],
        ["value", "7fff", VERIFIED],
        ["value", "7f 6161 6162 ff", VERIFIED],
        ["value", "7f 61c3 61a9 ff", VERIFIED],
        ["value", "7f 61c3 ff", UNVERIFIED],
        ["value", "7f 61ff ff", UNVERIFIED],
        ["value", "7f 4161 ff", UNVERIFIED],
        ["value", "7f 7fff ff", UNVERIFIED],
        ["value", "7f c26161 ff", UNVERIFIED],
        ["value", "617f", VERIFIED],
        ["value", "62c280", VERIFIED],
        ["value", "62dfbf", VERIFIED],
        ["value", "63e0a0c0", UNVERIFIED],
        ["value", "62c3c0", UNVERIFIED],
        ["value", "62c37f", UNVERIFIED],
        ["value", "63e0a041", UNVERIFIED],
        ["value", "626180", UNVERIFIED],
        ["value", "64f09080c0", UNVERIFIED],
        ["value", "64f090807f", UNVERIFIED],
        ["value", "64f0c08080", UNVERIFIED],
        ["item", "bf 00 4161 01 RL 05 5f 5f ff ff", UNVERIFIED],
        ["item", "bf 00 4161 01 RL 05 7f 7f ff ff", UNVERIFIED],
      ]),
      "",
    );
  });

  test("a skipped array or map verifies exactly when cbor_decode reads it", () => {
    assert.stringEquals(
      diverging([
        ["value", "80", VERIFIED],
        ["value", "8100", VERIFIED],
        ["value", "820001", VERIFIED],
        ["value", "9801 00", VERIFIED],
        ["value", "990001 00", VERIFIED],
        ["value", "9a00000001 00", VERIFIED],
        ["value", "9b0000000000000001 00", VERIFIED],
        ["value", "9c", UNVERIFIED],
        ["value", "9d", UNVERIFIED],
        ["value", "9e", UNVERIFIED],
        ["value", "9fff", VERIFIED],
        ["value", "9f 00 01 ff", VERIFIED],
        ["value", "9f 9fff ff", VERIFIED],
        ["value", "9f 00", UNVERIFIED],
        ["value", "9f 61ff ff", UNVERIFIED],
        ["value", "9affffffff", UNVERIFIED],
        ["value", "9b8000000000000000", UNVERIFIED],
        ["value", "9bffffffffffffffff", UNVERIFIED],
        ["value", "a0", VERIFIED],
        ["value", "a1 00 01", VERIFIED],
        ["value", "a1 6161 00", VERIFIED],
        ["value", "a1 61ff 00", UNVERIFIED],
        ["value", "a1 00 61ff", UNVERIFIED],
        ["value", "a1 a0 00", VERIFIED],
        ["value", "a1 80 00", VERIFIED],
        ["value", "a2 00 01 00 02", VERIFIED],
        ["value", "b801 00 01", VERIFIED],
        ["value", "bc", UNVERIFIED],
        ["value", "bd", UNVERIFIED],
        ["value", "be", UNVERIFIED],
        ["value", "bfff", VERIFIED],
        ["value", "bf 00 01 ff", VERIFIED],
        ["value", "bf 00 ff", UNVERIFIED],
        ["value", "bf ff", VERIFIED],
        ["value", "bf 00 01", UNVERIFIED],
        ["value", "bf 61ff 00 ff", UNVERIFIED],
        ["value", "baffffffff", UNVERIFIED],
        ["value", "bb8000000000000000", UNVERIFIED],
        ["value", "bbffffffffffffffff", UNVERIFIED],
      ]),
      "",
    );
  });

  test("a skipped map's text and other non-integer keys verify exactly when cbor_decode reads them", () => {
    assert.stringEquals(
      diverging([
        ["value", "a1 60 00", VERIFIED],
        ["value", "a1 63616263 00", VERIFIED],
        ["value", "a1 62c3a9 00", VERIFIED],
        ["value", "a1 63e282ac 00", VERIFIED],
        ["value", "a1 64f09f9880 00", VERIFIED],
        ["value", "a1 6100 00", VERIFIED],
        ["value", "a1 617f 00", VERIFIED],
        ["value", "a1 61c3 00", UNVERIFIED],
        ["value", "a1 6180 00", UNVERIFIED],
        ["value", "a1 61fe 00", UNVERIFIED],
        ["value", "a1 62c0af 00", UNVERIFIED],
        ["value", "a1 62c1bf 00", UNVERIFIED],
        ["value", "a1 63e08080 00", UNVERIFIED],
        ["value", "a1 63eda080 00", UNVERIFIED],
        ["value", "a1 64f4908080 00", UNVERIFIED],
        ["value", "a1 64f8888080 00", UNVERIFIED],
        ["value", "a1 7801 61 00", VERIFIED],
        ["value", "a1 790001 61 00", VERIFIED],
        ["value", "a1 7a00000001 61 00", VERIFIED],
        ["value", "a1 7b0000000000000001 61 00", VERIFIED],
        ["value", "a1 7bffffffffffffffff 00", UNVERIFIED],
        ["value", "a1 7c 00", UNVERIFIED],
        ["value", "a1 7d 00", UNVERIFIED],
        ["value", "a1 7e 00", UNVERIFIED],
        ["value", "a1 7fff 00", VERIFIED],
        ["value", "a1 7f 6161 ff 00", VERIFIED],
        ["value", "a1 7f 6161 6162 ff 00", VERIFIED],
        ["value", "a1 7f 60 ff 00", VERIFIED],
        ["value", "a1 7f 61c3 61a9 ff 00", VERIFIED],
        ["value", "a1 7f 61c3 ff 00", UNVERIFIED],
        ["value", "a1 7f 61ff ff 00", UNVERIFIED],
        ["value", "a1 7f 4161 ff 00", UNVERIFIED],
        ["value", "a1 7f 7fff ff 00", UNVERIFIED],
        ["value", "a1 7f c26161 ff 00", UNVERIFIED],
        ["value", "a1 7f 00 ff 00", UNVERIFIED],
        ["value", "a1 6161 61ff", UNVERIFIED],
        ["value", "a1 6161 7f 61c3 ff", UNVERIFIED],
        ["value", "a1 6161 a1 6162 00", VERIFIED],
        ["value", "a1 6161 a1 6162 a1 6163 00", VERIFIED],
        ["value", "a1 6161 a1 61ff 00", UNVERIFIED],
        ["value", "a1 6161 81 6162", VERIFIED],
        ["value", "a1 6161 c1 6162", VERIFIED],
        ["value", "a2 6161 00 6162 01", VERIFIED],
        ["value", "a2 6161 00 6161 01", VERIFIED],
        ["value", "a2 6161 00 00 01", VERIFIED],
        ["value", "a2 00 01 6161 00", VERIFIED],
        ["value", "a2 6161 00 4161 01", VERIFIED],
        ["value", "a2 6161 00 61ff 01", UNVERIFIED],
        ["value", "a3 6161 00 4161 01 f6 02", VERIFIED],
        ["value", "a1 40 00", VERIFIED],
        ["value", "a1 4161 00", VERIFIED],
        ["value", "a1 41ff 00", VERIFIED],
        ["value", "a1 4bffffffffffffffffffffff 00", VERIFIED],
        ["value", "a1 5801 61 00", VERIFIED],
        ["value", "a1 5bffffffffffffffff 00", UNVERIFIED],
        ["value", "a1 5c 00", UNVERIFIED],
        ["value", "a1 5fff 00", VERIFIED],
        ["value", "a1 5f 4161 ff 00", VERIFIED],
        ["value", "a1 5f 4161 4162 ff 00", VERIFIED],
        ["value", "a1 5f 6161 ff 00", UNVERIFIED],
        ["value", "a1 5f c24161 ff 00", UNVERIFIED],
        ["value", "a1 20 00", VERIFIED],
        ["value", "a1 37 00", VERIFIED],
        ["value", "a1 38ff 00", VERIFIED],
        ["value", "a1 3bffffffffffffffff 00", VERIFIED],
        ["value", "a1 3c 00", UNVERIFIED],
        ["value", "a1 1bffffffffffffffff 00", VERIFIED],
        ["value", "a1 1c 00", UNVERIFIED],
        ["value", "a1 1f 00", UNVERIFIED],
        ["value", "a1 f4 00", VERIFIED],
        ["value", "a1 f5 00", VERIFIED],
        ["value", "a1 f6 00", VERIFIED],
        ["value", "a1 f7 00", VERIFIED],
        ["value", "a1 e0 00", UNVERIFIED],
        ["value", "a1 f3 00", UNVERIFIED],
        ["value", "a1 f800 00", UNVERIFIED],
        ["value", "a1 f818 00", UNVERIFIED],
        ["value", "a1 f820 00", UNVERIFIED],
        ["value", "a1 f8ff 00", UNVERIFIED],
        ["value", "a1 f93c00 00", VERIFIED],
        ["value", "a1 f97e00 00", VERIFIED],
        ["value", "a1 f97c00 00", VERIFIED],
        ["value", "a1 fa3f800000 00", VERIFIED],
        ["value", "a1 fb3ff0000000000000 00", VERIFIED],
        ["value", "a1 fc 00", UNVERIFIED],
        ["value", "a1 ff 00", UNVERIFIED],
        ["value", "a1 c1 00 00", VERIFIED],
        ["value", "a1 c1 6161 00", VERIFIED],
        ["value", "a1 c1 61ff 00", UNVERIFIED],
        ["value", "a1 c2 4161 00", VERIFIED],
        ["value", "a1 c1 c1 6161 00", VERIFIED],
        ["value", "a1 d8ff 6161 00", VERIFIED],
        ["value", "a1 dc 00 00", UNVERIFIED],
        ["value", "a1 df 00 00", UNVERIFIED],
        ["value", "a1 8100 00", VERIFIED],
        ["value", "a1 816161 00", VERIFIED],
        ["value", "a1 8161ff 00", UNVERIFIED],
        ["value", "a1 9fff 00", VERIFIED],
        ["value", "a1 9f 6161 ff 00", VERIFIED],
        ["value", "a1 a1 6161 00 00", VERIFIED],
        ["value", "a1 a1 61ff 00 00", UNVERIFIED],
        ["value", "a1 a1 a1 6161 00 00 00", VERIFIED],
        ["value", "a1 bfff 00", VERIFIED],
        ["value", "a1 bf 6161 00 ff 00", VERIFIED],
        ["value", "a1 6161", UNVERIFIED],
        ["value", "a2 6161 00 6162", UNVERIFIED],
        ["value", "bf 6161 00 ff", VERIFIED],
        ["value", "bf 6161 00 6162 01 ff", VERIFIED],
        ["value", "bf 6161 00 00 01 ff", VERIFIED],
        ["value", "bf 60 00 ff", VERIFIED],
        ["value", "bf 7f 6161 ff 00 ff", VERIFIED],
        ["value", "bf 7f 61c3 61a9 ff 00 ff", VERIFIED],
        ["value", "bf 7f 61c3 ff 00 ff", UNVERIFIED],
        ["value", "bf 4161 00 ff", VERIFIED],
        ["value", "bf 5f 4161 ff 00 ff", VERIFIED],
        ["value", "bf 20 00 ff", VERIFIED],
        ["value", "bf f6 00 ff", VERIFIED],
        ["value", "bf f93c00 00 ff", VERIFIED],
        ["value", "bf c1 6161 00 ff", VERIFIED],
        ["value", "bf 80 00 ff", VERIFIED],
        ["value", "bf a0 00 ff", VERIFIED],
        ["value", "bf 61c3 00 ff", UNVERIFIED],
        ["value", "bf e0 00 ff", UNVERIFIED],
        ["value", "bf 6161 ff", UNVERIFIED],
        ["value", "bf 6161 00 6162 ff", UNVERIFIED],
        ["value", "bf 6161 ff ff", UNVERIFIED],
        ["value", "b801 6161 00", VERIFIED],
        ["value", "b90001 6161 00", VERIFIED],
        ["value", "81 a1 6161 00", VERIFIED],
        ["value", "82 a1 6161 00 a1 4161 01", VERIFIED],
        ["value", "9f a1 6161 00 ff", VERIFIED],
        ["value", "9f bf 6161 00 ff ff", VERIFIED],
        ["value", "c1 a1 6161 00", VERIFIED],
        ["value", "c1 bf 6161 00 ff", VERIFIED],
        ["value", "a1 6161 81*125 00", VERIFIED],
        ["value", "a1 81*125 00 00", VERIFIED],
        ["value", "a1 81*126 00 00", UNVERIFIED],
        ["value", "a1 6161 81*126 00", UNVERIFIED],
        ["value", "a1 81*125 80 00", UNVERIFIED],
        ["value", "bf 81*125 00 00 ff", VERIFIED],
        ["value", "bf 81*126 00 00 ff", UNVERIFIED],
        ["value", "81*125 a1 6161 00", VERIFIED],
        ["value", "81*126 a1 6161 00", UNVERIFIED],
        ["value", "81*125 bf 6161 00 ff", VERIFIED],
        ["value", "81*126 bf 6161 00 ff", UNVERIFIED],
      ]),
      "",
    );
  });

  test("a skipped tag verifies exactly when cbor_decode reads its content", () => {
    assert.stringEquals(
      diverging([
        ["value", "c000", VERIFIED],
        ["value", "c100", VERIFIED],
        ["value", "d700", VERIFIED],
        ["value", "d8ff 00", VERIFIED],
        ["value", "d9ffff 00", VERIFIED],
        ["value", "daffffffff 00", VERIFIED],
        ["value", "dbffffffffffffffff 00", VERIFIED],
        ["value", "dc00", UNVERIFIED],
        ["value", "dd00", UNVERIFIED],
        ["value", "de00", UNVERIFIED],
        ["value", "df00", UNVERIFIED],
        ["value", "c24161", VERIFIED],
        ["value", "c34100", VERIFIED],
        ["value", "c2c200", VERIFIED],
        ["value", "c1f6", VERIFIED],
        ["value", "c1ff", UNVERIFIED],
        ["value", "c19fff", VERIFIED],
        ["value", "c1a0", VERIFIED],
        ["value", "d9d9f7 a0", VERIFIED],
        ["value", "c161ff", UNVERIFIED],
        ["value", "c1 7f 61c3 ff", UNVERIFIED],
      ]),
      "",
    );
  });

  test("nesting verifies to 126 containers and tags deep and no deeper", () => {
    assert.stringEquals(
      diverging([
        ["value", "81*125 00", VERIFIED],
        ["value", "81*126 00", VERIFIED],
        ["value", "81*127 00", UNVERIFIED],
        ["value", "81*128 00", UNVERIFIED],
        ["value", "81*125 80", VERIFIED],
        ["value", "81*126 80", UNVERIFIED],
        ["value", "81*125 a0", VERIFIED],
        ["value", "81*126 a0", UNVERIFIED],
        ["value", "9f*126 00 ff*126", VERIFIED],
        ["value", "9f*127 00 ff*127", UNVERIFIED],
        ["value", "a100*126 00", VERIFIED],
        ["value", "a100*127 00", UNVERIFIED],
        ["value", "bf00*126 00 ff*126", VERIFIED],
        ["value", "bf00*127 00 ff*127", UNVERIFIED],
        ["value", "c1*126 00", VERIFIED],
        ["value", "c1*127 00", UNVERIFIED],
        ["value", "81*63 c1*63 00", VERIFIED],
        ["value", "81*64 c1*63 00", UNVERIFIED],
        ["value", "81*125 c100", VERIFIED],
        ["value", "81*126 c100", UNVERIFIED],
        ["item", "c1*125 a2 00 4161 01 RL", VERIFIED],
        ["item", "c1*126 a2 00 4161 01 RL", VERIFIED],
        ["item", "c1*127 a2 00 4161 01 RL", UNVERIFIED],
        ["item", "c1*128 a2 00 4161 01 RL", UNVERIFIED],
        ["item", "c1*63 a3 00 4161 01 RL 05 81*63 00", VERIFIED],
        ["item", "c1*63 a3 00 4161 01 RL 05 81*64 00", UNVERIFIED],
        ["item", "a2 c1*126 00 4161 01 RL", VERIFIED],
        ["item", "a2 c1*127 00 4161 01 RL", UNVERIFIED],
        ["item", "a2 00 4161 c1*126 01 RL", VERIFIED],
        ["item", "a2 00 4161 c1*127 01 RL", UNVERIFIED],
        ["item", "a2 00 4161 01 c1*126 RL", VERIFIED],
        ["item", "a2 00 4161 01 c1*127 RL", UNVERIFIED],
        ["item", "a2 00 c1*126 4161 01 RL", VERIFIED],
        ["item", "a2 00 c1*127 4161 01 RL", UNVERIFIED],
        ["item", "a2 00 c1*125 8101 01 RL", VERIFIED],
        ["item", "a2 00 c1*126 8101 01 RL", UNVERIFIED],
        ["item", "a2 00 81 c1*125 01 01 RL", VERIFIED],
        ["item", "a2 00 81 c1*126 01 01 RL", UNVERIFIED],
        ["item", "a2 00 9f c1*125 01 ff 01 RL", VERIFIED],
        ["item", "a2 00 9f c1*126 01 ff 01 RL", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 c1*126 00", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 c1*127 00", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 a1 c1*125 00 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 a1 c1*126 00 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 a1 00 c1*125 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 a1 00 c1*126 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 82 c1*125 00 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 82 c1*126 00 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 82 00 c1*125 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 82 00 c1*126 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL SK c1*126 6161", VERIFIED],
        ["item", "a3 00 4161 01 RL SK c1*127 6161", UNVERIFIED],
        ["item", "c1*125 a3 00 4161 01 RL 03 a1 00 f6", VERIFIED],
        ["item", "c1*126 a3 00 4161 01 RL 03 a1 00 f6", UNVERIFIED],
        ["item", "c1*125 a3 00 4161 01 RL 03 82 00 f6", VERIFIED],
        ["item", "c1*126 a3 00 4161 01 RL 03 82 00 f6", UNVERIFIED],
        ["item", "c1*126 a3 00 4161 01 RL 03 00", VERIFIED],
        ["item", "c1*126 a2 00 8101 01 RL", UNVERIFIED],
        ["item", "c1*125 a2 00 8101 01 RL", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 c1*126 00", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 c1*127 00", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 04 c1*126 00", VERIFIED],
        ["item", "a3 00 4161 01 RL 04 c1*127 00", UNVERIFIED],
        ["value", "81*126 4161", VERIFIED],
        ["value", "81*126 6161", VERIFIED],
        ["value", "81*126 5f ff", VERIFIED],
      ]),
      "",
    );
  });

  test("item map keys, counts and tags verify exactly when cbor_decode reads them", () => {
    assert.stringEquals(
      diverging([
        ["item", "a2 c100 4161 01 RL", VERIFIED],
        ["item", "a2 1800 4161 01 RL", VERIFIED],
        ["item", "a2 190000 4161 01 RL", VERIFIED],
        ["item", "a2 1b0000000000000000 4161 01 RL", VERIFIED],
        ["item", "a2 00 4161 1801 RL", VERIFIED],
        ["item", "a2 20 4161 01 RL", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 20 00", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 6161 00", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 4161 00", UNVERIFIED],
        ["item", "a3 00 4161 01 RL f6 00", UNVERIFIED],
        ["item", "a3 00 4161 01 RL f4 00", UNVERIFIED],
        ["item", "a3 00 4161 01 RL f93c00 00", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 80 00", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 1f 00", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 1bffffffffffffffff 00", VERIFIED],
        ["item", "a3 00 4161 01 RL 3bffffffffffffffff 00", UNVERIFIED],
        ["item", "a4 00 4161 01 RL 05 00 05 00", UNVERIFIED],
        ["item", "a4 00 4161 01 RL 05 00 1805 00", UNVERIFIED],
        ["item", "a4 00 4161 01 RL 05 00 06 00", VERIFIED],
        ["item", "a3 00 4161 01 RL 00 4162", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 01 RL", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 1800 4162", UNVERIFIED],
        ["item", "a4 00 4161 01 RL 02 00 02 00", UNVERIFIED],
        ["item", "a4 00 4161 01 RL 03 00 03 00", UNVERIFIED],
        ["item", "a4 00 4161 01 RL 04 00 04 00", UNVERIFIED],
        ["item", "a4 00 4161 01 RL SK 6161 SK 6161", UNVERIFIED],
        ["item", "a2 01 RL 00 4161", VERIFIED],
        ["item", "a0", UNVERIFIED],
        ["item", "a1 00 4161", UNVERIFIED],
        ["item", "a1 01 RL", UNVERIFIED],
        ["item", "bf 00 4161 01 RL ff", VERIFIED],
        ["item", "bf ff", UNVERIFIED],
        ["item", "bf 00 4161 01 RL 05 00 ff", VERIFIED],
        ["item", "bf 00 4161 01 RL", UNVERIFIED],
        ["item", "bf 00 4161 01 RL 05 ff", UNVERIFIED],
        ["item", "b802 00 4161 01 RL", VERIFIED],
        ["item", "b90002 00 4161 01 RL", VERIFIED],
        ["item", "bb0000000000000002 00 4161 01 RL", VERIFIED],
        ["item", "a3 00 4161 01 RL", UNVERIFIED],
        ["item", "a1 00 4161 01 RL", UNVERIFIED],
        ["item", "bb8000000000000000 00 4161 01 RL", UNVERIFIED],
        ["item", "82004161011bff13109e41336ff2", UNVERIFIED],
        ["item", "80", UNVERIFIED],
        ["item", "9f ff", UNVERIFIED],
        ["item", "f6", UNVERIFIED],
        ["item", "00", UNVERIFIED],
        ["item", "4161", UNVERIFIED],
        ["item", "6161", UNVERIFIED],
        ["item", "c1 a2 00 4161 01 RL", VERIFIED],
        ["item", "d8ff a2 00 4161 01 RL", VERIFIED],
        ["item", "dbffffffffffffffff a2 00 4161 01 RL", VERIFIED],
        ["item", "c1 c2 a2 00 4161 01 RL", VERIFIED],
        ["item", "df a2 00 4161 01 RL", UNVERIFIED],
        ["item", "a2 00 4161 01 1b0000000000000001", VERIFIED],
        ["item", "a2 00 4161 01 00", VERIFIED],
        ["item", "a2 00 61ff 01 1b0000000000000001", UNVERIFIED],
        ["item", "a3 00 4161 01 1b0000000000000001 03 03", UNVERIFIED],
        ["item", "a3 00 4161 01 1b0000000000000001 05 61ff", UNVERIFIED],
        ["item", "a3 00 4161 01 1b0000000000000001 05 81*127 00", UNVERIFIED],
        ["item", "a2 00 4161 01 1bff0a89c674ee7874", UNVERIFIED],
        ["item", "a2 00 4161 01 c1 1bff0a89c674ee7874", UNVERIFIED],
        [
          "item",
          "a2 00 4161 01 RL a2 00 4161 01 1bff0a89c674ee7874",
          UNVERIFIED,
        ],
        ["item", "a4 00 4161 1b0100000000000000 00 00 4162 01 RL", UNVERIFIED],
        ["item", "a4 00 4161 190100 00 00 4162 01 RL", UNVERIFIED],
        ["item", "a4 00 4161 1880 00 00 4162 01 RL", UNVERIFIED],
        ["item", "a4 00 4161 1b8000000000000000 00 00 4162 01 RL", UNVERIFIED],
        ["item", "a4 00 4161 05 00 00 4162 01 RL", UNVERIFIED],
        ["item", "a3 190100 00 00 4161 01 RL", VERIFIED],
        ["item", "a3 1b0100000000000000 00 00 4161 01 RL", VERIFIED],
        ["item", "a3 1880 00 00 4161 01 RL", VERIFIED],
        ["item", "a4 190180 00 1880 00 00 4161 01 RL", VERIFIED],
        [
          "item",
          "a5 1b0100000000000000 00 190100 00 1880 00 00 4161 01 RL",
          VERIFIED,
        ],
        ["item", "a2 1f 4161 01 RL", UNVERIFIED],
        ["item", "a2 01 RL 1f 4161", UNVERIFIED],
        ["item", "bf 1f 4161 01 RL ff", UNVERIFIED],
        ["item", "a2 c1 1f 4161 01 RL", UNVERIFIED],
      ]),
      "",
    );
  });

  test("item magic forms verify exactly when cbor_decode reads them", () => {
    assert.stringEquals(
      diverging([
        ["item", "a2 00 4161 01 c1 RL", VERIFIED],
        ["item", "a2 00 4161 01 c1 c1 RL", VERIFIED],
        ["item", "a2 00 4161 01 20", UNVERIFIED],
        ["item", "a2 00 4161 01 3bff13109e41336ff2", UNVERIFIED],
        ["item", "a2 00 4161 01 48ff13109e41336ff2", UNVERIFIED],
        ["item", "a2 00 4161 01 6161", UNVERIFIED],
        ["item", "a2 00 4161 01 f6", UNVERIFIED],
        ["item", "a2 00 4161 01 f93c00", UNVERIFIED],
        ["item", "a2 00 4161 01 81 RL", UNVERIFIED],
        ["item", "a2 00 4161 01 1f", UNVERIFIED],
        ["item", "a2 00 4161 01 1c", UNVERIFIED],
      ]),
      "",
    );
  });

  test("item payload forms verify exactly when cbor_decode reads them", () => {
    assert.stringEquals(
      diverging([
        ["item", "a2 00 40 01 RL", VERIFIED],
        ["item", "a2 00 5fff 01 RL", VERIFIED],
        ["item", "a2 00 5f 4161 ff 01 RL", VERIFIED],
        ["item", "a2 00 5f 6161 ff 01 RL", UNVERIFIED],
        ["item", "a2 00 5f c24161 ff 01 RL", UNVERIFIED],
        ["item", "a2 00 60 01 RL", VERIFIED],
        ["item", "a2 00 61ff 01 RL", UNVERIFIED],
        ["item", "a2 00 7fff 01 RL", VERIFIED],
        ["item", "a2 00 7f 61c3 61a9 ff 01 RL", VERIFIED],
        ["item", "a2 00 7f 61c3 ff 01 RL", UNVERIFIED],
        ["item", "a2 00 7f 4161 ff 01 RL", UNVERIFIED],
        ["item", "a2 00 80 01 RL", VERIFIED],
        ["item", "a2 00 8100 01 RL", VERIFIED],
        ["item", "a2 00 8118ff 01 RL", VERIFIED],
        ["item", "a2 00 811900ff 01 RL", VERIFIED],
        ["item", "a2 00 81190100 01 RL", UNVERIFIED],
        ["item", "a2 00 811b00000000000000ff 01 RL", VERIFIED],
        ["item", "a2 00 8120 01 RL", UNVERIFIED],
        ["item", "a2 00 81f4 01 RL", UNVERIFIED],
        ["item", "a2 00 81f6 01 RL", UNVERIFIED],
        ["item", "a2 00 81c100 01 RL", VERIFIED],
        ["item", "a2 00 818100 01 RL", UNVERIFIED],
        ["item", "a2 00 814161 01 RL", UNVERIFIED],
        ["item", "a2 00 9f0102ff 01 RL", VERIFIED],
        ["item", "a2 00 9fff 01 RL", VERIFIED],
        ["item", "a2 00 9f 01 01 RL", UNVERIFIED],
        ["item", "a2 00 980101 01 RL", VERIFIED],
        ["item", "a2 00 9b000000000000000101 01 RL", VERIFIED],
        ["item", "a2 00 9bffffffffffffffff 01 RL", UNVERIFIED],
        ["item", "a2 00 a0 01 RL", UNVERIFIED],
        ["item", "a2 00 a10001 01 RL", UNVERIFIED],
        ["item", "a2 00 f6 01 RL", UNVERIFIED],
        ["item", "a2 00 00 01 RL", UNVERIFIED],
        ["item", "a2 00 c14161 01 RL", VERIFIED],
        ["item", "a2 00 c18101 01 RL", VERIFIED],
        ["item", "a2 00 5b0000000000000001 61 01 RL", VERIFIED],
        ["item", "a2 00 5bffffffffffffffff 01 RL", UNVERIFIED],
        ["item", "a2 00 7b0000000000000001 61 01 RL", VERIFIED],
        ["item", "a2 00 5820 00*32 01 RL", VERIFIED],
        ["item", "a2 00 811f 01 RL", UNVERIFIED],
      ]),
      "",
    );
  });

  test("item content type forms verify exactly when cbor_decode reads them", () => {
    assert.stringEquals(
      diverging([
        ["item", "a3 00 4161 01 RL 02 00", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 01", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 02", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 03", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 04", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 17", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 1803", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 1b0000000000000003", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 20", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 644e6f6e65", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 646e6f6e65", UNVERIFIED],
        [
          "item",
          "a3 00 4161 01 RL 02 706170706c69636174696f6e2f6a736f6e",
          VERIFIED,
        ],
        [
          "item",
          "a3 00 4161 01 RL 02 706170706c69636174696f6e2f63626f72",
          VERIFIED,
        ],
        [
          "item",
          "a3 00 4161 01 RL 02 78186170706c69636174696f6e2f6f637465742d73747265616d",
          VERIFIED,
        ],
        ["item", "a3 00 4161 01 RL 02 646a736f6e", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 444e6f6e65", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 7f 624e6f 626e65 ff", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 c100", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 c1644e6f6e65", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 a1 00 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 a1 03 f7", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 a1 644e6f6e65 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 a1 04 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 a1 00 00", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 a1 00 f4", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 a1 00 c1f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 a1 c100 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 82 00 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 82 644e6f6e65 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 82 00 f7", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 82 00 c1f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 82 c100 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 82 00 00", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 81 00", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 80", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 83 00 f6 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 9f 00 f6 ff", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 9f 00 ff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 9f 00 f6 f6 ff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 9802 00 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 02 a2 00 f6 01 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 b801 00 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 bf 00 f6 ff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 a0", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 f4", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 c1 a1 00 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 c1 82 00 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 4161", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 61ff", UNVERIFIED],
        ["item", "a4 00 4161 01 RL 02 a2 00 f6 05 f6", UNVERIFIED],
        ["item", "a4 00 4161 01 RL 02 b802 00 f6 05 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 a1 00 16", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 a1 00 17", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 82 00 17", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 1f", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 a1 00 f5", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 82 00 f5", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 9f 00 f5 ff", UNVERIFIED],
      ]),
      "",
    );
  });

  test("item content encoding forms verify exactly when cbor_decode reads them", () => {
    assert.stringEquals(
      diverging([
        ["item", "a3 00 4161 01 RL 03 00", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 01", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 02", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 03", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 1802", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 1b0000000000000002", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 20", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 646e6f6e65", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 686964656e74697479", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 676465666c617465", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 644e6f6e65", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 674445464c415445", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 446e6f6e65", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 476465666c617465", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 7f 63646566 646c617465 ff", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 c102", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 a1 02 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 a1 676465666c617465 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 a1 03 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 82 02 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 82 676465666c617465 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 9f 02 f6 ff", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 81 02", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 a0", UNVERIFIED],
        ["item", "bf 00 4161 01 RL 03 9f 00 f6 f6 ff", UNVERIFIED],
        ["item", "a4 00 4161 01 RL 03 83 00 f6 05 00", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 1f", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 a1 01 f5", UNVERIFIED],
      ]),
      "",
    );
  });

  test("item content language forms verify exactly when cbor_decode reads them", () => {
    assert.stringEquals(
      diverging([
        ["item", "a3 00 4161 01 RL 04 00", VERIFIED],
        ["item", "a3 00 4161 01 RL 04 01", VERIFIED],
        ["item", "a3 00 4161 01 RL 04 02", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 04 646e6f6e65", VERIFIED],
        ["item", "a3 00 4161 01 RL 04 62656e", VERIFIED],
        ["item", "a3 00 4161 01 RL 04 62454e", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 04 42656e", VERIFIED],
        ["item", "a3 00 4161 01 RL 04 7f 6165 616e ff", VERIFIED],
        ["item", "a3 00 4161 01 RL 04 c101", VERIFIED],
        ["item", "a3 00 4161 01 RL 04 a1 01 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 04 a1 62656e f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 04 82 01 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 04 20", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 04 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 04 a1 01 f5", UNVERIFIED],
      ]),
      "",
    );
  });

  test("item schema forms verify exactly when cbor_decode reads them", () => {
    assert.stringEquals(
      diverging([
        ["item", "a3 00 4161 01 RL SK 6161", VERIFIED],
        ["item", "a3 00 4161 01 RL SK 60", VERIFIED],
        ["item", "a3 00 4161 01 RL SK 4161", VERIFIED],
        ["item", "a3 00 4161 01 RL SK 40", VERIFIED],
        ["item", "a3 00 4161 01 RL SK 41ff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL SK 61ff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL SK 7f 6161 ff", VERIFIED],
        ["item", "a3 00 4161 01 RL SK 5f 4161 ff", VERIFIED],
        ["item", "a3 00 4161 01 RL SK 5f 41c3 41a9 ff", VERIFIED],
        ["item", "a3 00 4161 01 RL SK 7f 61c3 61a9 ff", VERIFIED],
        ["item", "a3 00 4161 01 RL SK c16161", VERIFIED],
        ["item", "a3 00 4161 01 RL SK 01", UNVERIFIED],
        ["item", "a3 00 4161 01 RL SK f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL SK 80", UNVERIFIED],
        ["item", "a3 00 4161 01 RL SK a0", UNVERIFIED],
        ["item", "a3 00 4161 01 RL SK 816161", UNVERIFIED],
      ]),
      "",
    );
  });

  test("a name preimage verifies in every payload form cbor_decode reads", () => {
    assert.stringEquals(
      diverging([
        ["name", "a2 00 4f NP 01 NM", VERIFIED],
        ["name", "a2 00 6f NP 01 NM", VERIFIED],
        [
          "name",
          "a2 00 5f 47737430782e7262 4861632e75732e7631 ff 01 NM",
          VERIFIED,
        ],
        [
          "name",
          "a2 00 7f 67737430782e7262 6861632e75732e7631 ff 01 NM",
          VERIFIED,
        ],
        ["name", "a2 00 5f 4f NP 40 ff 01 NM", VERIFIED],
        [
          "name",
          "a2 00 8f 1873 1874 1830 1878 182e 1872 1862 1861 1863 182e 1875 1873 182e 1876 1831 01 NM",
          VERIFIED,
        ],
        [
          "name",
          "a2 00 9f 1873 1874 1830 1878 182e 1872 1862 1861 1863 182e 1875 1873 182e 1876 1831 ff 01 NM",
          VERIFIED,
        ],
        [
          "name",
          "a2 00 8f 1873 1874 1830 1878 182e 1872 1862 1861 1863 182e 1875 1873 182e 1876 c11831 01 NM",
          VERIFIED,
        ],
        ["name", "a2 00 c1 4f NP 01 NM", VERIFIED],
        ["name", "c1 a2 00 4f NP 01 NM", VERIFIED],
        ["name", "a2 01 NM 00 4f NP", VERIFIED],
        ["name", "bf 00 4f NP 01 NM ff", VERIFIED],
        ["name", "a2 00 4f NP 01 c1 NM", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 05 00", VERIFIED],
        ["name", "a6 00 4f NP 01 NM 02 00 03 01 04 01 SK 6161", VERIFIED],
        ["name", "a2 00 4f NP 01 NM a2 00 6f NP 01 NM", VERIFIED],
      ]),
      "",
    );
  });

  test("a name preimage verifies exactly when cbor_decode reads it unencoded", () => {
    assert.stringEquals(
      diverging([
        ["name", "a3 00 4f NP 01 NM 03 00", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 01", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 02", UNVERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 03", UNVERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 1801", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 1b0000000000000001", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 1b0000000000000002", UNVERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 20", UNVERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 646e6f6e65", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 686964656e74697479", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 676465666c617465", UNVERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 644e6f6e65", UNVERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 446e6f6e65", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 486964656e74697479", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 476465666c617465", UNVERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 7f 626e6f 626e65 ff", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 5f 426e6f 426e65 ff", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 c100", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 c101", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 c102", UNVERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 c1646e6f6e65", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 a1 00 f6", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 a1 01 f7", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 a1 02 f6", UNVERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 a1 646e6f6e65 f6", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 a1 686964656e74697479 f6", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 a1 676465666c617465 f6", UNVERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 a1 c101 c1f6", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 82 00 f6", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 82 01 f6", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 82 02 f6", UNVERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 82 686964656e74697479 f6", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 9f 01 f6 ff", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 9802 01 f6", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 81 01", UNVERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 f6", UNVERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 a0", UNVERIFIED],
        ["name", "a2 00 4f NP 01 NM a3 00 4f NP 01 NM 03 01", VERIFIED],
        ["name", "a2 00 4f NP 01 NM a3 00 4f NP 01 NM 03 02", UNVERIFIED],
      ]),
      "",
    );
  });

  test("a document verifies only whole, under its own prefix", () => {
    assert.stringEquals(
      diverging([
        ["doc", "P NAME TYPE", VERIFIED],
        ["doc", "NAME TYPE", UNVERIFIED],
        ["doc", "ff0a89c674ee7875 NAME TYPE", UNVERIFIED],
        ["doc", "P P NAME TYPE", UNVERIFIED],
        ["doc", "P NAME P TYPE", UNVERIFIED],
        ["doc", "P NAME TYPE ff", UNVERIFIED],
        ["doc", "P NAME TYPE 00", UNVERIFIED],
        ["doc", "P NAME TYPE f6", UNVERIFIED],
        ["doc", "P NAME TYPE a0", UNVERIFIED],
        ["doc", "P NAME TYPE a20041", UNVERIFIED],
        ["doc", "P NAME TYPE a2004161", UNVERIFIED],
        ["doc", "P NAME TYPE a2004161 01", UNVERIFIED],
        ["doc", "P NAME TYPE c1", UNVERIFIED],
        ["doc", "P NAME TYPE 5f", UNVERIFIED],
        ["doc", "P NAME TYPE bf", UNVERIFIED],
        ["doc", "P NAME TYPE 18", UNVERIFIED],
        ["doc", "P NAME TYPE 1900", UNVERIFIED],
        ["doc", "P NAME TYPE 9f", UNVERIFIED],
        ["doc", "P NAME TYPE a100", UNVERIFIED],
        ["doc", "P NAME TYPE a3004161 01 RL 05 9f", UNVERIFIED],
        ["doc", "P NAME TYPE a3004161 01 RL 05 5f4161", UNVERIFIED],
        ["doc", "P NAME TYPE a3004161 01 RL 05 1900", UNVERIFIED],
        ["doc", "P NAME TYPE a2004161 01 1b0000000000000001", VERIFIED],
        ["doc", "P a2004161 01 1b0000000000000001", UNVERIFIED],
        ["doc", "P NAME a2004161 01 1b0000000000000001 TYPE", VERIFIED],
        ["doc", "P NAME TYPE NAME", VERIFIED],
        ["doc", "P NAME TYPE TYPE", VERIFIED],
        ["doc", "P NAME a2004761646472657373011bffcdb2cc1b1d53", UNVERIFIED],
        ["doc", "P NAME TYPE a3004161 01 RL 05 4161", VERIFIED],
        ["doc", "P NAME TYPE a3004161 01 RL 05 6161", VERIFIED],
        ["doc", "P NAME TYPE a2 01 RL 00 4161", VERIFIED],
        ["doc", "P NAME TYPE a3004161 01 RL 05 82 00 00", VERIFIED],
        ["doc", "P NAME TYPE a3004161 01 RL 05 a1 00 00", VERIFIED],
        ["doc", "P NAME TYPE a3004161 01 RL 03", UNVERIFIED],
        ["doc", "P NAME TYPE a3004161 01 RL 03 a1", UNVERIFIED],
        ["doc", "P NAME TYPE a3004161 01 RL 03 82", UNVERIFIED],
        ["doc", "P NAME TYPE a3004161 01 RL 03 c1", UNVERIFIED],
        ["doc", "P NAME TYPE a3004161 01 RL 02", UNVERIFIED],
        ["doc", "P NAME TYPE a3004161 01 RL 04", UNVERIFIED],
      ]),
      "",
    );
  });

  test("every head argument up to 2^64-1 verifies exactly when cbor_decode reads it", () => {
    assert.stringEquals(
      diverging([
        ["value", "1bfffffffffffffffe", VERIFIED],
        ["value", "1b8000000000000000", VERIFIED],
        ["value", "1b7fffffffffffffff", VERIFIED],
        ["value", "1b0000000100000000", VERIFIED],
        ["value", "1bffffffff00000000", VERIFIED],
        ["value", "3bfffffffffffffffe", VERIFIED],
        ["value", "3b0000000100000000", VERIFIED],
        ["value", "fbffffffffffffffff", VERIFIED],
        ["value", "81 1bffffffffffffffff", VERIFIED],
        ["value", "81 3bffffffffffffffff", VERIFIED],
        ["value", "81 fbffffffffffffffff", VERIFIED],
        ["value", "81 dbffffffffffffffff 00", VERIFIED],
        ["value", "81 5bffffffffffffffff", UNVERIFIED],
        ["value", "81 7bffffffffffffffff", UNVERIFIED],
        ["value", "81 9bffffffffffffffff", UNVERIFIED],
        ["value", "81 bbffffffffffffffff", UNVERIFIED],
        ["value", "82 1bffffffffffffffff 3bffffffffffffffff", VERIFIED],
        ["value", "9f 1bffffffffffffffff ff", VERIFIED],
        ["value", "9f 3bffffffffffffffff ff", VERIFIED],
        ["value", "9f dbffffffffffffffff 00 ff", VERIFIED],
        ["value", "9bfffffffffffffffe", UNVERIFIED],
        ["value", "9b0000000100000001 00", UNVERIFIED],
        ["value", "a1 00 1bffffffffffffffff", VERIFIED],
        ["value", "a1 00 3bffffffffffffffff", VERIFIED],
        ["value", "a1 1bffffffffffffffff 1bffffffffffffffff", VERIFIED],
        ["value", "a1 3bffffffffffffffff 3bffffffffffffffff", VERIFIED],
        ["value", "a2 1bffffffffffffffff 00 1bfffffffffffffffe 00", VERIFIED],
        ["value", "a2 1bffffffffffffffff 00 1bffffffffffffffff 00", VERIFIED],
        ["value", "bf 1bffffffffffffffff 1bffffffffffffffff ff", VERIFIED],
        ["value", "bf 1bffffffffffffffff ff", UNVERIFIED],
        ["value", "a1 dbffffffffffffffff 00 00", VERIFIED],
        ["value", "a1 00 dbffffffffffffffff 00", VERIFIED],
        ["value", "a1 fbffffffffffffffff 00", VERIFIED],
        ["value", "a1 00 fbffffffffffffffff", VERIFIED],
        ["value", "a1 00 5bffffffffffffffff", UNVERIFIED],
        ["value", "a1 00 7bffffffffffffffff", UNVERIFIED],
        ["value", "a1 00 9bffffffffffffffff", UNVERIFIED],
        ["value", "a1 00 bbffffffffffffffff", UNVERIFIED],
        ["value", "bbfffffffffffffffe", UNVERIFIED],
        ["value", "bb0000000100000001 00 00", UNVERIFIED],
        ["value", "dbffffffffffffffff 1bffffffffffffffff", VERIFIED],
        ["value", "dbffffffffffffffff 3bffffffffffffffff", VERIFIED],
        ["value", "dbffffffffffffffff dbffffffffffffffff 00", VERIFIED],
        ["value", "dbffffffffffffffff 80", VERIFIED],
        ["value", "dbffffffffffffffff a0", VERIFIED],
        ["value", "dbffffffffffffffff 9f ff", VERIFIED],
        ["value", "dbffffffffffffffff 4161", VERIFIED],
        ["value", "dbffffffffffffffff fbffffffffffffffff", VERIFIED],
        ["value", "dbffffffffffffffff 9bffffffffffffffff", UNVERIFIED],
        ["value", "dbffffffffffffffff ff", UNVERIFIED],
        ["value", "dbfffffffffffffffe 00", VERIFIED],
        ["value", "db8000000000000000 00", VERIFIED],
        ["value", "db7fffffffffffffff 00", VERIFIED],
        ["value", "dbffffffffffffffff*125 00", VERIFIED],
        ["value", "dbffffffffffffffff*126 00", VERIFIED],
        ["value", "dbffffffffffffffff*127 00", UNVERIFIED],
        ["value", "81*125 dbffffffffffffffff 00", VERIFIED],
        ["value", "81*126 dbffffffffffffffff 00", UNVERIFIED],
        ["value", "5bfffffffffffffffe", UNVERIFIED],
        ["value", "5b0000000100000001 61", UNVERIFIED],
        ["value", "7b0000000100000001 61", UNVERIFIED],
        ["value", "5f 5bffffffffffffffff ff", UNVERIFIED],
        ["value", "7f 7bffffffffffffffff ff", UNVERIFIED],
        ["value", "5f 5b0000000100000001 61 ff", UNVERIFIED],
        ["value", "7f 7b0000000100000001 61 ff", UNVERIFIED],
        [
          "item",
          "a3 00 4161 01 RL 1bffffffffffffffff 1bffffffffffffffff",
          VERIFIED,
        ],
        [
          "item",
          "a3 00 4161 01 RL 1bffffffffffffffff 3bffffffffffffffff",
          VERIFIED,
        ],
        [
          "item",
          "a3 00 4161 01 RL 1bffffffffffffffff dbffffffffffffffff 00",
          VERIFIED,
        ],
        [
          "item",
          "a3 00 4161 01 RL 1bffffffffffffffff fbffffffffffffffff",
          VERIFIED,
        ],
        ["item", "a3 00 4161 01 RL 1bffffffffffffffff 9f ff", VERIFIED],
        ["item", "a3 00 4161 01 RL 1bffffffffffffffff 5f ff", VERIFIED],
        [
          "item",
          "a3 00 4161 01 RL 1bffffffffffffffff 5bffffffffffffffff",
          UNVERIFIED,
        ],
        [
          "item",
          "a3 00 4161 01 RL 1bffffffffffffffff 9bffffffffffffffff",
          UNVERIFIED,
        ],
        [
          "item",
          "a3 00 4161 01 RL 1bffffffffffffffff bbffffffffffffffff",
          UNVERIFIED,
        ],
        ["item", "a3 00 4161 01 RL 1bffffffffffffffff ff", UNVERIFIED],
        [
          "item",
          "a4 00 4161 01 RL 1bffffffffffffffff 00 1bffffffffffffffff 00",
          UNVERIFIED,
        ],
        [
          "item",
          "a4 00 4161 01 RL 1bffffffffffffffff 00 1bfffffffffffffffe 00",
          VERIFIED,
        ],
        ["item", "a4 00 4161 01 RL 1bffffffffffffffff 00 05 00", VERIFIED],
        ["item", "a3 00 4161 01 RL 1bfffffffffffffffe 00", VERIFIED],
        ["item", "a3 00 4161 01 RL 1b8000000000000000 00", VERIFIED],
        ["item", "a3 00 4161 01 RL 1b0000000100000000 00", VERIFIED],
        ["item", "a3 00 4161 01 RL 1b0000000100000001 00", VERIFIED],
        ["item", "a3 00 4161 01 RL 1b0000000100000002 04", VERIFIED],
        ["item", "a3 00 4161 01 RL 1b0000000100000003 03", VERIFIED],
        ["item", "a3 00 4161 01 RL 3bfffffffffffffffe 00", UNVERIFIED],
        ["item", "a2 dbffffffffffffffff 00 4161 01 RL", VERIFIED],
        ["item", "a2 00 4161 dbffffffffffffffff 01 RL", VERIFIED],
        [
          "item",
          "a3 00 4161 01 RL dbffffffffffffffff 1bffffffffffffffff 00",
          VERIFIED,
        ],
        [
          "item",
          "a3 00 4161 01 RL dbffffffffffffffff 3bffffffffffffffff 00",
          UNVERIFIED,
        ],
        ["item", "bf 00 4161 01 RL 1bffffffffffffffff 00 ff", VERIFIED],
        ["item", "bf 00 4161 01 RL 1bffffffffffffffff ff", UNVERIFIED],
        ["item", "bbffffffffffffffff 00 4161 01 RL", UNVERIFIED],
        ["item", "bbfffffffffffffffe 00 4161 01 RL", UNVERIFIED],
        ["item", "bb0000000100000002 00 4161 01 RL", UNVERIFIED],
        ["item", "9bffffffffffffffff 00 4161 01 RL", UNVERIFIED],
        ["item", "1bffffffffffffffff", UNVERIFIED],
        ["item", "3bffffffffffffffff", UNVERIFIED],
        ["item", "5bffffffffffffffff", UNVERIFIED],
        ["item", "7bffffffffffffffff", UNVERIFIED],
        ["item", "fbffffffffffffffff", UNVERIFIED],
        [
          "item",
          "dbffffffffffffffff dbffffffffffffffff a2 00 4161 01 RL",
          VERIFIED,
        ],
        ["item", "dbffffffffffffffff*126 a2 00 4161 01 RL", VERIFIED],
        ["item", "dbffffffffffffffff*127 a2 00 4161 01 RL", UNVERIFIED],
        ["item", "a2 00 4161 01 1bffffffffffffffff", VERIFIED],
        ["item", "a2 01 1bffffffffffffffff 00 4161", VERIFIED],
        [
          "item",
          "a2 00 4161 01 dbffffffffffffffff 1bffffffffffffffff",
          VERIFIED,
        ],
        ["item", "a2 00 4161 01 dbffffffffffffffff RL", VERIFIED],
        ["item", "a2 00 4161 01 1bfffffffffffffffe", VERIFIED],
        ["item", "a2 00 4161 01 1b8000000000000000", VERIFIED],
        ["item", "a2 00 4161 01 3bffffffffffffffff", UNVERIFIED],
        ["item", "a2 00 4161 01 fbffffffffffffffff", UNVERIFIED],
        ["item", "a2 00 4161 01 5bffffffffffffffff", UNVERIFIED],
        ["item", "a2 00 4161 01 9bffffffffffffffff", UNVERIFIED],
        [
          "item",
          "a3 00 4161 01 1bffffffffffffffff 05 1bffffffffffffffff",
          VERIFIED,
        ],
        [
          "item",
          "a3 00 4161 01 1bffffffffffffffff 1bffffffffffffffff 00",
          VERIFIED,
        ],
        ["item", "a3 00 4161 01 1bffffffffffffffff 03 03", UNVERIFIED],
        [
          "item",
          "a3 00 4161 01 1bffffffffffffffff 03 1bffffffffffffffff",
          UNVERIFIED,
        ],
        [
          "item",
          "a3 00 4161 01 1bffffffffffffffff 02 1bffffffffffffffff",
          UNVERIFIED,
        ],
        ["item", "a3 00 4161 01 1bffffffffffffffff 01 RL", UNVERIFIED],
        ["item", "a2 00 61ff 01 1bffffffffffffffff", UNVERIFIED],
        [
          "item",
          "a2 00 4161 01 1bffffffffffffffff a2 00 4161 01 1bffffffffffffffff",
          VERIFIED,
        ],
        ["item", "a2 00 4161 01 1bffffffffffffffff a2 00 4161 01 RL", VERIFIED],
        ["item", "a2 00 4161 01 1bffffffffffffffff 00", UNVERIFIED],
        ["item", "a2 00 7bffffffffffffffff 01 RL", UNVERIFIED],
        ["item", "a2 00 81 1bffffffffffffffff 01 RL", UNVERIFIED],
        ["item", "a2 00 81 3bffffffffffffffff 01 RL", UNVERIFIED],
        ["item", "a2 00 81 fbffffffffffffffff 01 RL", UNVERIFIED],
        ["item", "a2 00 81 dbffffffffffffffff 01 01 RL", VERIFIED],
        ["item", "a2 00 81 1b0000000100000001 01 RL", UNVERIFIED],
        ["item", "a2 00 81 1bffffffffffffff01 01 RL", UNVERIFIED],
        ["item", "a2 00 9f 1bffffffffffffffff ff 01 RL", UNVERIFIED],
        ["item", "a2 00 9bfffffffffffffffe 01 RL", UNVERIFIED],
        ["item", "a2 00 9b0000000100000001 01 01 RL", UNVERIFIED],
        ["item", "a2 00 5f 5bffffffffffffffff ff 01 RL", UNVERIFIED],
        ["item", "a2 00 7f 7bffffffffffffffff ff 01 RL", UNVERIFIED],
        ["item", "a2 00 5b0000000100000001 61 01 RL", UNVERIFIED],
        ["item", "a2 00 5f 5b0000000100000001 61 ff 01 RL", UNVERIFIED],
        ["item", "a2 00 dbffffffffffffffff 4161 01 RL", VERIFIED],
        [
          "item",
          "a2 00 dbffffffffffffffff 81 dbffffffffffffffff 01 01 RL",
          VERIFIED,
        ],
        ["item", "a2 00 5f dbffffffffffffffff 4161 ff 01 RL", UNVERIFIED],
        ["item", "a2 00 1bffffffffffffffff 01 RL", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 02 1bffffffffffffffff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 1bffffffffffffffff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 04 1bffffffffffffffff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 1b0000000100000000", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 1b0000000100000002", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 3bffffffffffffffff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 fbffffffffffffffff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 dbffffffffffffffff 02", VERIFIED],
        [
          "item",
          "a3 00 4161 01 RL 03 dbffffffffffffffff 676465666c617465",
          VERIFIED,
        ],
        ["item", "a3 00 4161 01 RL 03 5bffffffffffffffff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 7bffffffffffffffff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 a1 1bffffffffffffffff f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 a1 dbffffffffffffffff 02 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 a1 02 dbffffffffffffffff f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 a1 02 fbffffffffffffffff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 a1 02 1bffffffffffffffff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 82 1bffffffffffffffff f6", UNVERIFIED],
        [
          "item",
          "a3 00 4161 01 RL 03 82 dbffffffffffffffff 02 dbffffffffffffffff f6",
          VERIFIED,
        ],
        ["item", "a3 00 4161 01 RL 03 82 02 fbffffffffffffffff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 9bffffffffffffffff 02 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 9b0000000000000002 02 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL 03 9b0000000100000002 02 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 bbffffffffffffffff 02 f6", UNVERIFIED],
        ["item", "a3 00 4161 01 RL 03 bb0000000000000001 02 f6", UNVERIFIED],
        [
          "item",
          "a3 00 4161 01 RL 03 9f 02 dbffffffffffffffff f6 ff",
          VERIFIED,
        ],
        [
          "item",
          "a3 00 4161 01 RL 02 a1 dbffffffffffffffff 00 dbffffffffffffffff f6",
          VERIFIED,
        ],
        ["item", "a3 00 4161 01 RL 04 82 dbffffffffffffffff 01 f6", VERIFIED],
        ["item", "a3 00 4161 01 RL SK 7bffffffffffffffff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL SK 5bffffffffffffffff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL SK dbffffffffffffffff 6161", VERIFIED],
        ["item", "a3 00 4161 01 RL SK 1bffffffffffffffff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL SK 7f 7bffffffffffffffff ff", UNVERIFIED],
        ["item", "a3 00 4161 01 RL dbffffffffffffffff SK 6161", VERIFIED],
        [
          "name",
          "a2 00 4f NP 01 NM a2 00 4161 01 1bffffffffffffffff",
          VERIFIED,
        ],
        ["name", "a3 00 4f NP 01 NM 1bffffffffffffffff 00", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 1bffffffffffffffff", UNVERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 dbffffffffffffffff 01", VERIFIED],
        ["name", "a3 00 4f NP 01 NM 03 dbffffffffffffffff 02", UNVERIFIED],
        [
          "name",
          "a3 00 4f NP 01 NM 03 a1 dbffffffffffffffff 01 dbffffffffffffffff f6",
          VERIFIED,
        ],
        ["name", "a2 00 dbffffffffffffffff 4f NP 01 NM", VERIFIED],
        ["name", "a2 00 4f NP 01 dbffffffffffffffff NM", VERIFIED],
        ["name", "dbffffffffffffffff a2 00 4f NP 01 NM", VERIFIED],
        [
          "name",
          "a2 00 8f 1873 1874 1830 1878 182e 1872 1862 1861 1863 182e 1875 1873 182e 1876 dbffffffffffffffff 1831 01 NM",
          VERIFIED,
        ],
        ["doc", "P a2004161 01 1bffffffffffffffff", UNVERIFIED],
        ["doc", "P NAME a2004161 01 1bffffffffffffffff TYPE", VERIFIED],
        ["doc", "P a2004161 01 1bffffffffffffffff NAME TYPE", VERIFIED],
        ["doc", "P NAME TYPE dbffffffffffffffff", UNVERIFIED],
        ["doc", "P NAME TYPE 1bffffffffffffffff", UNVERIFIED],
      ]),
      "",
    );
  });
});

describe("ConfigRegistryV5 delegates", () => {
  afterEach(clearStore);

  test("Approved then Revoked move an approval under the V5 registry", () => {
    handleConfigRegistryV5Approved(
      changetype<Approved>(
        delegateChangeLog(
          Address.fromString(REGISTRY),
          Address.fromString(AUTHORITY),
          Bytes.fromHexString(US_NAME),
          Address.fromString(DELEGATE),
          300,
          4,
        ),
      ),
    );
    let id = delegateId(REGISTRY, AUTHORITY, US_NAME, DELEGATE);
    assert.fieldEquals("RegistryDelegate", id, "approved", "true");
    assert.fieldEquals("RegistryDelegate", id, "registry", REGISTRY);
    assert.fieldEquals("Contract", REGISTRY, "kind", "CONFIG_REGISTRY_V5");

    handleConfigRegistryV5Revoked(
      changetype<Revoked>(
        delegateChangeLog(
          Address.fromString(REGISTRY),
          Address.fromString(AUTHORITY),
          Bytes.fromHexString(US_NAME),
          Address.fromString(DELEGATE),
          400,
          2,
        ),
      ),
    );
    assert.fieldEquals("RegistryDelegate", id, "approved", "false");
    assert.fieldEquals("RegistryDelegate", id, "approvedAtBlock", "300");
    assert.fieldEquals("RegistryDelegate", id, "revokedAtBlock", "400");
    assert.entityCount("RegistryDelegateChange", 2);
  });
});

function unscoped(approved: boolean, blockNumber: i32, logIndex: i32): void {
  let log = unscopedDelegateChangeLog(
    Address.fromString(REGISTRY),
    Address.fromString(AUTHORITY),
    Address.fromString(DELEGATE),
    blockNumber,
    logIndex,
  );
  if (approved) {
    handleConfigRegistryV5ApprovedUnscoped(changetype<ApprovedUnscoped>(log));
  } else {
    handleConfigRegistryV5RevokedUnscoped(changetype<RevokedUnscoped>(log));
  }
}

describe("ConfigRegistryV5 unscoped delegates", () => {
  afterEach(clearStore);

  test("ApprovedUnscoped then RevokedUnscoped move an unscoped approval", () => {
    unscoped(true, 300, 4);
    let id = REGISTRY.concat(AUTHORITY.slice(2)).concat(DELEGATE.slice(2));
    assert.fieldEquals("RegistryUnscopedDelegate", id, "approved", "true");
    assert.fieldEquals("RegistryUnscopedDelegate", id, "registry", REGISTRY);
    assert.fieldEquals("RegistryUnscopedDelegate", id, "account", AUTHORITY);
    assert.fieldEquals("RegistryUnscopedDelegate", id, "delegate", DELEGATE);
    assert.fieldEquals("Contract", REGISTRY, "kind", "CONFIG_REGISTRY_V5");

    unscoped(false, 400, 2);
    assert.fieldEquals("RegistryUnscopedDelegate", id, "approved", "false");
    assert.fieldEquals(
      "RegistryUnscopedDelegate",
      id,
      "approvedAtBlock",
      "300",
    );
    assert.fieldEquals("RegistryUnscopedDelegate", id, "revokedAtBlock", "400");
    assert.entityCount("RegistryUnscopedDelegateChange", 2);
    assert.fieldEquals(
      "RegistryUnscopedDelegateChange",
      mockRowId(4),
      "approved",
      "true",
    );
    assert.entityCount("RegistryDelegate", 0);
  });

  test("an unscoped change row records its log's block and transaction", () => {
    unscoped(false, 400, 2);

    let row = mockRowId(2);
    assert.fieldEquals(
      "RegistryUnscopedDelegateChange",
      row,
      "blockNumber",
      "400",
    );
    assert.fieldEquals(
      "RegistryUnscopedDelegateChange",
      row,
      "blockTimestamp",
      "4800",
    );
    assert.fieldEquals(
      "RegistryUnscopedDelegateChange",
      row,
      "transactionHash",
      TX_HASH.toHexString(),
    );
    assert.fieldEquals(
      "RegistryUnscopedDelegateChange",
      row,
      "transactionFrom",
      TX_FROM.toHexString(),
    );
    assert.fieldEquals("RegistryUnscopedDelegateChange", row, "logIndex", "2");
  });

  test("an unscoped approval and revocation record their logs' block timestamps", () => {
    unscoped(true, 300, 4);
    unscoped(false, 400, 2);

    let id = REGISTRY.concat(AUTHORITY.slice(2)).concat(DELEGATE.slice(2));
    assert.fieldEquals(
      "RegistryUnscopedDelegate",
      id,
      "approvedAtTimestamp",
      "3600",
    );
    assert.fieldEquals(
      "RegistryUnscopedDelegate",
      id,
      "revokedAtTimestamp",
      "4800",
    );
  });
});
