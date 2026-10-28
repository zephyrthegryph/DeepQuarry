import unittest
from checker_coverage_inventory import sites


class CoverageInventoryTests(unittest.TestCase):
    def test_comments_strings_and_untagged_constructions_are_accounted_separately(self):
        source = '''
// error(x, "ignored").with_errortype("ignored");
fn check_var_defs() {
    let example = r#"error(x, "ignored").with_errortype("ignored")"#;
    error(loc, "typed").with_errortype("final_var").register(context);
    error(loc, format!("untagged {value}")).register(context);
}
'''
        result = sites(source, 'checker.rs')
        self.assertEqual([site['family'] for site in result['families']], ['final_var'])
        self.assertEqual(len(result['construction_sites']), 2)
        self.assertTrue(all(site['destination'] == 'native declaration queries'
                            for site in result['construction_sites']))
        self.assertEqual(result['families'][0]['line'], 5)

    def test_recursive_passes_are_not_assigned_to_ordinary_blocking_queries(self):
        source = '''fn check_proc_call_tree() {
            error(loc, message).with_errortype("must_not_sleep");
        }'''
        result = sites(source, 'checker.rs')
        self.assertEqual(result['families'][0]['destination'],
                         'native SCC inference and retractable call contributions')

    def test_error_helper_definition_is_not_a_construction_site(self):
        source = 'fn error(location: Location, message: String) -> DMError { DMError::new(location, message) }'
        self.assertEqual(len(sites(source, 'checker.rs')['construction_sites']), 1)


if __name__ == '__main__':
    unittest.main()
