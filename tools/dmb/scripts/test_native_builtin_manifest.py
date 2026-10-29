import json
from pathlib import Path
import struct
import unittest
from unittest.mock import patch

from native_builtin_manifest import (
    BUILTINS_SHA256, PROC_MACRO_SHA256, Unsupported, build_manifest,
    build_rust_hierarchy, extract_declarations, hierarchy, main, rust_string, sha256,
)


def table(body):
    return "fn register() { builtins_table! {\n" + body + "\n}; }"


class NativeBuiltinManifestTests(unittest.TestCase):
    def pinned_inputs(self):
        tools = Path(__file__).resolve().parents[2]
        return ((tools / "analyze/vendor/dreammaker/src/builtins.rs").read_bytes(),
                (tools / "analyze/vendor/builtins-proc-macro/src/lib.rs").read_bytes())

    def test_inherited_paths_attributes_flags_and_rust_defaults(self):
        declarations = extract_declarations(table(r'''
datum;
#[dm_ref("/datum/vars")] datum {
    var/const/list/vars;
    var/tmp/name = string!("semi; colon, and \"quote\"");
    proc/Read(F = 7);
}
datum/parent_type = path!(/datum/base);
'''))
        self.assertEqual([row["kind"] for row in declarations],
                         ["type", "field", "field", "callable", "field"])
        field = declarations[1]
        self.assertEqual((field["owner"], field["name"], field["type_path"]),
                         ("/datum", "vars", ["list"]))
        self.assertEqual(field["flags"], ["const"])
        self.assertEqual(field["reference_flag_bits"], 4)
        self.assertEqual(field["attributes"], [{"name": "dm_ref", "value": "/datum/vars"}])
        self.assertEqual(declarations[2]["default"]["constant"]["value"],
                         'semi; colon, and "quote"')
        self.assertEqual(declarations[4]["form"], "override")
        self.assertIsNone(declarations[4]["type_path"])
        self.assertEqual(declarations[4]["default"]["constant"],
                         {"kind": "type_path", "value": "/datum/base"})

    def test_parameter_comments_and_authored_defaults_are_not_effective_types_or_defaults(self):
        procedure = extract_declarations(table('proc/Example(/*atom*/A/*=usr*/, B=1, C=world.view, D="text");'))[0]
        self.assertEqual(procedure["owner"], "/")
        self.assertEqual([parameter["name"] for parameter in procedure["parameters"]], ["A", "B", "C", "D"])
        self.assertEqual([parameter["source_default_syntax"] for parameter in procedure["parameters"]],
                         [None, "1", "world.view", '"text"'])
        for parameter in procedure["parameters"]:
            self.assertEqual(parameter["type_path"], [])
            self.assertIsNone(parameter["default"])
        self.assertIsNone(procedure["return_annotation"])
        self.assertTrue(procedure["source_parameter_defaults_discarded"])
        self.assertEqual(procedure["variadic"], "not_expressed_by_reference_dsl")

    def test_comments_and_strings_cannot_forge_declarations(self):
        source = '''
const DM_VERSION: i32 = 516;
const DM_BUILD: i32 = 1666;
// builtins_table! { proc/fake(); }
fn register() { builtins_table! {
    /* nested /* proc/fake(); */ comment */
    var/text = string!("} builtins_table! { proc/fake();");
    var/version = int!(DM_VERSION);
}; }
'''
        declarations = extract_declarations(source)
        self.assertEqual([row["name"] for row in declarations], ["text", "version"])
        bits = struct.unpack("<I", struct.pack("<f", 516))[0]
        self.assertEqual(declarations[1]["default"]["constant"], {"kind": "number", "f32_bits": bits})

    def test_unknown_constructs_fail_instead_of_emitting_partial_data(self):
        for body in [
            'datum; var/value = unknown!(1);',
            'datum; proc/Example(value = effect());',
            'datum; proc/Example() as num;',
            '#[cfg(feature = "extra")] datum;',
            '#[] datum;',
            'datum; var/value = int!(UNKNOWN);',
            'datum; var/const;',
            'datum; proc/Example(atom/value);',
        ]:
            with self.subTest(body=body), self.assertRaises(Unsupported):
                extract_declarations(table(body))
        with self.assertRaises(Unsupported):
            extract_declarations("fn register() { builtins_table! { datum;")

    def test_hierarchy_replays_reference_rules_and_encounter_order(self):
        declarations = extract_declarations(table('''
datum; list; world; client/var/const/parent_type;
atom/parent_type = path!(/datum);
atom/movable; obj/parent_type = path!(/atom/movable);
image; mutable_appearance/parent_type = path!(/image);
'''))
        types = hierarchy(declarations)
        self.assertEqual([row["path"] for row in types],
                         ["/", "/datum", "/list", "/world", "/client", "/atom", "/atom/movable", "/obj", "/image", "/mutable_appearance"])
        parents = {row["path"]: row["parent"] for row in types}
        self.assertEqual(parents["/client"], "/")
        self.assertEqual(parents["/list"], "/")
        self.assertEqual(parents["/obj"], "/atom/movable")
        self.assertEqual(parents["/image"], "/datum")
        self.assertEqual(parents["/mutable_appearance"], "/image")

    def test_duplicate_names_and_implicit_method_form_stay_in_declaration_order(self):
        declarations = extract_declarations(table('datum; datum/New(A); datum/proc/Example(x, x); datum/verb/Choose();'))
        self.assertEqual(declarations[1]["form"], "implicit")
        self.assertEqual(declarations[1]["callable_kind"], "proc")
        self.assertEqual([row["name"] for row in declarations[2]["parameters"]], ["x", "x"])
        self.assertEqual(declarations[3]["callable_kind"], "verb")
        self.assertEqual([row["ordinal"] for row in declarations], [0, 1, 2, 3])

    def test_rust_literal_escapes_are_not_interpreted_as_dm_escapes(self):
        self.assertEqual(rust_string(r'"\u{41}\x42\n"'), "AB\n")
        self.assertEqual(rust_string('r#"[literal]\\n"#'), "[literal]\\n")
        with self.assertRaises(Unsupported):
            rust_string(r'"\q"')

    def test_complete_pinned_catalog_remains_incomplete_for_runtime_engine_inventory(self):
        tools = Path(__file__).resolve().parents[2]
        source = (tools / "analyze/vendor/dreammaker/src/builtins.rs").read_bytes()
        macro = (tools / "analyze/vendor/builtins-proc-macro/src/lib.rs").read_bytes()
        self.assertEqual(sha256(source), BUILTINS_SHA256)
        self.assertEqual(sha256(macro), PROC_MACRO_SHA256)
        manifest = build_manifest(source, macro)
        self.assertTrue(manifest["coverage"]["pinned_dsl_declarations_complete"])
        self.assertFalse(manifest["coverage"]["runtime_engine_inventory_complete"])
        self.assertFalse(manifest["coverage"]["runtime_slots_or_abi"])
        self.assertGreater(manifest["counts"]["field"], 200)
        self.assertGreater(manifest["counts"]["callable"], 200)
        self.assertEqual(json.dumps(manifest, sort_keys=True), json.dumps(build_manifest(source, macro), sort_keys=True))
        with self.assertRaisesRegex(Unsupported, "source bytes"):
            build_manifest(source + b"\n", macro)
        with self.assertRaisesRegex(Unsupported, "proc-macro bytes"):
            build_manifest(source, macro + b"\n")

    def test_rust_hierarchy_has_only_exact_pinned_parents_and_provenance(self):
        source, macro = self.pinned_inputs()
        rust = build_rust_hierarchy(source, macro)
        manifest = build_manifest(source, macro)
        for row in manifest["types"]:
            expected = f'    ("{row["path"]}", ' + (f'Some("{row["parent"]}")' if row["parent"] is not None else "None") + "),"
            self.assertIn(expected, rust)
        self.assertEqual(sum(line.startswith('    ("/') for line in rust.splitlines()), 28)
        for hash_value in [BUILTINS_SHA256, PROC_MACRO_SHA256]:
            self.assertIn(hash_value, rust)
        self.assertIn("MEMBER_INVENTORY_COMPLETE: bool = false", rust)
        self.assertIn("intrinsics: Arc::from([])", rust)
        self.assertIn("fields: Arc::from([])", rust)
        self.assertIn("pub fn seed() -> EngineSeed", rust)
        self.assertNotIn("serde_json", rust)
        self.assertNotIn("IntrinsicMember {", rust)

    def test_rust_hierarchy_is_deterministic_and_matches_generated_source(self):
        source, macro = self.pinned_inputs()
        first = build_rust_hierarchy(source, macro)
        self.assertEqual(first, build_rust_hierarchy(source, macro))
        generated = Path(__file__).resolve().parents[1] / "crates/dm-analysis/examples/support/reference_hierarchy.rs"
        self.assertEqual(generated.read_text(encoding="utf-8"), first)

    def test_rust_hierarchy_rejects_unpinned_input_before_output(self):
        source, macro = self.pinned_inputs()
        for builtin, proc_macro in [(source+b"\n", macro), (source, macro+b"\n")]:
            with self.assertRaises(Unsupported):
                build_rust_hierarchy(builtin, proc_macro)
        with patch("native_builtin_manifest.Path.read_bytes", return_value=source+b"\n"), \
                patch("native_builtin_manifest.Path.write_text") as output:
            self.assertEqual(main(["--rust-hierarchy-output", "E:/unused-seed.rs"]), 2)
            output.assert_not_called()

    def test_rust_output_option_cannot_be_combined_with_manifest_output(self):
        for other in ["--output", "--check"]:
            with self.assertRaises(SystemExit):
                main(["--rust-hierarchy-output", "E:/unused-seed.rs", other, "E:/unused.json"])


