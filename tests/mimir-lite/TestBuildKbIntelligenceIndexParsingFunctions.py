#!/usr/bin/env python3
"""Direct unit tests for pure parsing functions of Build-KbIntelligenceIndex.py.

Each function is called in process, without starting pwsh or building an index:
mask_xml_cdata_and_comments, line_number_at, strip_line_comment,
case_insensitive_lookup and direct_call_pattern. The build module is loaded through
importlib by the shared tests/mimir-lite/_engine_loader.py.
"""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import random  # noqa: E402
import re  # noqa: E402
import time  # noqa: E402
import unittest  # noqa: E402

from _engine_loader import load_build_module  # noqa: E402

BUILD = load_build_module()


class MaskXmlCdataAndCommentsTests(unittest.TestCase):
    def mask(self, text: str) -> str:
        return BUILD.mask_xml_cdata_and_comments(text)

    def test_text_without_cdata_or_comments_is_unchanged(self) -> None:
        text = "<Object><Name>Proc</Name></Object>"
        self.assertEqual(self.mask(text), text)

    def test_cdata_block_is_masked_with_same_length(self) -> None:
        text = "<a><![CDATA[call(Proc)]]></a>"
        masked = self.mask(text)
        self.assertEqual(masked, "<a>" + "X" * len("<![CDATA[call(Proc)]]>") + "</a>")

    def test_comment_block_is_masked_with_same_length(self) -> None:
        text = "<a><!-- Proc() --></a>"
        masked = self.mask(text)
        self.assertEqual(masked, "<a>" + "X" * len("<!-- Proc() -->") + "</a>")

    def test_line_breaks_inside_masked_blocks_are_kept(self) -> None:
        text = "<a>\n<![CDATA[one\ntwo]]>\n<!--x\ny-->\n<b/>"
        masked = self.mask(text)
        self.assertEqual(len(masked), len(text))
        self.assertEqual(
            [i for i, c in enumerate(masked) if c == "\n"],
            [i for i, c in enumerate(text) if c == "\n"],
        )
        self.assertTrue(masked.endswith("\n<b/>"))
        self.assertNotIn("one", masked)
        self.assertNotIn("y-->", masked)

    def test_crlf_text_keeps_length_and_line_numbers(self) -> None:
        text = "<a>\r\n<!-- c\r\n -->\r\n<b>Proc</b>"
        masked = self.mask(text)
        self.assertEqual(len(masked), len(text))
        index = text.index("<b>")
        self.assertEqual(masked[index:], "<b>Proc</b>")
        self.assertEqual(BUILD.line_number_at(masked, index), BUILD.line_number_at(text, index))

    def test_comment_opener_inside_cdata_does_not_start_a_comment(self) -> None:
        text = "<![CDATA[ <!-- ]]>keep-->"
        masked = self.mask(text)
        self.assertEqual(masked, "X" * len("<![CDATA[ <!-- ]]>") + "keep-->")

    def test_cdata_opener_inside_comment_does_not_start_cdata(self) -> None:
        text = "<!-- <![CDATA[ -->keep]]>"
        masked = self.mask(text)
        self.assertEqual(masked, "X" * len("<!-- <![CDATA[ -->") + "keep]]>")

    def test_several_blocks_are_masked_and_text_between_is_kept(self) -> None:
        text = "A<!--1-->B<![CDATA[2]]>C<!--3-->D"
        self.assertEqual(self.mask(text), "AXXXXXXXXBXXXXXXXXXXXXXCXXXXXXXXD")

    def test_unclosed_cdata_is_not_masked(self) -> None:
        text = "<a><![CDATA[Proc() no closer</a>"
        self.assertEqual(self.mask(text), text)

    def test_unclosed_comment_is_not_masked(self) -> None:
        text = "<a><!-- Proc() no closer</a>"
        self.assertEqual(self.mask(text), text)

    def test_block_after_an_unclosed_opener_is_still_masked(self) -> None:
        # An unclosed CDATA opener is skipped, so a later complete comment is masked.
        text = "<![CDATA[x <!--c-->"
        self.assertEqual(self.mask(text), "<![CDATA[x " + "X" * len("<!--c-->"))


