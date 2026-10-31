#!/usr/bin/env python3
"""Exercise the actual staged shell wrapper through installed PATH entry points."""
import ast
import pathlib
import shutil
import subprocess
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent


def staged_wrapper():
    # Extract the literal wrapper from the real staging source without executing
    # its native build/library scan. This regression changes when that wrapper does.
    tree = ast.parse((HERE / 'stage-cli.py').read_text())
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == 'write_text':
            if node.args and isinstance(node.args[0], ast.Constant) and str(node.args[0].value).startswith('#!/bin/sh'):
                return node.args[0].value
    raise AssertionError('Native staging script has no shell launcher fixture')


class InstallerTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='HanX installer paths ')
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.source = self.root / 'CLI archive'
        self.source.mkdir()
        self.prefix = self.root / 'User prefix'
        shutil.copy2(HERE / 'install-cli.sh', self.source / 'install-cli.sh')
        (self.source / 'hanx').write_text(staged_wrapper())
        (self.source / 'hanx').chmod(0o755)
        # Stand in only for the native engine. The launcher itself is extracted
        # unchanged from stage-cli.py, so an invalid dirname($0) breaks this test.
        (self.source / 'hanx-engine').write_text('#!/bin/sh\nprintf "%s\\n" "engine reached" "$@"\n')
        (self.source / 'hanx-engine').chmod(0o755)
        (self.source / 'lib').mkdir()

    def install(self):
        return subprocess.run(['sh', str(self.source / 'install-cli.sh'), '--prefix', str(self.prefix)],
                              input='', capture_output=True, text=True, timeout=10)

    def test_noninteractive_install_exposes_working_wrapper_and_alias(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        for command in ('hanx', 'hanx-cli'):
            result = subprocess.run([str(self.prefix / 'bin' / command), '--version', 'value with spaces'],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), ['engine reached', '--version', 'value with spaces'])
        self.assertFalse((self.prefix / 'lib' / 'hanx-gui').exists())

    def test_install_refuses_to_replace_existing_command(self):
        (self.prefix / 'bin').mkdir(parents=True)
        command = self.prefix / 'bin' / 'hanx-cli'
        command.write_text('belongs to someone else')
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Refusing to overwrite', result.stderr)
        self.assertEqual(command.read_text(), 'belongs to someone else')
        self.assertFalse((self.prefix / 'lib' / 'hanx').exists())


if __name__ == '__main__':
    unittest.main()
