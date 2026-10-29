import json, pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class Install(unittest.TestCase):
    def test_user_prefix_install_and_existing_command_preserved(self):
        with tempfile.TemporaryDirectory(prefix='hanword-install-') as d:
            root=pathlib.Path(d); prefix=root/'Application Support'/'HanWord'; commands=root/'bin'
            p=subprocess.run(['/bin/sh',str(ROOT/'install-cli.sh'),'--prefix',str(prefix),'--bin-dir',str(commands)],capture_output=True,text=True)
            self.assertEqual(p.returncode,0,(p.stdout,p.stderr))
            result=subprocess.check_output([str(commands/'hanword'),'--version'],text=True); self.assertEqual(json.loads(result)['data']['version'],'2.6.0')
            cap=json.loads(subprocess.check_output([str(commands/'hanword'),'capabilities'],text=True))['data']; self.assertIn('guidePath',cap); self.assertTrue(pathlib.Path(cap['guidePath']).is_file()); self.assertTrue((prefix/'README.md').exists()); self.assertTrue((prefix/'examples'/'document.json').exists())
            commands.joinpath('hanword').unlink(); commands.joinpath('hanword').write_text('user command')
            p=subprocess.run(['/bin/sh',str(ROOT/'install-cli.sh'),'--prefix',str(root/'other'),'--bin-dir',str(commands)],capture_output=True,text=True)
            self.assertNotEqual(p.returncode,0); self.assertEqual(commands.joinpath('hanword').read_text(),'user command'); self.assertFalse((root/'other').exists())
    def test_foreign_symlink_is_not_treated_as_an_owned_cli_installation(self):
        with tempfile.TemporaryDirectory(prefix='hanword-foreign-command-') as d:
            root=pathlib.Path(d); foreign=root/'homebrew/Cellar/tool/1/bin/hanword';foreign.parent.mkdir(parents=True);foreign.write_text('foreign command')
            commands=root/'bin';commands.mkdir();command=commands/'hanword';command.symlink_to(foreign)
            prefix=root/'new-install'
            p=subprocess.run(['/bin/sh',str(ROOT/'install-cli.sh'),'--prefix',str(prefix),'--bin-dir',str(commands)],capture_output=True,text=True)
            self.assertNotEqual(p.returncode,0);self.assertEqual(command.readlink(),foreign);self.assertFalse(prefix.exists())
if __name__=='__main__':unittest.main()
