#!/usr/bin/env python3
"""The declarative extractor registry of the KB Intelligence build.

GeneXusKbIntelligenceCore.EXTRACTOR_RECORDS describes each extractor call of the build (rule names,
first extractor version, source and target types), in the order the build runs them, and
Build-KbIntelligenceIndex.EXTRACTOR_CALLS holds, by record name, the function and the arguments of
that call and where its evidence goes in the index. main runs the records in order, so the order
is the one the build had before the registry (written down below from main at d8f656e), and
adding a record with its call is enough to run a new extractor.
"""

from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import ast  # noqa: E402
import unittest  # noqa: E402
from pathlib import Path  # noqa: E402

from _engine_loader import REPO_ROOT, load_build_module  # noqa: E402

BUILD = load_build_module()

import GeneXusKbIntelligenceCore as CORE  # noqa: E402

SAMPLE_KB = REPO_ROOT / "tests" / "fixtures" / "sample-kb"

# The extractor calls of main at d8f656e, in call order: (record name, function). The
# workwith_sd_attribute_evidence function runs twice: for WorkWith, then for Panel.
BASELINE_CALLS = (
    ("evidence", "extract_evidence"),
    ("source_for_each_explicit_table", "extract_source_for_each_explicit_table_evidence"),
    ("source_for_each_qualified_table_prefix", "extract_source_for_each_qualified_table_prefix_evidence"),
    ("source_bc_load_transaction", "extract_source_bc_load_transaction_evidence"),
    ("source_bc_save_transaction", "extract_source_bc_save_transaction_evidence"),
    ("source_bc_delete_transaction", "extract_source_bc_delete_transaction_evidence"),
    ("source_bc_check_transaction", "extract_source_bc_check_transaction_evidence"),
    ("source_simple_bc_insert_update_transaction", "extract_source_simple_bc_insert_update_transaction_evidence"),
    ("source_external_object_method", "extract_source_external_object_method_evidence"),
    ("workwith_action", "extract_workwith_action_evidence"),
    ("workwith_condition", "extract_workwith_condition_evidence"),
    ("workwith_condition_attribute", "extract_workwith_condition_attribute_evidence"),
    ("workwith_transaction", "extract_workwith_transaction_evidence"),
    ("workwith_webpanel_link", "extract_workwith_webpanel_link_evidence"),
    ("workwith_prompt", "extract_workwith_prompt_evidence"),
    ("workwith_for_web_attribute", "extract_workwith_for_web_attribute_evidence"),
    ("workwith_sd_attribute", "extract_workwith_sd_attribute_evidence"),
    ("panel_attribute", "extract_workwith_sd_attribute_evidence"),
    ("code_attribute", "extract_code_attribute_evidence"),
    ("attcustomtype", "extract_attcustomtype_evidence"),
    ("attcustomtype_resolved", "extract_attcustomtype_resolved_evidence"),
    ("sdt_item_attcustomtype_resolved_sdt", "extract_sdt_item_attcustomtype_resolved_sdt_evidence"),
    ("idbasedon_domain", "extract_idbasedon_domain_evidence"),
    ("classic_formula", "extract_classic_formula_evidence"),
    ("attribute_formula_attribute", "extract_attribute_formula_attribute_evidence"),
    ("classic_menu_option", "extract_classic_menu_option_evidence"),
    ("attribute_formula_call", "extract_attribute_formula_call_evidence"),
    ("transaction_level_attribute", "extract_transaction_level_attribute_evidence"),
    ("transaction_level_table", "extract_transaction_level_table_evidence"),
    ("table_key_attribute", "extract_table_key_attribute_evidence"),
    ("table_index_member_attribute", "extract_table_index_member_attribute_evidence"),
    ("classic_table_structure", "extract_classic_table_structure_evidence"),
    ("classic_transaction_level", "extract_classic_transaction_level_evidence"),
    ("classic_for_each_base_table", "extract_classic_for_each_base_table_evidence"),
    ("css_layout_usage", "extract_css_layout_usage_evidence"),
    ("css_event_usage", "extract_css_event_usage_evidence"),
)

# The order main at d8f656e concatenated the evidence of those calls (it decides the evidence and
# relation ids): not the call order for the formula, menu, classic structure and CSS calls.
BASELINE_EVIDENCE_ORDER = (
    "evidence",
    "source_for_each_explicit_table",
    "source_for_each_qualified_table_prefix",
    "source_bc_load_transaction",
    "source_bc_save_transaction",
    "source_bc_delete_transaction",
    "source_bc_check_transaction",
    "source_simple_bc_insert_update_transaction",
    "source_external_object_method",
    "workwith_action",
    "workwith_condition",
    "workwith_condition_attribute",
    "workwith_transaction",
    "workwith_webpanel_link",
    "workwith_prompt",
    "workwith_for_web_attribute",
    "workwith_sd_attribute",
    "panel_attribute",
    "code_attribute",
    "attcustomtype",
    "attcustomtype_resolved",
    "sdt_item_attcustomtype_resolved_sdt",
    "idbasedon_domain",
    "attribute_formula_call",
    "classic_menu_option",
    "classic_formula",
    "attribute_formula_attribute",
    "transaction_level_attribute",
    "transaction_level_table",
    "table_key_attribute",
    "table_index_member_attribute",
    "css_layout_usage",
    "css_event_usage",
    "classic_table_structure",
    "classic_transaction_level",
    "classic_for_each_base_table",
)

