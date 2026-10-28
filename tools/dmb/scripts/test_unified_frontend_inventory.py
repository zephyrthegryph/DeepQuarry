"""Tests for the source audit, including false-success and lexical traps."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('inventory', Path(__file__).with_name('unified_frontend_inventory.py'))
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


class InventoryTests(unittest.TestCase):
    def test_comments_raw_strings_chars_and_lifetimes(self):
        text = '''// dreammaker::Comment
/* dreammaker::Outer /* nested */ still comment */
let a = r##"dreammaker::Raw \" "# inside"##;
let b = "dreammaker::Escaped \\";
let c = '"';
fn borrow<'a>(v: &'a dreammaker::ast::Block) {}
'''
        code = audit.code_view(text)
        self.assertEqual(len(code), len(text))
        self.assertEqual(code.count('\n'), text.count('\n'))
        self.assertEqual(code.count('dreammaker::'), 1)
        self.assertIn("borrow<'a>", code)
        self.assertIn('&\'a dreammaker::ast::Block', code)

    def test_source_locations_and_content_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / 'consumer.rs'
            path.write_text('// dreammaker::ignored\nuse dreammaker::ast::Block;\n', encoding='utf-8')
            first = audit.file_record(path, root)
            self.assertEqual(first['dependencies']['parser_types'], [2])
            self.assertEqual(first, audit.file_record(path, root))
            path.write_text('use dreammaker::ast::Block;\n', encoding='utf-8')
            self.assertNotEqual(first['sha256'], audit.file_record(path, root)['sha256'])

    def test_missing_checker_is_not_empty_success(self):
        result = audit.checker_inventory(None)
        self.assertEqual(result['status'], 'source_unavailable')
        self.assertIsNone(result['families'])
        self.assertFalse(result['coverage_complete'])

    def test_checker_source_does_not_claim_verified_pin_or_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            crate = root / 'crates/dreamchecker'
            (crate / 'src').mkdir(parents=True)
            (crate / 'Cargo.toml').write_text('[package]\nname = "dreamchecker"\n', encoding='utf-8')
            (crate / 'src/lib.rs').write_text('use dreammaker::ObjectTree;', encoding='utf-8')
            result = audit.checker_inventory(root)
            self.assertEqual(result['status'], 'source_present_pin_not_verified')
            self.assertFalse(result['coverage_complete'])
            self.assertIsNone(result['families'])
            self.assertEqual(len(result['files']), 1)

    def test_wrong_or_empty_checker_source_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(ValueError):
                audit.checker_inventory(root)
            (root / 'Cargo.toml').write_text('[package]\nname = "dreamchecker"\n', encoding='utf-8')
            with self.assertRaises(ValueError):
                audit.checker_inventory(root)

    def test_fixture_inventory_determinism_and_missing_native_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            analyze = root / 'tools/analyze'
            (analyze / 'src/lints').mkdir(parents=True)
            (analyze / 'src/sem').mkdir()
            (analyze / 'Cargo.toml').write_text('[dependencies]\ndreammaker = { path = "vendor/dreammaker" }\n', encoding='utf-8')
            (analyze / 'src/lints/local.rs').write_text('fn scan_tree() { let _: Sem; }', encoding='utf-8')
            (analyze / 'src/sem/mod.rs').write_text('use dreammaker::objtree::ObjectTree;', encoding='utf-8')
            first = audit.inventory(root)
            self.assertEqual(first, audit.inventory(root))
            self.assertEqual(first['consumers']['sem']['direct_parser_files'], 1)
            self.assertEqual(first['consumers']['lints']['semantic_review_files'], 1)
            self.assertEqual(first['native_contracts']['typed_syntax']['status'], 'missing')
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                status = audit.main(['--root', str(root), '--require-checker-source'])
            self.assertEqual(status, 1)
            self.assertEqual(json.loads(output.getvalue())['schema'], audit.SCHEMA)


if __name__ == '__main__':
    unittest.main()
