import importlib.util,tempfile,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('observable_order',Path(__file__).with_name('run.py'))
runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)
class Observations(unittest.TestCase):
    def test_preserves_observed_order_without_assumed_golden(self):
        with tempfile.TemporaryDirectory() as directory:
            log=Path(directory)/'world.log'
            rows=['boot trace=procedure;global-second;','holder vars=a_second;z_first;','procedure result=procedure','types=/datum/orderkind/a_second;/datum/orderkind/z_first;','finished']
            log.write_text('\n'.join('DQ_VISIBLE_ORDER '+row for row in rows))
            self.assertEqual(runner.observations(log)['markers'],['DQ_VISIBLE_ORDER '+row for row in rows])
            log.write_text(log.read_text()+'\nruntime error: broken')
            with self.assertRaises(ValueError):runner.observations(log)
if __name__=='__main__':unittest.main()
