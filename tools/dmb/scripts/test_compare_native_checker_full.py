"""All-row comparison and filesystem-free path controls; no oracle invocation."""
import unittest
from pathlib import Path, PurePosixPath, PureWindowsPath
from unittest.mock import patch
import compare_native_checker_full as m
ROOT=PureWindowsPath('E:/frozen/checkout')
class Controls(unittest.TestCase):
 def test_unparsed_and_unattached_diagnostics_cannot_be_silently_dropped(self):
  for text in ["warning: unlocated\n","- unlocated note\n","unexpected configuration error\n"]:
   with self.assertRaises(ValueError):m.reference_rows(text,ROOT)
 def test_selected_phase_envelope_cannot_qualify(self):
  with self.assertRaises(ValueError):m.native_rows({"row":"source_native_original_ordered_checker","full_checker_parity":False},ROOT)
 def test_notes_and_untagged_messages_preserve_order(self):
  rows=m.reference_rows("code/a.dm, line 1, column 2:\nwarning: untagged message\n- first\n- second\n\ncode/a.dm, line 2, column 3:\nerror: other\n",ROOT)
  self.assertEqual([r["message"] for r in rows],["untagged message","other"]);self.assertEqual(rows[0]["notes"],["first","second"])
 def test_reference_summary_and_exit_cannot_hide_dropped_diagnostics(self):
  phases="Analyzing variables...\nGathering proc settings...\nAnalyzing proc bodies...\nAnalyzing proc override validity...\nAnalyzing proc call tree...\n"
  m.require_reference_completion(phases+"Found 0 diagnostics\n",0,[])
  for stdout,code in [("",0),("Found 1 diagnostics\n",0),("Found 0 diagnostics\n",1),("Found 0 diagnostics\nFound 0 diagnostics\n",0)]:
   with self.assertRaises(ValueError):m.require_reference_completion(phases+stdout,code,[])
 def test_parse_only_or_fatal_summary_cannot_claim_checker_completion(self):
  with self.assertRaises(ValueError):m.require_reference_completion("Found 0 diagnostics\n",0,[])
 def test_incomplete_parser_progress_is_not_silently_filtered(self):
  with self.assertRaises(ValueError):m.reference_rows("parsed 0/1 proc bodies (0%)\n",ROOT)
 def test_source_path_normalization_never_resolves_or_stats(self):
  with patch.object(Path,'resolve',side_effect=AssertionError('source resolve forbidden')),patch.object(Path,'stat',side_effect=AssertionError('source stat forbidden')):
   self.assertEqual(m.path_name('code/probe.dm',ROOT),'E:/frozen/checkout/code/probe.dm')
   self.assertEqual(m.path_name(r'E:\frozen\checkout\code\probe.dm',ROOT),'E:/frozen/checkout/code/probe.dm')
   self.assertEqual(m.path_name('(builtins)',ROOT),'(builtins)')
   self.assertEqual(m.path_name('(unknown)',ROOT),'(unknown)')
 def test_absolute_relative_posix_unc_and_windows_spelling_remain_lexical(self):
  self.assertEqual(m.path_name('code/./probe.dm',PurePosixPath('/frozen/checkout')),'/frozen/checkout/code/probe.dm')
  self.assertEqual(m.path_name('/elsewhere/probe.dm',PurePosixPath('/frozen/checkout')),'/elsewhere/probe.dm')
  posix_double=PurePosixPath('//frozen/checkout')
  self.assertIsInstance(m.frozen_root(posix_double),PurePosixPath)
  self.assertNotEqual(m.path_name(r'x\y',posix_double),m.path_name('x/y',posix_double))
  self.assertEqual(m.path_name('code/probe.dm',PureWindowsPath(r'\\server\share\checkout')),'//server/share/checkout/code/probe.dm')
  self.assertEqual(m.path_name('Code/../probe.dm',ROOT),'E:/frozen/checkout/Code/../probe.dm')
  self.assertNotEqual(m.path_name('Code/probe.dm',ROOT),m.path_name('code/probe.dm',ROOT))
  self.assertNotEqual(m.path_name(r'\\?\E:\frozen\checkout\code\probe.dm',ROOT),m.path_name('code/probe.dm',ROOT))
 def test_relative_root_and_ambiguous_windows_paths_cannot_be_guessed(self):
  for root in ['checkout','.',r'E:checkout','//server/share']:
   with self.assertRaises(ValueError):m.frozen_root(root)
  for path in [r'E:code\probe.dm',r'\code\probe.dm']:
   with self.assertRaises(ValueError):m.path_name(path,ROOT)
 def test_documented_crlf_wire_format_preserves_real_completion(self):
  stdout='\r\n'.join(['Analyzing variables...','Gathering proc settings...','Analyzing proc bodies...',
                       'Analyzing proc override validity...','Analyzing proc call tree...','Found 0 diagnostics',''])
  m.require_reference_completion(stdout,0,[])
if __name__=="__main__":unittest.main()
