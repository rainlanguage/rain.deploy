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

function isElementaryAbiType(name: string): bool {
  if (
    name == "address" ||
    name == "bool" ||
    name == "string" ||
    name == "bytes"
  ) {
    return true;
  }
  if (name.startsWith("bytes")) {
    let m = smallDecimal(name.substring(5));
    return m >= 1 && m <= 32;
  }
  let bits: i32 = -1;
  if (name.startsWith("uint")) {
    bits = smallDecimal(name.substring(4));
  } else if (name.startsWith("int")) {
    bits = smallDecimal(name.substring(3));
  }
  return bits >= 8 && bits <= 256 && bits % 8 == 0;
}

/** Iterative so that deeply nested tuples in an emitted type string cannot overflow the wasm stack. */
export function isCanonicalAbiType(s: string): bool {
  let pos = 0;
  let depth = 0;
  while (true) {
    while (pos < s.length && s.charCodeAt(pos) == CHAR_OPEN_PAREN) {
      depth++;
      pos++;
    }
    let start = pos;
    while (pos < s.length && isIdentifierChar(s.charCodeAt(pos))) {
      pos++;
    }
    if (!isElementaryAbiType(s.substring(start, pos))) {
      return false;
    }
    while (pos < s.length) {
      let c = s.charCodeAt(pos);
      if (c == CHAR_OPEN_BRACKET) {
        pos++;
        if (pos < s.length && s.charCodeAt(pos) == CHAR_CLOSE_BRACKET) {
          pos++;
          continue;
        }
        if (
          pos >= s.length ||
          s.charCodeAt(pos) < CHAR_1 ||
          s.charCodeAt(pos) > CHAR_9
        ) {
          return false;
        }
        while (pos < s.length && isDigit(s.charCodeAt(pos))) {
          pos++;
        }
        if (pos >= s.length || s.charCodeAt(pos) != CHAR_CLOSE_BRACKET) {
          return false;
        }
        pos++;
      } else if (c == CHAR_CLOSE_PAREN && depth > 0) {
        depth--;
        pos++;
      } else {
        break;
      }
    }
    if (pos == s.length) {
      return depth == 0;
    }
    if (s.charCodeAt(pos) != CHAR_COMMA || depth == 0) {
      return false;
    }
    pos++;
  }
  return false;
}
