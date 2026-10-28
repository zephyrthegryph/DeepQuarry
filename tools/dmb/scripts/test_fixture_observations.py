import unittest
from fixture_observations import require_unchanged, observation_digest

class FixtureObservationTests(unittest.TestCase):
    def test_unchanged_bytes_allow_different_dictionary_order(self):
        left = {"a.dm": "a", "b.dme": "b"}
        right = {"b.dme": "b", "a.dm": "a"}
        require_unchanged(left, right)
        self.assertEqual(observation_digest(left), observation_digest(right))

    def test_edits_additions_and_removals_reject_the_observation(self):
        original = {"code/a.dm": "first"}
        for changed in ({"code/a.dm": "edited"}, {},
                        {"code/a.dm": "first", "code/new.dm": "new"}):
            with self.assertRaisesRegex(ValueError, "inputs changed"):
                require_unchanged(original, changed)

    def test_digest_names_files_not_just_the_bag_of_contents(self):
        self.assertNotEqual(observation_digest({"a.dm": "x"}), observation_digest({"b.dm": "x"}))

if __name__ == "__main__":
    unittest.main()
