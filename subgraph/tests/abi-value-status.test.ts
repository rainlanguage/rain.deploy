// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd

import { assert, describe, test } from "matchstick-as";
import { Bytes } from "@graphprotocol/graph-ts";
import { ConfigValueStatus, configValueStatus } from "../src/configregistry";

/** `cast abi-encode "f(uint8[9])" "[1,2,3,4,5,6,7,8,9]"`. */
const UINT8_X9_VALUE =
  "0x000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000009";
/** `cast abi-encode "f(uint8[10])" "[1,2,3,4,5,6,7,8,9,10]"`. */
const UINT8_X10_VALUE =
  "0x000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000009000000000000000000000000000000000000000000000000000000000000000a";
/** `cast abi-encode "f(uint160)" 1461501637330902918203684832716283019655932542975` (2^160 - 1). */
const UINT160_MAX_VALUE =
  "0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff";
/** `cast abi-encode "f(uint256)" 1000000`. */
const UINT256_VALUE =
  "0x00000000000000000000000000000000000000000000000000000000000f4240";
/** `cast abi-encode "f(uint56)" 1`. */
const UINT56_VALUE =
  "0x0000000000000000000000000000000000000000000000000000000000000001";
/** `cast abi-encode "f(uint248)" 1000000`. */
const UINT248_VALUE =
  "0x00000000000000000000000000000000000000000000000000000000000f4240";
/** `cast abi-encode "f(bytes32)" 0xb046f6b844b680f0dcfc7a139f126e7e13d58023f8d26c15e3229eb4fff8499f`. */
const BYTES32_VALUE =
  "0xb046f6b844b680f0dcfc7a139f126e7e13d58023f8d26c15e3229eb4fff8499f";
/** `cast abi-encode "f(bytes1)" 0xff`. */
const BYTES1_VALUE =
  "0xff00000000000000000000000000000000000000000000000000000000000000";
/** `cast abi-encode "f(bytes4)" 0xdeadbeef`. */
const BYTES4_VALUE =
  "0xdeadbeef00000000000000000000000000000000000000000000000000000000";
/** `BYTES4_VALUE` with byte 4, the first tail byte, set. */
const BYTES4_BYTE_4_VALUE =
  "0xdeadbeef01000000000000000000000000000000000000000000000000000000";
/** `cast abi-encode "f(uint8)" 255`. */
const UINT8_MAX_VALUE =
  "0x00000000000000000000000000000000000000000000000000000000000000ff";
/** `UINT8_MAX_VALUE` with byte 0 set. */
const UINT8_BYTE_0_VALUE =
  "0x01000000000000000000000000000000000000000000000000000000000000ff";
/** `cast abi-encode "f(int16)" 255`: the sign byte, byte 30, is clear. */
const INT16_255_VALUE =
  "0x00000000000000000000000000000000000000000000000000000000000000ff";
/** `cast abi-encode "f(int8)" -- -128`. */
const INT8_MIN_VALUE =
  "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff80";
/** `cast abi-encode "f(int8)" -- -1` with byte 30 cleared. */
const INT8_MINUS_1_BYTE_30_VALUE =
  "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00ff";
/** `cast abi-encode "f(int8)" -- -1` with byte 0 cleared. */
const INT8_MINUS_1_BYTE_0_VALUE =
  "0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
/** `cast abi-encode "f(bool)" true` with byte 30 set. */
const BOOL_BYTE_30_VALUE =
  "0x0000000000000000000000000000000000000000000000000000000000000101";
/** `cast abi-encode "f(address)" 0x0b300013cd54a8f1ac40981f80faaa18b8cc1e4c`. */
const ADDRESS_VALUE =
  "0x0000000000000000000000000b300013cd54a8f1ac40981f80faaa18b8cc1e4c";
/** `ADDRESS_VALUE` with byte 11, the lowest padding byte, set. */
const ADDRESS_BYTE_11_VALUE =
  "0x0000000000000000000000010b300013cd54a8f1ac40981f80faaa18b8cc1e4c";
/** `cast abi-encode "f(address,uint256)" 0x0b300013cd54a8f1ac40981f80faaa18b8cc1e4c 1000000`. */
const ADDRESS_UINT256_VALUE =
  "0x0000000000000000000000000b300013cd54a8f1ac40981f80faaa18b8cc1e4c00000000000000000000000000000000000000000000000000000000000f4240";
/** `cast abi-encode "f(uint256[2])" "[1000000,1000000]"`. */
const UINT256_X2_VALUE =
  "0x00000000000000000000000000000000000000000000000000000000000f424000000000000000000000000000000000000000000000000000000000000f4240";
/** `cast abi-encode "f((uint256[][][][],uint256[][][][]))" "([],[])"`. */
const SIBLING_ARRAYS_VALUE =
  "0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
/** `cast abi-encode "f((uint256[2],bool))" "([1000000,1000000],true)"`. */
const FIXED_ARRAY_BOOL_VALUE =
  "0x00000000000000000000000000000000000000000000000000000000000f424000000000000000000000000000000000000000000000000000000000000f42400000000000000000000000000000000000000000000000000000000000000001";
