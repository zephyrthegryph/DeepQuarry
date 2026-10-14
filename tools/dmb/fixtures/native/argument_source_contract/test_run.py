"""Metadata policy only; direct world calls do not prove prompt/helper execution."""
import unittest
from run import validate_helper_formals
class HelperFormals(unittest.TestCase):
    def test_current_and_dynamic_formals_are_separately_authenticated(self):
        current=[{'name':'value','type_flags':0,'value_source':0,'reserved':0}]
        validate_helper_formals([('current_source',0)], current)
        validate_helper_formals([('dynamic_source',0)], [])
        validate_helper_formals([('first_source',0)], [])
        validate_helper_formals([('earlier',1)], [{**current[0], 'name':'first'}])
        for binding,rows in [([('current_source',0)],[]),([('dynamic_source',0)],current),
                             ([('current_source',0)],[{**current[0], 'type_flags':8}])]:
            with self.assertRaises(ValueError): validate_helper_formals(binding,rows)
if __name__=='__main__': unittest.main()
