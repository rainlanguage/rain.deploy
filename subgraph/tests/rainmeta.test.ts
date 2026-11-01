// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd

import { assert, describe, test } from "matchstick-as";
import { Bytes, crypto } from "@graphprotocol/graph-ts";
import {
  CONFIG_REGISTRY_NAME_V1,
  PreimageCheck,
  verifyPreimages,
} from "../src/lib/rainmeta";

const PREFIX = "0xff0a89c674ee7874";
const NAME_MAGIC = "011bffcdcfae6227d5e9";
const TEXT_FIRST = "a200";
const MAGIC_FIRST = "a2".concat(NAME_MAGIC).concat("00");

/**
 * Each `[body, payload, expected]` whose name preimage differs from `expected`,
 * the payload rain.metadata `RainMetaDocumentV1Item::cbor_decode` reads from
 * the prefixed body, or "null" where it rejects it. The check's key is the
 * hash of `payload`, the bytes a decoder that accepted the body would read.
 */
function diverging(cases: string[][]): string {
  let out = "";
  for (let i = 0; i < cases.length; i++) {
    let meta = Bytes.fromHexString(PREFIX.concat(cases[i][0]));
    let key = Bytes.fromByteArray(
      crypto.keccak256(Bytes.fromHexString(cases[i][1])),
    );
    let check = new PreimageCheck(CONFIG_REGISTRY_NAME_V1, key);
    let got = verifyPreimages(meta, [check]);
    let actual = got === null ? "null" : got[0].toHexString();
    if (actual != cases[i][2]) {
      out = out
        .concat(cases[i][0])
        .concat(": oracle ")
        .concat(cases[i][2])
        .concat(", subgraph ")
        .concat(actual)
        .concat("\n");
    }
  }
  return out;
}

describe("rain meta document payload decoding", () => {
  test("a text payload's three-byte e0 sequence needs a second byte of at least a0", () => {
    assert.stringEquals(
      diverging([
        [TEXT_FIRST.concat("63e09fbf").concat(NAME_MAGIC), "0xe09fbf", "null"],
        [
          TEXT_FIRST.concat("63e0a080").concat(NAME_MAGIC),
          "0xe0a080",
          "0xe0a080",
        ],
      ]),
      "",
    );
  });

  test("a text payload's four-byte f0 sequence needs a second byte of at least 90", () => {
    assert.stringEquals(
      diverging([
        [
          TEXT_FIRST.concat("64f08fbfbf").concat(NAME_MAGIC),
          "0xf08fbfbf",
          "null",
        ],
        [
          TEXT_FIRST.concat("64f0908080").concat(NAME_MAGIC),
          "0xf0908080",
          "0xf0908080",
        ],
      ]),
      "",
    );
  });

  test("a payload array whose bytes end exactly at the end of the meta is read", () => {
    assert.stringEquals(
      diverging([
        [MAGIC_FIRST.concat("83010203"), "0x010203", "0x010203"],
        [MAGIC_FIRST.concat("820102"), "0x0102", "0x0102"],
        [MAGIC_FIRST.concat("80"), "0x", "0x"],
        [MAGIC_FIRST.concat("84010203"), "0x010203", "null"],
      ]),
      "",
    );
  });
});
