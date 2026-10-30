import os,pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class PKGCommands(unittest.TestCase):
    def test_postinstall_links_owned_command_but_preserves_other_installations(self):
        script=ROOT/'packaging/pkg/postinstall'
        with tempfile.TemporaryDirectory(prefix='hanx-target ') as d:
            target=pathlib.Path(d); cli=target/'Applications/HanX.app/Contents/Resources/CLI/hanx';cli.parent.mkdir(parents=True);cli.write_text('CLI')
            p=subprocess.run(['/bin/sh',str(script),'pkg','/',str(target)],capture_output=True,text=True);self.assertEqual(p.returncode,0,p.stderr)
            link=target/'usr/local/bin/hanx';self.assertTrue(link.is_symlink());self.assertEqual(os.readlink(link),'/Applications/HanX.app/Contents/Resources/CLI/hanx')
            p=subprocess.run(['/bin/sh',str(script),'pkg','/',str(target)],capture_output=True,text=True);self.assertEqual(p.returncode,0,p.stderr)
            link.unlink();link.write_text('another installation')
            p=subprocess.run(['/bin/sh',str(script),'pkg','/',str(target)],capture_output=True,text=True);self.assertEqual(p.returncode,0,p.stderr);self.assertEqual(link.read_text(),'another installation')
    def test_postinstall_requires_embedded_cli_and_does_not_create_dangling_command(self):
        script=ROOT/'packaging/pkg/postinstall'
        with tempfile.TemporaryDirectory() as d:
            p=subprocess.run(['/bin/sh',str(script),'pkg','/',d],capture_output=True,text=True);self.assertNotEqual(p.returncode,0);self.assertFalse((pathlib.Path(d)/'usr/local/bin/hanx').exists())
    def test_legacy_owned_command_is_retired_without_touching_foreign_commands(self):
        with tempfile.TemporaryDirectory(prefix='hanx-migration-') as d:
            target=pathlib.Path(d);cli=target/'Applications/HanX.app/Contents/Resources/CLI/hanx';cli.parent.mkdir(parents=True);cli.write_text('CLI')
            commands=target/'usr/local/bin';commands.mkdir(parents=True)
            legacy=commands/'hanword';legacy.symlink_to('/Applications/HanWord.app/Contents/Resources/CLI/hanword')
            foreign=commands/'hanword-cli';foreign.write_text('foreign command')
            p=subprocess.run(['/bin/sh',str(ROOT/'packaging/pkg/postinstall'),'pkg','/',str(target)],capture_output=True,text=True)
            self.assertEqual(p.returncode,0,p.stderr);self.assertFalse(legacy.is_symlink());self.assertEqual(foreign.read_text(),'foreign command');self.assertTrue((commands/'hanx').is_symlink())
if __name__=='__main__':unittest.main()
