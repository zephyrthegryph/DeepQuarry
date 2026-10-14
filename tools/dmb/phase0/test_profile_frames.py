import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class SamplingFrames(unittest.TestCase):
    def test_equal_addresses_in_different_libraries_resolve_independently(self):
        profile = {
            'libs': [{'name': 'dm-compile.exe', 'debugName': 'compiler.pdb', 'breakpadId': 'AA1'},
                     {'name': 'kernel.dll', 'debugName': 'kernel.pdb', 'breakpadId': 'BB1'}],
            'threads': [{'name': 'worker', 'stringArray': ['0x1000'],
                         'samples': {'stack': [1], 'time': [0], 'weight': [1]},
                         'stackTable': {'frame': [0, 1], 'prefix': [None, 0]},
                         'frameTable': {'func': [0, 1], 'address': [4096, 4096]},
                         'funcTable': {'name': [0, 0], 'resource': [0, 1]},
                         'resourceTable': {'lib': [0, 1]}}]}
        sidecar = {'string_table': ['compiler::lower', 'kernel::wait'], 'data': [
            {'debug_name': 'compiler.pdb', 'debug_id': 'AA1',
             'known_addresses': [[4096, 0]], 'symbol_table': [{'symbol': 0}]},
            {'debug_name': 'kernel.pdb', 'debug_id': 'BB1',
             'known_addresses': [[4096, 0]], 'symbol_table': [{'symbol': 1}]}]}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'profile.json').write_text(json.dumps(profile))
            (root/'symbols.json').write_text(json.dumps(sidecar))
            subprocess.run([sys.executable, str(Path(__file__).with_name('profile_frames.py')),
                            str(root/'profile.json'), '--symbols', str(root/'symbols.json'),
                            '--output', str(root/'report.json')], check=True)
            result = json.loads((root/'report.json').read_text())
            names = {row['frame'] for row in result['top10_inclusive']}
            self.assertEqual(names, {'compiler::lower', 'kernel::wait'})
            self.assertEqual(result['symbol_coverage']['unresolved_frame_observations'], 0)
            self.assertFalse(result['top10_named_frames_gate_passed'])


if __name__ == '__main__':
    unittest.main()
