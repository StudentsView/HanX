import os,pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class PKGCommands(unittest.TestCase):
    def test_postinstall_links_owned_command_but_preserves_other_installations(self):
        script=ROOT/'packaging/pkg/postinstall'
        with tempfile.TemporaryDirectory(prefix='hanword-target ') as d:
            target=pathlib.Path(d); cli=target/'Applications/HanWord.app/Contents/Resources/CLI/hanword';cli.parent.mkdir(parents=True);cli.write_text('CLI')
            p=subprocess.run(['/bin/sh',str(script),'pkg','/',str(target)],capture_output=True,text=True);self.assertEqual(p.returncode,0,p.stderr)
            link=target/'usr/local/bin/hanword';self.assertTrue(link.is_symlink());self.assertEqual(os.readlink(link),'/Applications/HanWord.app/Contents/Resources/CLI/hanword')
            p=subprocess.run(['/bin/sh',str(script),'pkg','/',str(target)],capture_output=True,text=True);self.assertEqual(p.returncode,0,p.stderr)
            link.unlink();link.write_text('another installation')
            p=subprocess.run(['/bin/sh',str(script),'pkg','/',str(target)],capture_output=True,text=True);self.assertEqual(p.returncode,0,p.stderr);self.assertEqual(link.read_text(),'another installation')
    def test_postinstall_requires_embedded_cli_and_does_not_create_dangling_command(self):
        script=ROOT/'packaging/pkg/postinstall'
        with tempfile.TemporaryDirectory() as d:
            p=subprocess.run(['/bin/sh',str(script),'pkg','/',d],capture_output=True,text=True);self.assertNotEqual(p.returncode,0);self.assertFalse((pathlib.Path(d)/'usr/local/bin/hanword').exists())
if __name__=='__main__':unittest.main()
