// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd

const CHAR_0: i32 = 48;
const CHAR_1: i32 = 49;
const CHAR_9: i32 = 57;
const CHAR_A: i32 = 97;
const CHAR_Z: i32 = 122;
const CHAR_OPEN_PAREN: i32 = 40;
const CHAR_CLOSE_PAREN: i32 = 41;
const CHAR_COMMA: i32 = 44;
const CHAR_OPEN_BRACKET: i32 = 91;
const CHAR_CLOSE_BRACKET: i32 = 93;

/** Bounds the recursion of the mapping's own walk over a value of the type. */
const MAX_NESTING: i32 = 8;

/** Larger than any event payload, so a saturated size or length still fails every bounds check. */
export const SIZE_CAP: i64 = 1 << 40;

export namespace AbiKind {
  export const ADDRESS: i32 = 0;
  export const BOOL: i32 = 1;
  export const UINT: i32 = 2;
  export const INT: i32 = 3;
  export const FIXED_BYTES: i32 = 4;
  export const BYTES: i32 = 5;
  export const STRING: i32 = 6;
  export const TUPLE: i32 = 7;
  export const ARRAY: i32 = 8;
}

export class AbiType {
  kind: i32;
  /** Bytes of a `uintN`/`intN`/`bytesN` value. */
  width: i32;
  /** Element count of a fixed array; -1 for `T[]`. */
  length: i64;
  element: AbiType | null;
  components: Array<AbiType>;
  dynamic: bool;
  /** Head bytes when inline in a sequence: 32 for a dynamic type, the whole encoding for a static one. */
  headSize: i64;

  constructor(
    kind: i32,
    width: i32,
    length: i64,
    element: AbiType | null,
    components: Array<AbiType>,
  ) {
    this.kind = kind;
    this.width = width;
    this.length = length;
    this.element = element;
    this.components = components;
    let dynamic = kind == AbiKind.BYTES || kind == AbiKind.STRING;
    let size: i64 = 32;
    if (kind == AbiKind.ARRAY) {
      let e = element!;
      dynamic = length < 0 || e.dynamic;
      size = dynamic ? 32 : saturatingMul(length, e.headSize);
    } else if (kind == AbiKind.TUPLE) {
      size = 0;
      for (let i = 0; i < components.length; i++) {
        dynamic = dynamic || components[i].dynamic;
        size = saturatingAdd(size, components[i].headSize);
      }
      if (dynamic) {
        size = 32;
      }
    }
    this.dynamic = dynamic;
    this.headSize = size;
  }
}

export function saturatingAdd(a: i64, b: i64): i64 {
  let sum = a + b;
  return sum > SIZE_CAP ? SIZE_CAP : sum;
}

function saturatingMul(a: i64, b: i64): i64 {
  if (a != 0 && b > SIZE_CAP / a) {
    return SIZE_CAP;
  }
  let product = a * b;
  return product > SIZE_CAP ? SIZE_CAP : product;
}

function isDigit(c: i32): bool {
  return c >= CHAR_0 && c <= CHAR_9;
}

function isIdentifierChar(c: i32): bool {
  return isDigit(c) || (c >= CHAR_A && c <= CHAR_Z);
}

function smallDecimal(digits: string): i32 {
  if (digits.length < 1 || digits.length > 3) {
    return -1;
  }
  if (digits.charCodeAt(0) == CHAR_0) {
    return -1;
  }
  let n: i32 = 0;
  for (let i = 0; i < digits.length; i++) {
    let c = digits.charCodeAt(i);
    if (!isDigit(c)) {
      return -1;
    }
    n = n * 10 + (c - CHAR_0);
  }
  return n;
}

function elementary(kind: i32, width: i32): AbiType {
  return new AbiType(kind, width, 0, null, new Array<AbiType>());
}

function elementaryAbiType(name: string): AbiType | null {
  if (name == "address") {
    return elementary(AbiKind.ADDRESS, 20);
  }
  if (name == "bool") {
    return elementary(AbiKind.BOOL, 1);
  }
  if (name == "string") {
    return elementary(AbiKind.STRING, 0);
  }
  if (name == "bytes") {
    return elementary(AbiKind.BYTES, 0);
  }
  if (name.startsWith("bytes")) {
    let m = smallDecimal(name.substring(5));
    return m >= 1 && m <= 32 ? elementary(AbiKind.FIXED_BYTES, m) : null;
  }
  let kind: i32 = -1;
  let bits: i32 = -1;
  if (name.startsWith("uint")) {
    kind = AbiKind.UINT;
    bits = smallDecimal(name.substring(4));
  } else if (name.startsWith("int")) {
    kind = AbiKind.INT;
    bits = smallDecimal(name.substring(3));
  }
  if (bits >= 8 && bits <= 256 && bits % 8 == 0) {
    return elementary(kind, bits / 8);
  }
  return null;
}

/** Iterative so that deeply nested tuples in an emitted type string cannot overflow the wasm stack. */
export function parseAbiType(s: string): AbiType | null {
  let pos = 0;
  let enclosing = new Array<i32>();
  let frames = new Array<Array<AbiType>>();
  let levels: i32 = 0;
  while (true) {
    while (pos < s.length && s.charCodeAt(pos) == CHAR_OPEN_PAREN) {
      if (enclosing.length >= MAX_NESTING) {
        return null;
      }
      enclosing.push(0);
      frames.push(new Array<AbiType>());
      pos++;
    }
    let start = pos;
    while (pos < s.length && isIdentifierChar(s.charCodeAt(pos))) {
      pos++;
    }
    let leaf = elementaryAbiType(s.substring(start, pos));
    if (leaf === null) {
      return null;
    }
    let current: AbiType = leaf!;
    levels = 0;
    while (pos < s.length) {
      let c = s.charCodeAt(pos);
      if (c == CHAR_OPEN_BRACKET) {
        pos++;
        if (levels >= MAX_NESTING) {
          return null;
        }
        levels++;
        if (pos < s.length && s.charCodeAt(pos) == CHAR_CLOSE_BRACKET) {
          pos++;
          current = new AbiType(AbiKind.ARRAY, 0, -1, current, new Array<AbiType>());
          continue;
        }
        if (
          pos >= s.length ||
          s.charCodeAt(pos) < CHAR_1 ||
          s.charCodeAt(pos) > CHAR_9
        ) {
          return null;
        }
        let length: i64 = 0;
        while (pos < s.length && isDigit(s.charCodeAt(pos))) {
          length = saturatingAdd(
            saturatingMul(length, 10),
            (s.charCodeAt(pos) - CHAR_0) as i64,
          );
          pos++;
        }
        if (pos >= s.length || s.charCodeAt(pos) != CHAR_CLOSE_BRACKET) {
          return null;
        }
        pos++;
        current = new AbiType(AbiKind.ARRAY, 0, length, current, new Array<AbiType>());
      } else if (c == CHAR_CLOSE_PAREN && enclosing.length > 0) {
        let sibling = enclosing.pop();
        levels = 1 + (sibling > levels ? sibling : levels);
        if (levels > MAX_NESTING) {
          return null;
        }
        let components = frames.pop();
        components.push(current);
        current = new AbiType(AbiKind.TUPLE, 0, 0, null, components);
        pos++;
      } else {
        break;
      }
    }
    if (pos == s.length) {
      return enclosing.length == 0 ? current : null;
    }
    if (s.charCodeAt(pos) != CHAR_COMMA || enclosing.length == 0) {
      return null;
    }
    let top = enclosing.length - 1;
    if (levels > enclosing[top]) {
      enclosing[top] = levels;
    }
    frames[top].push(current);
    pos++;
  }
  return null;
}
