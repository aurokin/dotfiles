"""Platform selection and listener-evidence contracts, without live commands."""
import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / 'dot_scripts/compat-portless-isolated.py'


def load(system='Darwin'):
    spec = importlib.util.spec_from_file_location('compat_fixture', SOURCE)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    with patch('platform.system', return_value=system), patch('shutil.which', return_value='/test/lsof'):
        spec.loader.exec_module(module)
    return module


class Portability(unittest.TestCase):
    def test_stable_platform_paths(self):
        self.assertEqual(load('Darwin').NODE, '/opt/homebrew/opt/node@24/bin/node')
        self.assertEqual(load('Linux').NODE, '/home/linuxbrew/.linuxbrew/opt/node@24/bin/node')
        self.assertIsNone(load('Windows').NODE)
        self.assertEqual(load().LSOF, '/test/lsof')

    def test_lsof_observed_and_empty(self):
        m = load()
        for rc, out, err, expected in [(0, 'listener\n', '', 'listener'), (0, 'listener\n', 'mount warning', 'listener'), (1, '', '', '')]:
            with self.subTest(rc=rc, stderr=err), patch.object(m.subprocess, 'run', return_value=subprocess.CompletedProcess([], rc, out, err)):
                self.assertEqual(m.lsof_output(['-nP']), expected)
        self.assertEqual(len(m.LSOF_WARNINGS), 1)

    def test_lsof_uncertain_never_empty(self):
        m = load()
        for rc, out, err in [(2, '', 'failure'), (1, '', 'warning'), (0, '', ''), (1, 'unexpected', '')]:
            with self.subTest(rc=rc, stderr=err), patch.object(m.subprocess, 'run', return_value=subprocess.CompletedProcess([], rc, out, err)):
                with self.assertRaises(RuntimeError):
                    m.lsof_output(['-nP'])
        with patch.object(m.subprocess, 'run', side_effect=subprocess.TimeoutExpired('lsof', 10)):
            with self.assertRaises(subprocess.TimeoutExpired):
                m.lsof_output(['-nP'])


if __name__ == '__main__':
    unittest.main()