/** `cast abi-encode "f(uint256[1099511627776][16777215][])" "[]"`. */
const SATURATED_ELEMENT_ARRAY_VALUE =
  "0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000";
/** `cast abi-encode "f(string)" "st0x.rbac.us.v1"` with byte 25 of its root offset set. */
const STRING_OFFSET_BYTE_25_VALUE =
  "0x0000000000000000000000000000000000000000000000000001000000000020000000000000000000000000000000000000000000000000000000000000000f737430782e726261632e75732e76310000000000000000000000000000000000";
/** `cast abi-encode "f(string)" "st0x.rbac.us.v1"` with byte 26 of its root offset set. */
const STRING_OFFSET_BYTE_26_VALUE =
  "0x0000000000000000000000000000000000000000000000000000010000000020000000000000000000000000000000000000000000000000000000000000000f737430782e726261632e75732e76310000000000000000000000000000000000";
/** `cast abi-encode "f(string)" "st0x.rbac.us.v1"` with its first padding byte set. */
const STRING_FIRST_PADDING_VALUE =
  "0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000f737430782e726261632e75732e76310100000000000000000000000000000000";
/** `cast abi-encode "f(string)"` of 256 "a" bytes: its length word needs two bytes. */
const STRING_256_VALUE =
  "0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000010061616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161";
/** `cast abi-encode "f(string)" ""` plus a zero word, with its offset and its length each set to 0x40. */
const STRING_SKIPPED_LENGTH_VALUE =
  "0x000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000";
/** The first word of `cast abi-encode "f(uint256[])" "[]"`. */
const UINT256_ARRAY_OFFSET_ONLY_VALUE =
  "0x0000000000000000000000000000000000000000000000000000000000000020";
/** The first two words of `cast abi-encode "f(string[])" "[st0x.rbac.us.v1]"`. */
const STRING_ARRAY_NO_HEAD_VALUE =
  "0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000001";

function assertStatus(valueType: string, value: string, status: string): void {
  assert.stringEquals(
    configValueStatus(valueType, Bytes.fromHexString(value)),
    status,
  );
}

describe("ABI value type grammar", () => {
  test("uint8[9] holding nine elements is VALID", () => {
    assertStatus("uint8[9]", UINT8_X9_VALUE, ConfigValueStatus.VALID);
  });

  test("uint8[10] holding ten elements is VALID", () => {
    assertStatus("uint8[10]", UINT8_X10_VALUE, ConfigValueStatus.VALID);
  });

  test("uint160 at its maximum is VALID", () => {
    assertStatus("uint160", UINT160_MAX_VALUE, ConfigValueStatus.VALID);
  });

  test("uint8 at its maximum is VALID", () => {
    assertStatus("uint8", UINT8_MAX_VALUE, ConfigValueStatus.VALID);
  });

  test("a uint width past three digits is VALUE_NOT_DECODABLE even when it wraps to 256 in 32 bits", () => {
    assertStatus(
      "uint4294967552",
      UINT256_VALUE,
      ConfigValueStatus.VALUE_NOT_DECODABLE,
    );
  });

  test("a uint width that is not a number is VALUE_NOT_DECODABLE", () => {
    assertStatus("uinth", UINT56_VALUE, ConfigValueStatus.VALUE_NOT_DECODABLE);
  });

  test("a uint width that is not a multiple of 8 is VALUE_NOT_DECODABLE", () => {
    assertStatus(
      "uint255",
      UINT248_VALUE,
      ConfigValueStatus.VALUE_NOT_DECODABLE,
    );
  });

  test("bytes32 is VALID", () => {
    assertStatus("bytes32", BYTES32_VALUE, ConfigValueStatus.VALID);
  });

  test("bytes1 is VALID", () => {
    assertStatus("bytes1", BYTES1_VALUE, ConfigValueStatus.VALID);
  });

  test("bytes4 filling its four bytes is VALID", () => {
    assertStatus("bytes4", BYTES4_VALUE, ConfigValueStatus.VALID);
  });

  test("a fixed array closed by a paren is VALUE_NOT_DECODABLE", () => {
    assertStatus(
      "uint256[2)",
      UINT256_X2_VALUE,
      ConfigValueStatus.VALUE_NOT_DECODABLE,
    );
  });

  test("an unclosed tuple is VALUE_NOT_DECODABLE", () => {
    assertStatus(
      "(address",
      ADDRESS_VALUE,
      ConfigValueStatus.VALUE_NOT_DECODABLE,
    );
  });

  test("a close paren with no open tuple is VALUE_NOT_DECODABLE", () => {
    assertStatus(
      "address)",
      ADDRESS_VALUE,
      ConfigValueStatus.VALUE_NOT_DECODABLE,
    );
  });

  test("two types separated by a top-level comma are VALUE_NOT_DECODABLE", () => {
    assertStatus(
      "address,uint256",
      ADDRESS_UINT256_VALUE,
      ConfigValueStatus.VALUE_NOT_DECODABLE,
    );
  });

  test("tuple components separated by a space are VALUE_NOT_DECODABLE", () => {
    assertStatus(
      "(address uint256)",
      ADDRESS_UINT256_VALUE,
      ConfigValueStatus.VALUE_NOT_DECODABLE,
    );
  });

  test("two sibling components each 4 arrays deep are VALID", () => {
    assertStatus(
      "(uint256[][][][],uint256[][][][])",
      SIBLING_ARRAYS_VALUE,
      ConfigValueStatus.VALID,
    );
  });

  test("an empty array whose fixed-array element saturates the head size is VALID", () => {
    assertStatus(
      "uint256[1099511627776][16777215][]",
      SATURATED_ELEMENT_ARRAY_VALUE,
      ConfigValueStatus.VALID,
    );
  });
});

