// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd

import { Bytes } from "@graphprotocol/graph-ts";
import { AbiKind, AbiType, SIZE_CAP, saturatingAdd } from "./abitype";

export namespace AbiEncoding {
  export const CANONICAL: i32 = 0;
  export const NOT_CANONICAL: i32 = 1;
  export const NOT_DECODABLE: i32 = 2;
}

const WORD: i64 = 32;

class EncodingWalk {
  data: Bytes;
  canonical: bool = true;

  constructor(data: Bytes) {
    this.data = data;
  }

  fits(pos: i64, size: i64): bool {
    let end = saturatingAdd(pos, size);
    return pos >= 0 && size >= 0 && end <= (this.data.length as i64);
  }

  /** Zero-padding check over `[from, to)` of the word at `pos`. */
  zeroes(pos: i64, from: i32, to: i32): bool {
    for (let i = from; i < to; i++) {
      if (this.data[(pos as i32) + i] != 0) {
        return false;
      }
    }
    return true;
  }

  /** A uint256 word read as an offset or length; SIZE_CAP when it cannot address the data. */
  size(pos: i64): i64 {
    if (!this.zeroes(pos, 0, 26)) {
      return SIZE_CAP;
    }
    let n: i64 = 0;
    for (let i = 26; i < 32; i++) {
      n = (n << 8) | (this.data[(pos as i32) + i] as i64);
    }
    return n > SIZE_CAP ? SIZE_CAP : n;
  }

  /** Checks one static word in place; false when it is past the end. */
  word(t: AbiType, pos: i64): bool {
    if (!this.fits(pos, WORD)) {
      return false;
    }
    let p = pos as i32;
    let ok = true;
    if (t.kind == AbiKind.ADDRESS || t.kind == AbiKind.UINT) {
      ok = this.zeroes(pos, 0, 32 - t.width);
    } else if (t.kind == AbiKind.BOOL) {
      ok = this.zeroes(pos, 0, 31) && this.data[p + 31] <= 1;
    } else if (t.kind == AbiKind.FIXED_BYTES) {
      ok = this.zeroes(pos, t.width, 32);
    } else if (t.kind == AbiKind.INT) {
      let fill: u8 = (this.data[p + 32 - t.width] & 0x80) != 0 ? 0xff : 0;
      for (let i = 0; i < 32 - t.width; i++) {
        if (this.data[p + i] != fill) {
          ok = false;
        }
      }
    }
    if (!ok) {
      this.canonical = false;
    }
    return true;
  }

  /** Walks `t` encoded at `pos`; returns the end of its canonical encoding, or -1 when it cannot be read. */
  value(t: AbiType, pos: i64): i64 {
    if (t.kind == AbiKind.BYTES || t.kind == AbiKind.STRING) {
      if (!this.fits(pos, WORD)) {
        return -1;
      }
      let length = this.size(pos);
      let padded = saturatingAdd(length, (WORD - (length % WORD)) % WORD);
      let start = pos + WORD;
      if (!this.fits(start, padded)) {
        return -1;
      }
      for (let i = length; i < padded; i++) {
        if (this.data[(start + i) as i32] != 0) {
          this.canonical = false;
        }
      }
      return start + padded;
    }
    if (t.kind == AbiKind.TUPLE) {
      return this.sequence(t, t.components.length as i64, pos);
    }
    if (t.kind == AbiKind.ARRAY) {
      if (t.length >= 0) {
        return this.sequence(t, t.length, pos);
      }
      if (!this.fits(pos, WORD)) {
        return -1;
      }
      return this.sequence(t, this.size(pos), pos + WORD);
    }
    return this.word(t, pos) ? pos + WORD : -1;
  }

  /** Walks the `count` items of a tuple or array whose heads start at `base`. */
  sequence(t: AbiType, count: i64, base: i64): i64 {
    let isTuple = t.kind == AbiKind.TUPLE;
    let headsEnd = base;
    if (isTuple) {
      for (let i = 0; i < t.components.length; i++) {
        headsEnd = saturatingAdd(headsEnd, t.components[i].headSize);
      }
    } else {
      let headSize = t.element!.headSize;
      headsEnd =
        count > SIZE_CAP / headSize
          ? SIZE_CAP
          : saturatingAdd(base, count * headSize);
    }
    if (!this.fits(base, headsEnd - base)) {
      return -1;
    }
    let head = base;
    let tail = headsEnd;
    for (let i: i64 = 0; i < count; i++) {
      let item = isTuple ? t.components[i as i32] : t.element!;
      if (item.dynamic) {
        let target = saturatingAdd(base, this.size(head));
        if (target != tail) {
          this.canonical = false;
        }
        let end = this.value(item, target);
        if (end < 0) {
          return -1;
        }
        tail = end;
      } else if (this.value(item, head) < 0) {
        return -1;
      }
      head += item.headSize;
    }
    return tail;
  }
}

/** Whether `data` is exactly `abi.encode` of one value of type `t`. */
export function abiEncodingStatus(t: AbiType, data: Bytes): i32 {
  let walk = new EncodingWalk(data);
  let root = new AbiType(AbiKind.TUPLE, 0, 0, null, [t]);
  let end = walk.value(root, 0);
  if (end < 0) {
    return AbiEncoding.NOT_DECODABLE;
  }
  if (!walk.canonical || end != (data.length as i64)) {
    return AbiEncoding.NOT_CANONICAL;
  }
  return AbiEncoding.CANONICAL;
}
