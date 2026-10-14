from pathlib import Path
import unittest
from worktree_authority import authenticate


class AuthorityTests(unittest.TestCase):
    def setup(self):
        roots = [Path(f"E:/projects/dq-wt/authority-{index}") for index in range(6)]
        facts = {str(root): [str(root.resolve()), "E:/projects/main/.git",
                            f"E:/projects/main/.git/worktrees/authority-{index}", str(index + 1) * 40]
                 for index, root in enumerate(roots)}
        registrations = [{"worktree": str(root.resolve()), "HEAD": facts[str(root)][3],
                          "branch": f"refs/heads/branch-{index}"} for index, root in enumerate(roots)]
        calls = []

        def run(root, arguments, timeout):
            calls.append((root, arguments, timeout))
            if arguments[0] == "rev-parse":
                return "\n".join(facts[str(root)]) + "\n"
            return "".join("\0".join(f"{key} {value}" for key, value in row.items()) + "\0\0" for row in registrations)

        return roots, facts, registrations, calls, run

    def test_six_registered_roots_have_exact_head_and_private_authority(self):
        roots, _, _, calls, run = self.setup()
        proof = authenticate(roots, run)
        self.assertEqual(proof["status"], "passed")
        self.assertEqual(len(proof["worktrees"]), 6)
        self.assertEqual(proof["worktrees"][3]["head"], "4" * 40)
        self.assertEqual(proof["worktrees"][3]["branch"], "refs/heads/branch-3")
        self.assertEqual(len(calls), 7)
        self.assertTrue(all(0 < timeout <= 10 for _, _, timeout in calls))

    def test_unregistered_or_changed_head_cannot_claim_six_worktrees(self):
        for change in ("missing", "changed", "prunable"):
            roots, _, registrations, _, run = self.setup()
            if change == "missing":
                registrations.pop()
            elif change == "changed":
                registrations[-1]["HEAD"] = "a" * 40
            else:
                registrations[-1]["prunable"] = "missing worktree"
            with self.assertRaises(ValueError):
                authenticate(roots, run)

    def test_private_alias_foreign_repo_and_nonroot_are_rejected(self):
        for index, value in ((2, "E:/projects/main/.git/worktrees/authority-0"),
                             (1, "E:/projects/foreign/.git"), (0, "E:/projects/another-root")):
            roots, facts, _, _, run = self.setup()
            facts[str(roots[-1])][index] = value
            with self.assertRaises(ValueError):
                authenticate(roots, run)

    def test_count_and_canonical_aliases_fail_before_git(self):
        roots, _, _, calls, run = self.setup()
        with self.assertRaises(ValueError):
            authenticate(roots[:5], run)
        roots[-1] = roots[0]
        with self.assertRaises(ValueError):
            authenticate(roots, run)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