describe("ABI value canonical layout", () => {
  test("a static tuple of uint256[2] then bool is VALID", () => {
    assertStatus(
      "(uint256[2],bool)",
      FIXED_ARRAY_BOOL_VALUE,
      ConfigValueStatus.VALID,
    );
  });

  test("an address with its lowest padding byte set is VALUE_NOT_CANONICAL", () => {
    assertStatus(
      "address",
      ADDRESS_BYTE_11_VALUE,
      ConfigValueStatus.VALUE_NOT_CANONICAL,
    );
  });

  test("uint8 with its highest byte set is VALUE_NOT_CANONICAL", () => {
    assertStatus(
      "uint8",
      UINT8_BYTE_0_VALUE,
      ConfigValueStatus.VALUE_NOT_CANONICAL,
    );
  });

  test("bytes4 with its first tail byte set is VALUE_NOT_CANONICAL", () => {
    assertStatus(
      "bytes4",
      BYTES4_BYTE_4_VALUE,
      ConfigValueStatus.VALUE_NOT_CANONICAL,
    );
  });

  test("bool with byte 30 set is VALUE_NOT_CANONICAL", () => {
    assertStatus(
      "bool",
      BOOL_BYTE_30_VALUE,
      ConfigValueStatus.VALUE_NOT_CANONICAL,
    );
  });

  test("int16 255 is VALID", () => {
    assertStatus("int16", INT16_255_VALUE, ConfigValueStatus.VALID);
  });

  test("int8 -128 is VALID", () => {
    assertStatus("int8", INT8_MIN_VALUE, ConfigValueStatus.VALID);
  });

  test("int8 -1 with its lowest sign-fill byte clear is VALUE_NOT_CANONICAL", () => {
    assertStatus(
      "int8",
      INT8_MINUS_1_BYTE_30_VALUE,
      ConfigValueStatus.VALUE_NOT_CANONICAL,
    );
  });

  test("int8 -1 with its highest sign-fill byte clear is VALUE_NOT_CANONICAL", () => {
    assertStatus(
      "int8",
      INT8_MINUS_1_BYTE_0_VALUE,
      ConfigValueStatus.VALUE_NOT_CANONICAL,
    );
  });

  test("a string whose root offset has byte 25 set is VALUE_NOT_CANONICAL", () => {
    assertStatus(
      "string",
      STRING_OFFSET_BYTE_25_VALUE,
      ConfigValueStatus.VALUE_NOT_CANONICAL,
    );
  });

  test("a string whose root offset has byte 26 set is VALUE_NOT_CANONICAL", () => {
    assertStatus(
      "string",
      STRING_OFFSET_BYTE_26_VALUE,
      ConfigValueStatus.VALUE_NOT_CANONICAL,
    );
  });

  test("a 256-byte string is VALID", () => {
    assertStatus("string", STRING_256_VALUE, ConfigValueStatus.VALID);
  });

  test("a string with its first padding byte set is VALUE_NOT_CANONICAL", () => {
    assertStatus(
      "string",
      STRING_FIRST_PADDING_VALUE,
      ConfigValueStatus.VALUE_NOT_CANONICAL,
    );
  });

  test("a string whose canonical length runs past the end is VALUE_NOT_DECODABLE though its offset points at a readable one", () => {
    assertStatus(
      "string",
      STRING_SKIPPED_LENGTH_VALUE,
      ConfigValueStatus.VALUE_NOT_DECODABLE,
    );
  });

  test("a dynamic array with only its offset word is VALUE_NOT_DECODABLE", () => {
    assertStatus(
      "uint256[]",
      UINT256_ARRAY_OFFSET_ONLY_VALUE,
      ConfigValueStatus.VALUE_NOT_DECODABLE,
    );
  });

  test("a string array without its element's head is VALUE_NOT_DECODABLE", () => {
    assertStatus(
      "string[]",
      STRING_ARRAY_NO_HEAD_VALUE,
      ConfigValueStatus.VALUE_NOT_DECODABLE,
    );
  });
});
