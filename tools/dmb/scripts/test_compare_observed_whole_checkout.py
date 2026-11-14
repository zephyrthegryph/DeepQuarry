"""Held comparator format controls only, not fake native source authority."""
import importlib.util,unittest,struct,json,tempfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('captured',Path(__file__).with_name('compare_observed_whole_checkout.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class Formats(unittest.TestCase):
 def test_empty_analyze_refuses(self):
  with self.assertRaises(ValueError):m.parse_analyze(b'',False)
 def test_final_result_does_not_replace_unused_roster(self):
  with self.assertRaises(ValueError):m.parse_analyze(b'All ratchet lints passed.\n',False)
 def test_unknown_note_is_preserved_not_filtered(self):
  text=b'unknown producer note\n  nested explanation\nallow annotations: 0 unused\nAll ratchet lints passed.\n'
  self.assertEqual(m.parse_analyze(text,False)['lines'][:2],['unknown producer note','  nested explanation'])
 def test_ci_requires_balanced_actual_groups(self):
  with self.assertRaises(ValueError):m.parse_analyze(b'::group::actual\nallow annotations: 0 unused\nAll ratchet lints passed.\n',True)
 def test_journal_requires_actual_witness_and_exact_eof(self):
  record=struct.pack('<BIIQ',3,0,len(b'actions'),0)+b'actions';payload=b'DQGENJ01'+struct.pack('<QQ',1,40+len(record))+bytes(16)+record
  h=dict(journal_length=len(payload),journal_records=1,journal_records_hash='0'*32,names=['actions'])
  self.assertEqual(m.journal(payload,h)[0]['path'],'actions')
  with self.assertRaises(ValueError):m.journal(payload+b'x',h)
 def test_unknown_record_kind_is_not_skipped(self):
  record=struct.pack('<BIIQ',9,0,0,0);payload=b'DQGENJ01'+struct.pack('<QQ',1,57)+bytes(16)+record
  with self.assertRaises(ValueError):m.journal(payload,dict(journal_length=57,journal_records=1,journal_records_hash='0'*32,names=[]))
 def test_full_generator_notes_order_and_states_render(self):
  rows=[dict(generator='actions',path='actual',state='fresh')];diags=[dict(generator='actions',relative='source.dm',line=7,message='first\n  note')]
  self.assertEqual(m.expected_generator_text(rows,diags,['actions']),b'source.dm:7: [gen/actions] first\n  note\nfresh actual\n')
 def test_changed_capture_manifest_cannot_be_relabelled_as_original(self):
  with tempfile.TemporaryDirectory(dir='E:/dq-cache/test-scratch',prefix='observed-format-only-')as scratch:
   path=Path(scratch)/'capture.json';raw=json.dumps(dict(completed=True,callback_ran=True,oracle_sha256=m.ORACLE,artifacts_sha256={})).encode();path.write_bytes(raw)
   captured=m.Captured(scratch);self.assertEqual(captured.capture_sha256,m.digest(raw));path.write_bytes(raw+b' ')
   with self.assertRaises(ValueError):captured.verify_again()
 def test_check_written_state_refuses(self):
  with self.assertRaises(ValueError):m.expected_generator_text([dict(generator='actions',path='actual',state='written')],[],['actions'])
if __name__=='__main__':unittest.main()
