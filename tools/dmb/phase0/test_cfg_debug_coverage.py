import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from cfg_debug_coverage import inspect_procedure, report


def row(offset, successors, kind='ordinary', **values):
    return dict(offset=offset, successors=successors, kind=kind, **values)


class CoverageTests(unittest.TestCase):
    def test_join_agreement(self):
        for right, expected in [(10, True), (11, False)]:
            value = inspect_procedure(dict(identity='body0', instructions=[
                row(0, [1], 'DbgFile', file_bytes_hex='61'),
                row(1, [2, 3], 'DbgLine', line=10), row(2, [4]),
                row(3, [4], 'DbgLine', line=right), row(4, [])]))
            self.assertEqual(value['instructions'][-1]['located_on_all_incoming_paths'], expected)
            self.assertEqual(value['unknown_joins'], [] if expected else [4])

    def test_loop_and_file_switch(self):
        value = inspect_procedure(dict(identity='loop', instructions=[
            row(0, [1], 'DbgFile', file_bytes_hex='61'),
            row(1, [2], 'DbgLine', line=9), row(2, [1, 3]),
            row(3, [4], 'DbgFile', file_bytes_hex='62'), row(4, []), row(5, [])]))
        self.assertTrue(value['instructions'][2]['located_on_all_incoming_paths'])
        self.assertFalse(value['instructions'][4]['located_on_all_incoming_paths'])
        self.assertFalse(value['instructions'][5]['reachable'])

    def test_edges_required(self):
        for rows in [[dict(offset=0, kind='ordinary')], [row(0, [1])]]:
            with self.assertRaises(ValueError):
                inspect_procedure(dict(identity='bad', instructions=rows))

    def test_hash_binding(self):
        with tempfile.TemporaryDirectory() as directory:
            dmb = Path(directory) / 'input.dmb'
            sidecar = Path(directory) / 'decoded.json'
            dmb.write_bytes(b'authored-tiny')
            sidecar.write_text(json.dumps(dict(dmb_sha256=hashlib.sha256(dmb.read_bytes()).hexdigest(), procedures=[])))
            self.assertFalse(report(dmb, sidecar)['runtime_ownership_certified'])
            dmb.write_bytes(b'changed')
            with self.assertRaises(ValueError):
                report(dmb, sidecar)


if __name__ == '__main__':
    unittest.main()
