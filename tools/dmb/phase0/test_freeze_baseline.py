import struct
import tempfile
import unittest
from pathlib import Path
from freeze_baseline import archive_assets, restore_external_runtime_inputs, inventory


class ArchiveRecovery(unittest.TestCase):
    def entry(self, name, data):
        payload = struct.pack('<BIIII', 0, 123, 0, 0, len(data)) + name + b'\0' + data
        return struct.pack('<IB', len(payload), 1) + payload

    def test_payload_and_windows_separator_recovery(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root/'world.rsc'
            archive.write_bytes(self.entry(b'folder\\asset.txt', b'original\r\nbytes'))
            records = archive_assets(archive, root/'inputs')
            self.assertEqual((root/'inputs/folder/asset.txt').read_bytes(), b'original\r\nbytes')
            self.assertEqual(records[0]['path'], 'folder/asset.txt')

    def test_traversal_is_rejected_before_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root/'world.rsc'
            archive.write_bytes(self.entry(b'../escape.txt', b'bad'))
            with self.assertRaises(ValueError):
                archive_assets(archive, root/'inputs')
            self.assertFalse((root/'escape.txt').exists())

    def test_truncated_record_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root/'world.rsc'
            archive.write_bytes(self.entry(b'asset.txt', b'bytes')[:-1])
            with self.assertRaises(ValueError):
                archive_assets(archive, root/'inputs')


class ExternalRuntimeInputs(unittest.TestCase):
    relative = 'code/modules/unit_tests/data/dq_constraint_parity.json'
    def test_missing_source_refuses(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError): restore_external_runtime_inputs(Path(directory))
    def test_missing_target_restored_and_identical_target_kept(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'source'/self.relative
            source.parent.mkdir(parents=True);source.write_bytes(b'{"pinned":true}')
            rows=restore_external_runtime_inputs(root)
            target=root/'runtime'/self.relative
            self.assertEqual(target.read_bytes(),source.read_bytes())
            before=target.stat().st_mtime_ns
            self.assertEqual(restore_external_runtime_inputs(root),rows)
            self.assertEqual(target.stat().st_mtime_ns,before)
    def test_different_target_refuses_without_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for side,data in [('source',b'pinned'),('runtime',b'existing')]:
                file=root/side/self.relative;file.parent.mkdir(parents=True);file.write_bytes(data)
            with self.assertRaises(ValueError): restore_external_runtime_inputs(root)
            self.assertEqual((root/'runtime'/self.relative).read_bytes(),b'existing')
    def test_inventory_keeps_nested_fixture_not_runtime_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for relative in [self.relative,'data/logs/state.txt']:
                file=root/relative;file.parent.mkdir(parents=True);file.write_bytes(b'fixture')
            self.assertEqual([row['path'] for row in inventory(root)],[self.relative])


if __name__ == '__main__':
    unittest.main()