class NativeCheckerCatalogTests(unittest.TestCase):
    def pinned_inputs(self):
        return NativeBuiltinManifestTests().pinned_inputs()

    def test_checker_catalog_preserves_exact_fixed_metadata_and_not_runtime_claims(self):
        from native_builtin_manifest import build_rust_checker_catalog, checker_catalog_rows
        source, macro = self.pinned_inputs()
        manifest = build_manifest(source, macro)
        rows = checker_catalog_rows(manifest)
        self.assertEqual(len(rows), 842)
        self.assertEqual(sum(r["kind"] in (2, 3) for r in rows), 378)
        self.assertEqual(sum(r["kind"] == 1 for r in rows), 444)
        north = next(r for r in rows if r["owner"] == "/" and r["name"] == "NORTH")
        self.assertEqual((north["flags"], north["reference_flags"]), (2, 4))
        self.assertEqual(north["default"]["f32_bits"], struct.unpack("<I", struct.pack("<f", 1))[0])
        rust = build_rust_checker_catalog(source, macro)
        self.assertIn("NEVER runtime ABI/slot completeness", rust)
        self.assertNotIn("EngineSeed", rust)
        self.assertIn("source_default:", rust)

    def test_checker_catalog_is_deterministic_and_hash_matches_rust_importer(self):
        from native_builtin_manifest import build_rust_checker_catalog, checker_catalog_bytes, checker_catalog_rows
        source, macro = self.pinned_inputs()
        rust = build_rust_checker_catalog(source, macro)
        self.assertEqual(rust, build_rust_checker_catalog(source, macro))
        directory = Path(__file__).resolve().parents[1] / "crates/dm-tree/src"
        self.assertEqual((directory / "checker_builtin_data.rs").read_text(encoding="utf-8"), rust)
        manifest = build_manifest(source, macro)
        digest = sha256(checker_catalog_bytes(manifest, checker_catalog_rows(manifest)))
        self.assertIn(digest, rust)
        self.assertIn(digest, (directory / "checker_builtins.rs").read_text(encoding="utf-8"))
        changed = checker_catalog_rows(manifest)
        changed[0]["name"] = "forged"
        self.assertNotEqual(sha256(checker_catalog_bytes(manifest, changed)), digest)

    def test_checker_import_refuses_unpinned_inputs_and_unrepresentable_metadata(self):
        from copy import deepcopy
        from native_builtin_manifest import build_rust_checker_catalog, checker_catalog_rows
        source, macro = self.pinned_inputs()
        for original, interpretation in [(source+b"\n", macro), (source, macro+b"\n")]:
            with self.assertRaises(Unsupported):
                build_rust_checker_catalog(original, interpretation)
        manifest = build_manifest(source, macro)
        changed = deepcopy(manifest)
        next(r for r in changed["declarations"] if r["kind"] == "field" and r["flags"] is not None)["flags"].append("private")
        with self.assertRaisesRegex(Unsupported, "flag"):
            checker_catalog_rows(changed)
        changed = deepcopy(manifest)
        next(r for r in changed["declarations"] if r["kind"] == "callable")["return_annotation"] = "num"
        with self.assertRaisesRegex(Unsupported, "callable metadata"):
            checker_catalog_rows(changed)


if __name__ == "__main__":
    unittest.main()
