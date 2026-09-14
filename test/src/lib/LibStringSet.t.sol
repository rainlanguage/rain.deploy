// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibStringSet} from "../../../src/lib/LibStringSet.sol";

/// @title LibStringSetTest
/// `holds` is membership by whole-string equality over a list whose order it
/// does not fix. Every case here is a concrete list and needle whose answer is
/// derived from that definition rather than from the loop that implements it.
contract LibStringSetTest is Test {
    /// @return A three element list of distinct single character strings.
    function three() internal pure returns (string[] memory) {
        string[] memory haystack = new string[](3);
        haystack[0] = "a";
        haystack[1] = "b";
        haystack[2] = "c";
        return haystack;
    }

    /// Position does not matter: the first, a middle and the last element are
    /// all held.
    function testHoldsFindsAnElementAtEveryIndex() external pure {
        string[] memory haystack = three();
        assertTrue(LibStringSet.holds(haystack, "a"));
        assertTrue(LibStringSet.holds(haystack, "b"));
        assertTrue(LibStringSet.holds(haystack, "c"));
    }

    /// A one element list holds exactly that element.
    function testHoldsSingleElement() external pure {
        string[] memory haystack = new string[](1);
        haystack[0] = "only";
        assertTrue(LibStringSet.holds(haystack, "only"));
        assertFalse(LibStringSet.holds(haystack, "other"));
    }

    /// A string equal to none of the elements is not held.
    function testHoldsIsFalseOnAMiss() external pure {
        assertFalse(LibStringSet.holds(three(), "d"));
    }

    /// An empty list holds nothing, not even the empty string.
    function testHoldsIsFalseOnAnEmptyHaystack() external pure {
        string[] memory haystack = new string[](0);
        assertFalse(LibStringSet.holds(haystack, "a"));
        assertFalse(LibStringSet.holds(haystack, ""));
    }

    /// Equality is over the whole content: a prefix, an extension, a same
    /// length string differing in any byte, and a case change are all
    /// different strings.
    function testHoldsComparesTheWholeContent() external pure {
        string[] memory haystack = new string[](1);
        haystack[0] = "ab";
        assertTrue(LibStringSet.holds(haystack, "ab"));
        assertFalse(LibStringSet.holds(haystack, "a"));
        assertFalse(LibStringSet.holds(haystack, "abc"));
        assertFalse(LibStringSet.holds(haystack, "ac"));
        assertFalse(LibStringSet.holds(haystack, "cb"));
        assertFalse(LibStringSet.holds(haystack, "AB"));
        assertFalse(LibStringSet.holds(haystack, "aB"));
    }

    /// Content longer than one EVM word is compared in full: two strings that
    /// share their first 32 bytes and differ only after them are different.
    function testHoldsComparesBeyondTheFirstWord() external pure {
        string memory head = "0123456789abcdef0123456789abcdef";
        assertEq(bytes(head).length, 32);
        string[] memory haystack = new string[](1);
        haystack[0] = string.concat(head, "tail-one");
        assertTrue(LibStringSet.holds(haystack, string.concat(head, "tail-one")));
        assertFalse(LibStringSet.holds(haystack, string.concat(head, "tail-two")));
        assertFalse(LibStringSet.holds(haystack, head));
    }

    /// The empty string is an ordinary member: it is held only when an element
    /// is itself empty, and an empty element does not match a non empty needle.
    function testHoldsEmptyNeedleMatchesOnlyAnEmptyElement() external pure {
        string[] memory haystack = new string[](1);
        haystack[0] = "a";
        assertFalse(LibStringSet.holds(haystack, ""));

        string[] memory withEmpty = new string[](2);
        withEmpty[0] = "a";
        withEmpty[1] = "";
        assertTrue(LibStringSet.holds(withEmpty, ""));
        assertFalse(LibStringSet.holds(withEmpty, "b"));
    }

    /// Equality is by value, not by which memory the string sits in: a needle
    /// built separately from the element it equals is held, and a needle equal
    /// to no element is not, however it was built.
    function testHoldsIsByValueNotIdentity() external pure {
        string[] memory haystack = new string[](2);
        haystack[0] = string.concat("du", "p");
        haystack[1] = string.concat("d", "up");
        assertTrue(LibStringSet.holds(haystack, string.concat("dup", "")));
        assertFalse(LibStringSet.holds(haystack, string.concat("du", "")));
    }

    /// A match is the answer whatever follows it, so an element that is held
    /// is held no matter how many misses sit after it in the list.
    function testHoldsAMatchIsNotUndoneByLaterMisses() external pure {
        string[] memory haystack = new string[](4);
        haystack[0] = "hit";
        haystack[1] = "miss-one";
        haystack[2] = "miss-two";
        haystack[3] = "miss-three";
        assertTrue(LibStringSet.holds(haystack, "hit"));
        assertFalse(LibStringSet.holds(haystack, "miss-four"));
    }

    /// Membership is over a set, so the order of the list does not change it.
    function testHoldsIsOrderIndependent() external pure {
        string[] memory forward = three();
        string[] memory reversed = new string[](3);
        reversed[0] = forward[2];
        reversed[1] = forward[1];
        reversed[2] = forward[0];
        for (uint256 i = 0; i < forward.length; i++) {
            assertTrue(LibStringSet.holds(reversed, forward[i]));
            assertEq(LibStringSet.holds(forward, forward[i]), LibStringSet.holds(reversed, forward[i]));
        }
        assertFalse(LibStringSet.holds(reversed, "d"));
    }

    /// Every element of any list is held by that list. The extra element keeps
    /// the list non empty whatever the fuzzer produces.
    function testHoldsFuzzMember(string[] memory haystack, string memory extra, uint256 index) external pure {
        string[] memory withExtra = new string[](haystack.length + 1);
        for (uint256 i = 0; i < haystack.length; i++) {
            withExtra[i] = haystack[i];
        }
        withExtra[haystack.length] = extra;
        assertTrue(LibStringSet.holds(withExtra, withExtra[index % withExtra.length]));
    }

    /// A string longer than every element cannot equal any of them, so it is
    /// never held.
    function testHoldsFuzzLongerThanEveryElementIsMissed(string[] memory haystack) external pure {
        uint256 longest = 0;
        for (uint256 i = 0; i < haystack.length; i++) {
            if (bytes(haystack[i]).length > longest) {
                longest = bytes(haystack[i]).length;
            }
        }
        assertFalse(LibStringSet.holds(haystack, string(new bytes(longest + 1))));
    }
}
