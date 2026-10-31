import json, os, pathlib, select, subprocess, tempfile, unittest
BIN=pathlib.Path(os.environ.get('HANX_BIN','build/hanx-cli')).resolve()
class MCP(unittest.TestCase):
    def setUp(self):
        self.p=subprocess.Popen([str(BIN),'mcp'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
        self.seq=0; self.temp=tempfile.TemporaryDirectory(prefix='hanx-mcp-')
    def tearDown(self):
        if self.p.poll() is None: self.p.terminate()
        self.p.communicate(timeout=5); self.temp.cleanup()
    def send(self,value): self.p.stdin.write(json.dumps(value)+'\n'); self.p.stdin.flush()
    def receive(self):
        self.assertTrue(select.select([self.p.stdout],[],[],5)[0],'MCP response timed out')
        line=self.p.stdout.readline()
        try:return json.loads(line)
        except ValueError:self.fail('Expected a JSON-RPC message, got '+repr(line))
    def call(self,method,params=None):
        self.seq+=1; request={'jsonrpc':'2.0','id':self.seq,'method':method}
        if params is not None:request['params']=params
        self.send(request); result=self.receive(); self.assertEqual(result.get('id'),self.seq); return result
    def initialize(self):
        r=self.call('initialize',{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'test','version':'1'}})
        self.assertIn('tools',r['result']['capabilities']); self.send({'jsonrpc':'2.0','method':'notifications/initialized'})
    def test_discovery_and_real_document_edit(self):
        self.initialize(); tools=self.call('tools/list')['result']['tools']; self.assertIn('hanx_create',[t['name'] for t in tools]); self.assertIn('hanx_package_patch',[t['name'] for t in tools])
        root=pathlib.Path(self.temp.name); source=root/'source.hwp'; out=root/'edited.docx'
        r=self.call('tools/call',{'name':'hanx_create','arguments':{'output':str(source),'spec':{'kind':'document','text':'에이전트 원문'}}})['result']; self.assertFalse(r.get('isError',False)); self.assertTrue(source.exists())
        self.call('tools/call',{'name':'hanx_edit','arguments':{'input':str(source),'output':str(out),'operations':[{'op':'replace_text','find':'원문','replace':'수정'}]}})
        r=self.call('tools/call',{'name':'hanx_read','arguments':{'input':str(out)}})['result']; data=json.loads(r['content'][0]['text']); self.assertEqual(data['data']['text'],'에이전트 수정')
    def test_protocol_and_tool_errors_do_not_kill_server(self):
        self.assertIn('error',self.call('tools/list'))
        self.initialize(); self.p.stdin.write('{bad json\n'); self.p.stdin.flush(); self.assertEqual(self.receive()['error']['code'],-32700)
        self.assertEqual(self.call('not/a/method')['error']['code'],-32601)
        self.assertEqual(self.call('tools/call',{'name':'unknown','arguments':{}})['error']['code'],-32602)
        r=self.call('tools/call',{'name':'hanx_read','arguments':{'input':'/no/such/hanx-file.hwp'}}); self.assertTrue(r['result']['isError'])
        self.assertEqual(self.call('ping')['result'],{})
    def test_notification_has_no_response(self):
        self.initialize(); self.send({'jsonrpc':'2.0','method':'notifications/cancelled','params':{'requestId':77}})
        self.assertEqual(self.call('ping')['result'],{})
    def test_no_argument_tool_call_and_malformed_create_keep_connection_alive(self):
        self.initialize(); r=self.call('tools/call',{'name':'hanx_capabilities'})
        self.assertIn('result',r); self.assertFalse(r.get('result',{}).get('isError',False)); self.assertEqual(json.loads(r['result']['content'][0]['text'])['data']['version'],'2.8.0')
        r=self.call('tools/call',{'name':'hanx_create','arguments':{'output':str(pathlib.Path(self.temp.name)/'bad.hwp'),'spec':{'kind':'document','blocks':[{'text':'x','style':{'font':'a'*65536}}]}}})
        self.assertTrue(r['result']['isError']); self.assertEqual(self.call('ping')['result'],{})


    def test_spreadsheet_calculate_and_edit_through_mcp(self):
        self.initialize(); tools=self.call('tools/list')['result']['tools']; names=[t['name'] for t in tools]
        self.assertIn('hanx_sheet_read',names); self.assertIn('hanx_sheet_eval',names); self.assertIn('hanx_sheet_recalculate',names)
        p=pathlib.Path(self.temp.name)/'sheet.xlsx'; q=p.with_name('edited.xlsx')
        def tool(name,args):
            r=self.call('tools/call',{'name':'hanx_'+name,'arguments':args})['result']; self.assertFalse(r.get('isError',False),r); return json.loads(r['content'][0]['text'])['data']
        tool('create',{'output':str(p),'spec':{'kind':'spreadsheet','sheets':[{'name':'Data','rows':[[1],[2]],'cells':{'B1':'=SUM(A1:A2)'}}]}})
        self.assertEqual(tool('sheet_eval',{'input':str(p),'formula':'=SUM(Data!A1:A2)'})['value'],3)
        tool('edit',{'input':str(p),'output':str(q),'operations':[{'op':'set_cell','sheet':'Data','cell':'A2','value':9}]})
        result=tool('sheet_read',{'input':str(q),'sheet':'Data','range':'B1'}); self.assertEqual(result['cells'][0]['value'],10)

if __name__=='__main__': unittest.main()