class LineNumberAtTests(unittest.TestCase):
    def test_index_zero_is_line_one(self) -> None:
        self.assertEqual(BUILD.line_number_at("abc\ndef", 0), 1)

    def test_index_on_newline_is_still_that_line(self) -> None:
        self.assertEqual(BUILD.line_number_at("abc\ndef", 3), 1)

    def test_index_after_newline_is_next_line(self) -> None:
        text = "abc\ndef\nghi"
        self.assertEqual(BUILD.line_number_at(text, 4), 2)
        self.assertEqual(BUILD.line_number_at(text, text.index("ghi")), 3)

    def test_crlf_counts_one_line_per_break(self) -> None:
        text = "a\r\nb\r\nc"
        self.assertEqual(BUILD.line_number_at(text, text.index("c")), 3)

    def test_lone_carriage_return_is_not_a_line_break(self) -> None:
        self.assertEqual(BUILD.line_number_at("a\rb", 2), 1)

    def test_empty_lines_are_counted(self) -> None:
        text = "\n\n\nx"
        self.assertEqual(BUILD.line_number_at(text, 3), 4)

    def test_index_past_the_end_counts_every_break(self) -> None:
        self.assertEqual(BUILD.line_number_at("a\nb\n", 100), 3)


class StripLineCommentTests(unittest.TestCase):
    def strip(self, line: str) -> str:
        return BUILD.strip_line_comment(line)

    def test_line_without_comment_is_unchanged(self) -> None:
        self.assertEqual(self.strip("call(Proc, &x)"), "call(Proc, &x)")

    def test_trailing_line_comment_is_removed(self) -> None:
        self.assertEqual(self.strip("Proc.Call() // Other.Call()"), "Proc.Call() ")

    def test_whole_line_comment_becomes_empty(self) -> None:
        self.assertEqual(self.strip("// Proc.Call()"), "")

    def test_slashes_inside_double_quoted_literal_are_kept(self) -> None:
        line = '&url = "http://host/x" // note'
        self.assertEqual(self.strip(line), '&url = "http://host/x" ')

    def test_slashes_inside_single_quoted_literal_are_kept(self) -> None:
        line = "&url = 'http://host/x' // note"
        self.assertEqual(self.strip(line), "&url = 'http://host/x' ")

    def test_translatable_literal_is_a_literal(self) -> None:
        line = '&msg = !"see //here" // note'
        self.assertEqual(self.strip(line), '&msg = !"see //here" ')

    def test_other_quote_kind_inside_literal_does_not_close_it(self) -> None:
        line = "&s = \"it's // fine\" // note"
        self.assertEqual(self.strip(line), "&s = \"it's // fine\" ")

    def test_doubled_quote_inside_literal_keeps_it_open(self) -> None:
        line = '&s = "say ""//"" ok" // note'
        self.assertEqual(self.strip(line), '&s = "say ""//"" ok" ')

    def test_unterminated_literal_runs_to_end_of_line(self) -> None:
        line = '&s = "open // not a comment'
        self.assertEqual(self.strip(line), line)

    def test_block_comment_is_skipped_and_kept(self) -> None:
        line = "Proc() /* note */ // rest"
        self.assertEqual(self.strip(line), "Proc() /* note */ ")

    def test_quote_inside_block_comment_does_not_open_a_literal(self) -> None:
        line = "Proc() /* don't */ // rest"
        self.assertEqual(self.strip(line), "Proc() /* don't */ ")

    def test_unclosed_block_comment_runs_to_end_of_line(self) -> None:
        self.assertEqual(self.strip("Proc() /* open \"x // y"), "Proc() ")

    def test_single_slash_is_not_a_comment(self) -> None:
        self.assertEqual(self.strip("&a = &b / &c"), "&a = &b / &c")


