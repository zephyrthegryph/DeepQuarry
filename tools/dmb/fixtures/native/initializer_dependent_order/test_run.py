"""Pure observation admission tests; never compile or host a fixture."""
import unittest,tempfile
from pathlib import Path
from run import observations
class Observation(unittest.TestCase):
    def test_requires_values_effect_order_finish_and_no_runtime(self):
        good='DQ_INIT_ORDER values first=11 second=12 trace=first=11;second=12; resource=contract-resource.txt\nDQ_INIT_ORDER PASS\nDQ_INIT_ORDER finished\n'
        with tempfile.TemporaryDirectory() as root:
            file=Path(root)/'world.log';file.write_text(good)
            self.assertEqual(observations(file)['runtimes'],{})
            for bad in (good.replace('second=12','second=1'),good.replace('first=11;second=12;','second=12;first=11;'),good.replace('DQ_INIT_ORDER finished\n',''),good+'runtime error: failed\n'):
                file.write_text(bad)
                with self.assertRaises(ValueError):observations(file)
if __name__=='__main__':unittest.main()
