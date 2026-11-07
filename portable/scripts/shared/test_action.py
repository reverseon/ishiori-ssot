import unittest

from action import Action, ActionError, Status, run_actions


class Fake(Action):
    def __init__(self, name="fake", pre=False, post=True, boom=False, ignore=False):
        super().__init__(name=name)
        self.pre, self.post, self.boom = pre, post, boom
        self.continue_on_error = ignore
        self.ran = False

    def precheck(self):
        return self.pre

    def run(self):
        self.ran = True
        if self.boom:
            raise OSError("boom")

    def postcheck(self):
        return self.post


class Unchecked(Fake):
    def verifiable(self):
        return False

    def postcheck(self):
        raise AssertionError("postcheck must not be called")


class ActionTest(unittest.TestCase):
    def test_skips_when_precheck_true(self):
        a = Fake(
            pre=True,
        )
        self.assertEqual(a.execute().status, Status.SKIPPED)
        self.assertFalse(a.ran)

    def test_runs_and_verifies(self):
        a = Fake()
        self.assertEqual(a.execute().status, Status.CHANGED)
        self.assertTrue(a.ran)

    def test_unverifiable_is_unverified_not_changed(self):
        a = Unchecked()
        self.assertEqual(a.execute().status, Status.UNVERIFIED)
        self.assertTrue(a.ran)

    def test_unverifiable_still_skips_when_precheck_true(self):
        a = Unchecked(
            pre=True,
        )
        self.assertEqual(a.execute().status, Status.SKIPPED)

    def test_postcheck_failure_raises(self):
        with self.assertRaises(ActionError):
            Fake(
                post=False,
            ).execute()

    def test_run_failure_wrapped(self):
        with self.assertRaises(ActionError):
            Fake(
                boom=True,
            ).execute()

    def test_continue_on_error(self):
        action = Fake(
            boom=True,
            ignore=True,
        )
        self.assertEqual(action.execute().status, Status.FAILED)

    def test_runner_aborts_on_failure(self):
        later = Fake(
            name="later",
        )
        with self.assertRaises(ActionError):
            run_actions([
                Fake(
                    name="bad",
                    boom=True,
                ),
                later,
            ])
        self.assertFalse(later.ran)


class LogTest(unittest.TestCase):
    def test_tagged_phase_lines(self):
        a = Fake(
            name="x",
        )
        a.section = "ssh"
        with self.assertLogs("action", "INFO") as cm:
            a.execute()
        text = " | ".join(cm.output)
        for expected in ("[ssh][Precheck]", "[ssh][Run]", "[ssh][Postcheck]", "not satisfied"):
            self.assertIn(expected, text)

    def test_unverified_logs_skipped_postcheck(self):
        with self.assertLogs("action", "INFO") as cm:
            Unchecked().execute()
        self.assertIn("skipped (no check defined)", " | ".join(cm.output))

    def test_skip_and_failure_logged(self):
        with self.assertLogs("action", "INFO") as cm:
            Fake(
                pre=True,
            ).execute()
        self.assertIn("satisfied, skipping", cm.output[0])
        with self.assertLogs("action", "ERROR") as cm:
            with self.assertRaises(ActionError):
                Fake(
                    post=False,
                ).execute()
        self.assertIn("[-][Postcheck]", cm.output[0])


if __name__ == "__main__":
    unittest.main()