class CaseInsensitiveLookupTests(unittest.TestCase):
    def test_maps_lowercase_key_to_original_name(self) -> None:
        lookup = BUILD.case_insensitive_lookup({"CustomerGet", "OrderSave"}, "Procedure")
        self.assertEqual(lookup, {"customerget": "CustomerGet", "ordersave": "OrderSave"})

    def test_empty_set_gives_empty_lookup(self) -> None:
        self.assertEqual(BUILD.case_insensitive_lookup(set(), "Procedure"), {})

    def test_names_differing_only_by_case_raise_with_details(self) -> None:
        with self.assertRaises(ValueError) as raised:
            BUILD.case_insensitive_lookup({"Proc", "PROC", "Other"}, "Procedure")
        self.assertEqual(
            str(raised.exception),
            "Ambiguous Procedure names differing only by case: proc: PROC, Proc",
        )

    def test_every_collision_is_reported_in_key_order(self) -> None:
        with self.assertRaises(ValueError) as raised:
            BUILD.case_insensitive_lookup({"bb", "BB", "aa", "Aa"}, "Table")
        self.assertEqual(
            str(raised.exception),
            "Ambiguous Table names differing only by case: aa: Aa, aa; bb: BB, bb",
        )


class DirectCallPatternTests(unittest.TestCase):
    def names(self, pattern, text: str) -> list:
        return [match.group("name") for match in pattern.finditer(text)]

    def test_no_names_gives_no_pattern(self) -> None:
        self.assertIsNone(BUILD.direct_call_pattern(set()))

    def test_matches_name_followed_by_parenthesis(self) -> None:
        pattern = BUILD.direct_call_pattern({"CustomerGet"})
        self.assertEqual(self.names(pattern, "CustomerGet(&id, &name)"), ["CustomerGet"])

    def test_allows_whitespace_before_parenthesis(self) -> None:
        pattern = BUILD.direct_call_pattern({"CustomerGet"})
        self.assertEqual(self.names(pattern, "CustomerGet  (&id)\nCustomerGet\t(&x)"), ["CustomerGet", "CustomerGet"])

    def test_match_is_case_insensitive_and_returns_text_as_written(self) -> None:
        pattern = BUILD.direct_call_pattern({"CustomerGet"})
        self.assertEqual(self.names(pattern, "customerget(&id)"), ["customerget"])

    def test_name_without_parenthesis_does_not_match(self) -> None:
        pattern = BUILD.direct_call_pattern({"CustomerGet"})
        self.assertEqual(self.names(pattern, "&x = CustomerGet"), [])

    def test_variable_and_member_access_do_not_match(self) -> None:
        pattern = BUILD.direct_call_pattern({"CustomerGet"})
        self.assertEqual(self.names(pattern, "&CustomerGet(1) &obj.CustomerGet(2)"), [])

    def test_name_inside_a_longer_identifier_does_not_match(self) -> None:
        pattern = BUILD.direct_call_pattern({"Get"})
        self.assertEqual(self.names(pattern, "CustomerGet(1) GetAll(2)"), [])

    def test_longest_name_wins_when_one_is_a_prefix_of_another(self) -> None:
        pattern = BUILD.direct_call_pattern({"Proc", "ProcAll"})
        self.assertEqual(self.names(pattern, "ProcAll(1) Proc(2)"), ["ProcAll", "Proc"])

    def test_regex_metacharacters_in_names_are_literal(self) -> None:
        pattern = BUILD.direct_call_pattern({"Mod.Proc"})
        self.assertEqual(self.names(pattern, "ModXProc(1) Mod.Proc(2)"), ["Mod.Proc"])

    @staticmethod
    def reference_pattern(names: set) -> "re.Pattern[str]":
        # The original single alternation of every name, longest first.
        alternatives = "|".join(re.escape(name) for name in sorted(names, key=len, reverse=True))
        return re.compile(rf"(?<![&.])\b(?P<name>{alternatives})\s*\(", re.IGNORECASE)

    @staticmethod
    def spans(pattern, text: str) -> list:
        return [(m.start(), m.end(), m.group("name")) for m in pattern.finditer(text)]

    def random_texts(self, rng: random.Random, name_list: list, count: int):
        letters = "abcdefghijklmnopqrstuvwxyz"
        pieces = ["(", ")", " ", chr(9), chr(10), ".", "&", ",", "=", "+", "'", "1", "_"]
        # Letters that re.IGNORECASE treats as i, s or k but str.lower() does not map to them:
        # dotted capital I, dotless i, long s, and the Kelvin sign.
        variants = {"i": [chr(0x130), chr(0x131)], "s": [chr(0x17F)], "k": [chr(0x212A)]}
        for _ in range(count):
            parts = []
            for _ in range(rng.randint(1, 25)):
                choice = rng.random()
                if choice < 0.45:
                    name = rng.choice(name_list)
                    roll = rng.random()
                    if roll < 0.2:
                        name = name.lower()
                    elif roll < 0.4:
                        name = "".join(rng.choice(variants[c.lower()]) if c.lower() in variants and rng.random() < 0.5 else c for c in name)
                    parts.append(name)
                elif choice < 0.6:
                    parts.append("".join(rng.choice(letters) for _ in range(rng.randint(1, 6))))
                else:
                    parts.append(rng.choice(pieces))
            yield "".join(parts)

    def test_matches_are_identical_to_the_name_alternation(self) -> None:
        rng = random.Random(20261120)
        letters = "abcdefghijklmnopqrstuvwxyz"
        names = {"Proc", "ProcAll", "Mod.Proc", "Mod.Proc.Run", "Get", "A1_b", "x", "Kayit", "Kas", "Sika"}
        names |= {rng.choice(letters).upper() + "".join(rng.choice(letters) for _ in range(rng.randint(1, 8))) for _ in range(300)}
        reference = self.reference_pattern(names)
        matcher = BUILD.direct_call_pattern(names)
        self.assertNotIsInstance(matcher, re.Pattern, "ASCII names should use the token scan, not the alternation")
        explicit = [
            "KAY" + chr(0x130) + "T(1)",
            "kay" + chr(0x131) + "t(1) Kayit (2)",
            "Ka" + chr(0x17F) + "(1) " + chr(0x212A) + "as(2)",
            chr(0x17F) + "ika(1) &" + chr(0x17F) + "ika(2) obj." + chr(0x17F) + "ika(3)",
        ]
        for text in explicit:
            self.assertEqual(self.spans(matcher, text), self.spans(reference, text), f"text: {ascii(text)}")
        for text in self.random_texts(rng, sorted(names), 400):
            self.assertEqual(self.spans(matcher, text), self.spans(reference, text), f"text: {ascii(text)}")

    def test_a_name_outside_ascii_keeps_the_alternation(self) -> None:
        rng = random.Random(11)
        names = {"Proc", "ProcAll", "Get", chr(0xD1) + "and" + chr(0xFA), "Caf" + chr(0xE9)}
        pattern = BUILD.direct_call_pattern(names)
        self.assertIsInstance(pattern, re.Pattern, "a non-ASCII name should keep the original alternation")
        reference = self.reference_pattern(names)
        for text in self.random_texts(rng, sorted(names), 200):
            self.assertEqual(self.spans(pattern, text), self.spans(reference, text), f"text: {ascii(text)}")

    def test_cost_does_not_grow_with_the_number_of_names(self) -> None:
        # A single alternation of every name made the build quadratic in the number of Procedure
        # objects (measured with tools/benchmark): 20,000 names took about 80 times as long as 200 names on the
        # same text. The token scan's cost does not depend on the number of names. The check is
        # relative, so machine load affects both timings alike.
        rng = random.Random(7)
        letters = "abcdefghijklmnopqrstuvwxyz"

        def make_name() -> str:
            return rng.choice(letters).upper() + "".join(rng.choice(letters) for _ in range(rng.randint(5, 14)))

        many = sorted({make_name() for _ in range(20000)})
        few = set(many[:200])
        text = chr(10).join(f"  &x{i} = {many[i % 200]}(&a, &b) + &y.Other(1) // {make_name()} note" for i in range(3000))

        def timed(names) -> float:
            best = float("inf")
            for _ in range(3):
                started = time.perf_counter()
                found = sum(1 for _ in BUILD.direct_call_pattern(names).finditer(text))
                best = min(best, time.perf_counter() - started)
                self.assertEqual(found, 3000)
            return best

        few_time = timed(few)
        many_time = timed(set(many))
        self.assertLess(many_time, 5 * few_time + 0.05, f"20,000 names took {many_time:.3f} s against {few_time:.3f} s for 200 names")

if __name__ == "__main__":
    unittest.main()
