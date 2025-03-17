import asyncio
import os
import pathlib
import subprocess
import tempfile
import unittest.mock

from oeqa.selftest.case import OESelftestTestCase

runfvp = pathlib.Path(__file__).parents[5] / "scripts" / "runfvp"
testdir = pathlib.Path(__file__).parent / "tests"

class RunFVPTests(OESelftestTestCase):
    def setUpLocal(self):
        self.assertTrue(runfvp.exists())

    def run_fvp(self, *args, should_succeed=True):
        """
        Call runfvp passing any arguments. If check is True verify return stdout
        on exit code 0 or fail the test, otherwise return the CompletedProcess
        instance.
        """
        cli = [runfvp,] + list(args)
        print(f"Calling {cli}")
        # Set cwd to testdir so that any mock FVPs are found
        ret = subprocess.run(cli, cwd=testdir, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
        if should_succeed:
            self.assertEqual(ret.returncode, 0, f"runfvp exit {ret.returncode}, output: {ret.stdout}")
            return ret.stdout
        else:
            self.assertNotEqual(ret.returncode, 0, f"runfvp exit {ret.returncode}, output: {ret.stdout}")
            return ret.stdout

    def test_help(self):
        output = self.run_fvp("--help")
        self.assertIn("Run images in a FVP", output)

    def test_bad_options(self):
        self.run_fvp("--this-is-an-invalid-option", should_succeed=False)

    def test_run_auto_tests(self):
        cases = list(testdir.glob("auto-*.json"))
        if not cases:
            self.fail("No tests found")
        for case in cases:
            with self.subTest(case=case.stem):
                self.run_fvp(case)

    def test_fvp_options(self):
        # test-parameter sets one argument, add another manually
        self.run_fvp(testdir / "test-parameter.json", "--", "--parameter", "board.dog=woof")

class ConfFileTests(OESelftestTestCase):
    def test_no_exe(self):
        from fvp import conffile
        with tempfile.NamedTemporaryFile('w') as tf:
            tf.write('{}')
            tf.flush()

            with self.assertRaises(ValueError):
                conffile.load(tf.name)

    def test_minimal(self):
        from fvp import conffile
        with tempfile.NamedTemporaryFile('w') as tf:
            tf.write('{"exe": "FVP_Binary"}')
            tf.flush()

            conf = conffile.load(tf.name)
            self.assertTrue('fvp-bindir' in conf)
            self.assertTrue('fvp-bindir' in conf)
            self.assertTrue("exe" in conf)
            self.assertTrue("parameters" in conf)
            self.assertTrue("data" in conf)
            self.assertTrue("applications" in conf)
            self.assertTrue("terminals" in conf)
            self.assertTrue("args" in conf)
            self.assertTrue("consoles" in conf)
            self.assertTrue("env" in conf)


class RunnerTests(OESelftestTestCase):
    def create_mock(self):
        return unittest.mock.patch("asyncio.create_subprocess_exec")

    def test_start(self):
        from fvp import runner
        with self.create_mock() as m:
            fvp = runner.FVPRunner(self.logger)
            asyncio.run(fvp.start({
                "fvp-bindir": "/usr/bin",
                "exe": "FVP_Binary",
                "parameters": {'foo': 'bar'},
                "data": ['data1'],
                "applications": {'a1': 'file'},
                "terminals": {},
                "args": ['--extra-arg'],
                "env": {"FOO": "BAR"}
            }))

            m.assert_called_once_with('/usr/bin/FVP_Binary',
                '--parameter', 'foo=bar',
                '--data', 'data1',
                '--application', 'a1=file',
                '--extra-arg',
                stdin=unittest.mock.ANY,
                stdout=unittest.mock.ANY,
                stderr=unittest.mock.ANY,
                env={"FOO":"BAR"})