# The per-line call patterns of extract_evidence at d8f656e, in order: the rule of each target it
# tries, the first one that names an object winning (a Procedure before a Work Panel).
BASELINE_SOURCE_CALL_PATTERNS = (
    ("procedure_dot_call", "workpanel_dot_call"),
    ("procedure_direct_call",),
    ("procedure_call_command", "workpanel_call_command"),
    ("procedure_udp_func",),
    ("procedure_dot_udp",),
    ("procedure_dot_link",),
    ("webpanel_dot_link",),
    ("webpanel_dot_create",),
    ("dataprovider_direct_call",),
)


def sample_inputs():
    BUILD.activate_object_type_catalog(SAMPLE_KB.resolve())
    objects_by_type, _summary = BUILD.collect_all_objects(SAMPLE_KB.resolve())
    return BUILD.ExtractionInputs(SAMPLE_KB.resolve(), objects_by_type)


class RegistryOrderTests(unittest.TestCase):
    def test_records_list_the_baseline_calls_in_order(self) -> None:
        actual = tuple(
            (record.name, BUILD.EXTRACTOR_CALLS[record.name].function.__name__) for record in CORE.EXTRACTOR_RECORDS
        )
        self.assertEqual(actual, BASELINE_CALLS)
        self.assertEqual(set(BUILD.EXTRACTOR_CALLS), {name for name, _function in BASELINE_CALLS})

    def test_evidence_keeps_the_baseline_order(self) -> None:
        self.assertEqual(tuple(BUILD.evidence_order(CORE.EXTRACTOR_RECORDS, BUILD.EXTRACTOR_CALLS)), BASELINE_EVIDENCE_ORDER)

    def test_the_two_workwith_sd_calls_differ_only_by_their_arguments(self) -> None:
        inputs = sample_inputs()
        workwith = BUILD.EXTRACTOR_CALLS["workwith_sd_attribute"]
        panel = BUILD.EXTRACTOR_CALLS["panel_attribute"]
        self.assertIs(workwith.function, panel.function)
        _args, workwith_kwargs = workwith.arguments(inputs)
        _args, panel_kwargs = panel.arguments(inputs)
        self.assertNotIn("relation_kind", workwith_kwargs)
        self.assertEqual(panel_kwargs["relation_kind"], "panel_references_attribute")
        self.assertEqual(panel_kwargs["extractor_rule"], "sd_panel_attribute_reference")
        self.assertEqual(panel_kwargs["role_prefix"], "Panel")

    def test_main_calls_no_extractor_directly(self) -> None:
        tree = ast.parse(Path(BUILD.__file__).read_text(encoding="utf-8"))
        main = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "main")
        called = {
            node.func.id
            for node in ast.walk(main)
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id.startswith("extract_")
        }
        self.assertEqual(called, set())

    def test_extract_evidence_tries_the_baseline_call_patterns_in_order(self) -> None:
        patterns = BUILD.source_call_patterns({}, {}, {}, {}, None, None)
        self.assertEqual(
            tuple(tuple(target.extractor_rule for target in pattern.targets) for pattern in patterns),
            BASELINE_SOURCE_CALL_PATTERNS,
        )


class RegistryExtensionTests(unittest.TestCase):
    def test_adding_a_record_and_its_call_runs_a_new_extractor(self) -> None:
        inputs = sample_inputs()
        seen = []
        marker = BUILD.Evidence(
            source_type="Procedure",
            source_name="Fake",
            source_file="fake.xml",
            target_type="Table",
            target_name="FakeTable",
            relation_kind="fake_relation",
            line=1,
            column=1,
            snippet="fake",
            evidence_role="Fake",
            extractor_rule="fake_rule",
            confidence="high",
        )

        def extract_fake_evidence(objects, *, table_names):
            seen.append((len(objects), sorted(table_names)))
            return [marker]

        record = CORE.ExtractorRecord(
            name="fake",
            rules=("fake_rule",),
            first_version=99,
            source_types=("Procedure",),
            target_types=("Table",),
        )
        call = BUILD.ExtractorCall(
            function=extract_fake_evidence,
            arguments=lambda inputs: ((inputs.objects_in(record.source_types),), {"table_names": inputs.names("Table")}),
        )
        records = CORE.EXTRACTOR_RECORDS + (record,)
        calls = dict(BUILD.EXTRACTOR_CALLS, fake=call)
        baseline = BUILD.run_extractors(inputs, CORE.EXTRACTOR_RECORDS, BUILD.EXTRACTOR_CALLS)
        extended = BUILD.run_extractors(inputs, records, calls)
        procedures = len(inputs.of_type("Procedure"))
        self.assertEqual(seen, [(procedures, sorted(inputs.of_type("Table")))])
        self.assertEqual(extended, baseline + [marker])

    def test_a_record_without_a_call_is_refused(self) -> None:
        record = CORE.ExtractorRecord("missing", ("missing_rule",), 99, ("Procedure",), ("Table",))
        with self.assertRaises(RuntimeError) as raised:
            BUILD.run_extractors(sample_inputs(), CORE.EXTRACTOR_RECORDS + (record,), BUILD.EXTRACTOR_CALLS)
        self.assertIn("missing", str(raised.exception))


