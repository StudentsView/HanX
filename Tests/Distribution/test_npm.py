import json, pathlib, select, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class NPMPackage(unittest.TestCase):
    def test_packed_install_handles_spaces_json_errors_and_mcp(self):
        with tempfile.TemporaryDirectory(prefix='HanWord npm package ') as d:
            folder=pathlib.Path(d)
            p=subprocess.run(['npm','pack',str(ROOT/'packaging/npm'),'--ignore-scripts','--pack-destination',str(folder),'--json'],cwd=ROOT,capture_output=True,text=True)
            self.assertEqual(p.returncode,0,p.stderr)
            package=folder/json.loads(p.stdout)[0]['filename']; prefix=folder/'user commands'
            p=subprocess.run(['npm','install','--global','--ignore-scripts','--prefix',str(prefix),str(package)],capture_output=True,text=True)
            self.assertEqual(p.returncode,0,p.stderr)
            exe=prefix/'bin/hanword'
            p=subprocess.run([str(exe),'--version'],capture_output=True,text=True); self.assertEqual(p.returncode,0,p.stderr); self.assertTrue(json.loads(p.stdout)['ok'])
            p=subprocess.run([str(exe),'read',str(folder/'absent.xlsx')],capture_output=True,text=True); self.assertNotEqual(p.returncode,0); self.assertFalse(json.loads(p.stdout)['ok'])
            server=subprocess.Popen([str(exe),'mcp'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
            try:
                def call(obj):
                    server.stdin.write(json.dumps(obj)+'\n');server.stdin.flush();self.assertTrue(select.select([server.stdout],[],[],5)[0]);return json.loads(server.stdout.readline())
                r=call({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'npm-test','version':'1'}}}); self.assertIn('result',r)
                server.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n');server.stdin.flush()
                r=call({'jsonrpc':'2.0','id':2,'method':'tools/list'}); self.assertIn('hanword_sheet_eval',[t['name'] for t in r['result']['tools']])
                server.terminate(); server.wait(timeout=5)
            finally:
                if server.poll() is None:server.kill()
                server.communicate(timeout=5)
    def test_launcher_reports_missing_binary_without_launching_shell(self):
        launcher=ROOT/'packaging/npm/bin/hanword.js'
        with tempfile.TemporaryDirectory(prefix='HanWord launch ') as d:
            target=pathlib.Path(d)/'hanword.js'
            if launcher.exists():target.write_bytes(launcher.read_bytes())
            p=subprocess.run(['node',str(target),'--version'],capture_output=True,text=True)
            self.assertEqual(p.returncode,1)
            self.assertIn('native_binary_missing',p.stderr)
if __name__=='__main__':unittest.main()
