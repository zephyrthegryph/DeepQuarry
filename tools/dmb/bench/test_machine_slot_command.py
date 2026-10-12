"""Pure command policy/owned marker checks; no slot or heavy child execution."""
import tempfile,unittest
from pathlib import Path
from unittest.mock import patch
import machine_slot_command as slots
class Slots(unittest.TestCase):
    def test_queue_wait_keeps_same_child_job_and_explicit_capacities(self):
        with patch.object(slots,'tool_pin',side_effect=lambda p,s:{'path':str(p),'sha256':s,'bytes':1}):
            plan=slots.slot_command('cargo',['E:/cargo/bin/cargo.exe','build'],'E:/projects/dq-wt/dmb-review',
                {'DQ_SLOTS':'0','DQ_SLOTS_CARGO':'9','DQ_SLOT_PRIORITY':'0'},label='owned Cargo')
        self.assertEqual(plan['command'][-2:],['E:/cargo/bin/cargo.exe','build'])
        self.assertEqual(plan['environment']['DQ_SLOTS_CARGO'],'1')
        self.assertEqual(plan['environment']['DQ_SLOTS_TEST_WORLD'],'3')
        self.assertNotIn('DQ_SLOT_PRIORITY',plan['environment'])
        self.assertTrue(plan['evidence']['waitIncludedInOwnedChildDeadline'])
        for command in (['bash','tools/build/build.sh','dm-test'],['python','runtime-suite.py']):
            with self.assertRaises(ValueError):slots.slot_command('cargo',command,'E:/projects/dq-wt/dmb-review',{},label='nested')
        with self.assertRaises(ValueError):slots.slot_command('test_world',['dd.exe'],'E:/projects/dq-wt/dmb-review',{},label='raw tiny fixture')
    def test_existing_targets_require_same_explicit_workspace_owner(self):
        with tempfile.TemporaryDirectory(dir='E:/dq-cache',prefix='slot-policy-') as root:
            target=Path(root)/'target'
            slots.claim_workspace_target(target,'E:/projects/dq-wt/dmb-review')
            slots.claim_workspace_target(target,'E:/projects/dq-wt/dmb-review')
            with self.assertRaises(ValueError):slots.claim_workspace_target(target,'E:/projects/CHOMPStation2')
            unmarked=Path(root)/'unmarked';unmarked.mkdir()
            with self.assertRaises(FileNotFoundError):slots.claim_workspace_target(unmarked,'E:/projects/dq-wt/dmb-review')
if __name__=='__main__':unittest.main()