class RecordContentTests(unittest.TestCase):
    def test_names_are_unique_and_versions_known(self) -> None:
        names = [record.name for record in CORE.EXTRACTOR_RECORDS]
        self.assertEqual(len(names), len(set(names)))
        current = int(BUILD.EXTRACTOR_SIGNATURE_VERSION)
        for record in CORE.EXTRACTOR_RECORDS:
            with self.subTest(record=record.name):
                self.assertTrue(record.rules and record.source_types and record.target_types)
                self.assertGreaterEqual(record.first_version, CORE.FIRST_RECORDED_EXTRACTOR_VERSION)
                self.assertLessEqual(record.first_version, current)

    def test_every_rule_a_call_writes_on_sample_kb_is_in_its_record(self) -> None:
        inputs = sample_inputs()
        for record in CORE.EXTRACTOR_RECORDS:
            call = BUILD.EXTRACTOR_CALLS[record.name]
            args, kwargs = call.arguments(inputs)
            for evidence in call.function(*args, **kwargs):
                with self.subTest(record=record.name, rule=evidence.extractor_rule):
                    self.assertIn(evidence.extractor_rule, record.rules)
                    self.assertIn(evidence.target_type, record.target_types)
                    self.assertIn(evidence.source_type, record.source_types)

    def test_the_build_selects_its_sources_from_the_records(self) -> None:
        records = {record.name: record for record in CORE.EXTRACTOR_RECORDS}
        # A literal in the build (Test-KbIntelligenceReverseCoverageSelfTest.ps1 reads it there).
        self.assertEqual(BUILD.INDEXED_SOURCE_TYPES, records["evidence"].source_types)
        self.assertEqual(BUILD.INDEXED_SOURCE_TYPES, records["source_external_object_method"].source_types)
        self.assertIs(BUILD.FOR_EACH_SOURCE_TYPES, records["source_for_each_explicit_table"].source_types)
        self.assertIs(BUILD.BC_LOAD_SOURCE_TYPES, records["source_bc_load_transaction"].source_types)
        self.assertIs(BUILD.IDBASEDON_DOMAIN_SOURCE_TYPES, records["idbasedon_domain"].source_types)
        self.assertIs(BUILD.CSS_USAGE_SOURCE_TYPES, records["css_layout_usage"].source_types)
        self.assertEqual(
            set(records["code_attribute"].source_types),
            set(BUILD.CODE_ATTRIBUTE_PART_NAMES) | set(BUILD.CLASSIC_CODE_ATTRIBUTE_SECTIONS),
        )
        self.assertEqual(
            set(records["classic_for_each_base_table"].source_types), set(BUILD.CLASSIC_CODE_ATTRIBUTE_SECTIONS)
        )


class DerivedCoverageTests(unittest.TestCase):
    def test_attribute_use_versions_come_from_the_records(self) -> None:
        self.assertEqual(CORE.ATTRIBUTE_USE_SOURCE_TYPES_EXTRACTED_SINCE, {"Attribute": 21})
        self.assertEqual(
            CORE.attribute_use_source_types_extracted_since(
                CORE.EXTRACTOR_RECORDS, CORE.PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES
            ),
            {"Attribute": 21},
        )

    def test_a_new_attribute_use_record_gates_its_source_type(self) -> None:
        record = CORE.ExtractorRecord("fake", ("fake_rule",), 30, ("Domain",), ("Attribute",))
        derived = CORE.attribute_use_source_types_extracted_since(
            CORE.EXTRACTOR_RECORDS + (record,), CORE.PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES
        )
        self.assertEqual(derived, {"Attribute": 21, "Domain": 30})

    def test_no_partly_extracted_part_predates_the_records_that_read_its_type(self) -> None:
        for object_type, parts in CORE.PARTIALLY_EXTRACTED_ATTRIBUTE_USE_SOURCE_TYPES.items():
            first = min(
                record.first_version
                for record in CORE.EXTRACTOR_RECORDS
                if "Attribute" in record.target_types and object_type in record.source_types
            )
            for part in parts.extracted:
                with self.subTest(object_type=object_type, part=part.name):
                    self.assertGreaterEqual(part.since_version, first)


if __name__ == "__main__":
    unittest.main(verbosity=2)
