import json, os, pathlib, subprocess, tempfile, unittest, zipfile
import xml.etree.ElementTree as ET
BIN=pathlib.Path(os.environ.get('HANWORD_BIN','build/hanword-cli')).resolve()
NS={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
class Spreadsheets(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.root=pathlib.Path(self.tmp.name)
    def tearDown(self): self.tmp.cleanup()
    def runcli(self,*args,ok=True,stdin=None):
        p=subprocess.run([str(BIN),*map(str,args)],input=stdin,text=True,capture_output=True,timeout=25)
        self.assertEqual(p.returncode==0,ok,(p.returncode,p.stdout,p.stderr))
        d=json.loads(p.stdout); self.assertEqual(d['ok'],ok,d); return d['data'] if ok else d['error']
    def create(self,spec=None):
        p=self.root/'매출.xlsx'
        spec=spec or {'kind':'spreadsheet','sheets':[{'name':'매출','rows':[['상품','수량','단가','금액'],['사과',2,1000,'=B2*C2'],['배',3,2000,'=B3*C3']], 'cells':{'D4':{'input':'=SUM(D2:D3)','style':{'bold':True,'numberFormat':'#,##0'}}}},{'name':'요약','cells':{'A1':"='매출'!D4",'A2':'=XLOOKUP("배",매출!A2:A3,매출!D2:D3)','A3':'=SUMIFS(매출!D2:D3,매출!B2:B3,">2")','A4':'=IF(A1>5000,"달성","미달")'}}]}
        self.runcli('create','--spec','-','--output',p,stdin=json.dumps(spec)); return p
    def edit(self,p,ops,out='수정.xlsx',ok=True):
        dest=self.root/out; self.runcli('edit',p,'--ops','-','--output',dest,stdin=json.dumps(ops),ok=ok); return dest
    def cells(self,p,sheet,range):
        d=self.runcli('spreadsheet','read',p,'--sheet',sheet,'--range',range); return {c['address']:c for c in d['cells']}
    def test_create_formulas_and_real_xlsx_cached_values(self):
        p=self.create(); c=self.cells(p,'요약','A1:A4')
        self.assertEqual([c['A'+str(i)]['value'] for i in range(1,5)],[8000,6000,6000,'달성'])
        with zipfile.ZipFile(p) as z:
            root=ET.fromstring(z.read('xl/worksheets/sheet1.xml')); cell=root.find('.//s:c[@r="D4"]',NS)
            self.assertEqual(cell.find('s:f',NS).text,'SUM(D2:D3)'); self.assertEqual(float(cell.find('s:v',NS).text),8000)
        d=self.runcli('read',p); self.assertEqual(d['kind'],'spreadsheet'); self.assertEqual(d['sheets'][0]['name'],'매출')
    def test_edit_values_fill_relative_formulas_styles_and_recalculation(self):
        p=self.create(); out=self.edit(p,[{'op':'set_cell','sheet':'매출','cell':'B2','value':5},{'op':'set_range','sheet':'매출','start':'B3','values':[[4,2500]]},{'op':'fill_formula','sheet':'매출','range':'D2:D3','formula':'=B2*C2+$F$1'},{'op':'set_cell','sheet':'매출','cell':'F1','value':100},{'op':'style_range','sheet':'매출','range':'D2:D4','style':{'bold':True,'fill':'FFFF00','numberFormat':'#,##0.00'}},{'op':'set_column_width','sheet':'매출','column':'A','width':120},{'op':'freeze','sheet':'매출','rows':1,'columns':1}])
        c=self.cells(out,'매출','D2:D4'); self.assertEqual(c['D2']['value'],5100); self.assertEqual(c['D3']['input'],'=B3*C3+$F$1'); self.assertEqual(c['D3']['value'],10100); self.assertEqual(c['D4']['value'],15200)
        self.assertEqual(c['D3']['style']['fill'],'FFFF00'); self.assertEqual(self.cells(out,'요약','A1')['A1']['value'],15200)
        self.assertEqual(self.cells(p,'매출','B2')['B2']['value'],2)
        with zipfile.ZipFile(out) as z:
            x=ET.fromstring(z.read('xl/worksheets/sheet1.xml')); pane=x.find('.//s:pane',NS); self.assertEqual(pane.get('ySplit'),'1'); self.assertEqual(pane.get('xSplit'),'1')
    def test_evaluate_errors_and_dynamic_arrays_are_structured(self):
        p=self.create()
        for formula,want in [('=AVERAGE(매출!D2:D3)',4000),('=ROUND(10/3,2)',3.33),('=SUM(1,2,3)',6)]:
            self.assertAlmostEqual(self.runcli('spreadsheet','eval',p,'--sheet','요약','--formula',formula)['value'],want)
        error=self.runcli('spreadsheet','eval',p,'--formula','=1/0'); self.assertEqual(error['type'],'error'); self.assertEqual(error['value'],'#DIV/0!')
        d=self.runcli('spreadsheet','eval',p,'--formula','=SEQUENCE(2,2)'); self.assertEqual(d['value'],[[1,2],[3,4]])
        out=self.edit(p,[{'op':'set_cell','sheet':'요약','cell':'C1','input':'=SEQUENCE(2,2)'}]); c=self.cells(out,'요약','C1:D2'); self.assertEqual([c[x]['value'] for x in ['C1','D1','C2','D2']],[1,2,3,4])
    def test_csv_json_roundtrip_text_and_named_ranges(self):
        p=self.create({'kind':'spreadsheet','sheets':[{'name':'자료','rows':[['001','a,b',20000000],['=literal',True,5]],'cells':{'A2':{'value':'=literal'}}}], 'definedNames':{'TOTAL':'자료!C1+C2'}})
        self.assertEqual(self.cells(p,'자료','A1:C2')['A1']['value'],'001'); self.assertEqual(self.cells(p,'자료','A1:C2')['A2']['value'],'=literal')
        self.assertEqual(self.runcli('spreadsheet','eval',p,'--formula','=TOTAL')['value'],20000005)
        spec=self.root/'book.json'; self.runcli('convert',p,'--output',spec); q=self.root/'again.xlsx'; self.runcli('create','--spec',spec,'--output',q); self.assertEqual(self.cells(q,'자료','A1')['A1']['value'],'001')
        csv=self.root/'data.csv'; self.runcli('convert',p,'--output',csv); self.assertIn('"a,b"',csv.read_text(encoding='utf-8-sig')); self.assertEqual(self.runcli('read',csv)['kind'],'spreadsheet')
    def test_atomic_invalid_operations_bad_addresses_and_output_protection(self):
        p=self.create(); before=p.read_bytes(); out=self.edit(p,[{'op':'set_cell','cell':'A1','value':99},{'op':'set_cell','cell':'A0','value':1}],out='bad.xlsx',ok=False); self.assertFalse(out.exists()); self.assertEqual(p.read_bytes(),before)
        for addr in ['XFE1','A1048577','A' * 200+'1','A1:B2','A1junk']:
            self.edit(p,[{'op':'set_cell','cell':addr,'value':1}],out='invalid.xlsx',ok=False)
        self.edit(p,[{'op':'style_range','range':'A1:XFD1048576','style':{'bold':True}}],out='too-big.xlsx',ok=False)
        self.edit(p,[{'op':'set_cell','cell':'A1','value':99,'typo':True}],out='typo.xlsx',ok=False)
        self.runcli('spreadsheet','recalculate',p,'--output',p,ok=False); self.assertEqual(p.read_bytes(),before)
        self.runcli('spreadsheet','read',p,'--sheet','없는시트',ok=False)
    def test_sheet_management_clear_merge_and_function_discovery(self):
        p=self.create(); out=self.edit(p,[{'op':'add_sheet','name':'추가'},{'op':'set_range','sheet':'추가','start':'A1','values':[[1,2],[3,4]]},{'op':'clear_range','sheet':'추가','range':'B1:B2'},{'op':'merge','sheet':'추가','range':'A4:B4'},{'op':'set_row_height','sheet':'추가','row':0,'height':35},{'op':'define_name','name':'합계','formula':"매출!D4"}])
        c=self.cells(out,'추가','A1:B2'); self.assertEqual(c['B1']['type'],'empty'); self.assertEqual(c['A2']['value'],3)
        cap=self.runcli('capabilities'); self.assertIn('xlsx',cap['formats']['spreadsheet']); self.assertIn('XLOOKUP',cap['spreadsheetFunctions']); self.assertIn('fill_formula',cap['operations']['spreadsheet'])
        funcs=self.runcli('spreadsheet','functions'); self.assertIn('SUMIFS',funcs['functions'])
        q=self.root/'recalc.xlsx'; d=self.runcli('spreadsheet','recalculate',out,'--output',q); self.assertEqual(d['kind'],'spreadsheet'); self.assertTrue(q.exists())
    def test_external_formula_io_is_blocked_in_evaluation_and_writer(self):
        secret=self.root/'secret.csv'; secret.write_text('PRIVATE,123')
        p=self.create(); formula='=IMPORTCSV('+json.dumps(str(secret))+')'
        self.assertEqual(self.runcli('spreadsheet','eval',p,'--formula',formula)['value'],'#BLOCKED!')
        out=self.edit(p,[{'op':'set_cell','cell':'H1','input':formula},{'op':'set_cell','cell':'H2','input':'=WEBSERVICE("https://example.com/")'}]); c=self.cells(out,'매출','H1:H2'); self.assertEqual(c['H1']['value'],'#BLOCKED!'); self.assertEqual(c['H2']['value'],'#BLOCKED!'); self.assertNotIn(b'PRIVATE',out.read_bytes())
    def test_flat_opc_xlsx_roundtrip_and_invalid_formula_names(self):
        p=self.create(); flat=self.root/'book.xml'; out=self.root/'flat.xlsx'
        self.runcli('convert',p,'--output',flat); self.runcli('convert',flat,'--output',out)
        self.assertEqual(self.cells(out,'요약','A1')['A1']['value'],8000)
        result=self.runcli('spreadsheet','eval',p,'--formula','='+'Z'*200+'1')
        self.assertEqual(result['type'],'error')
        q=self.edit(p,[{'op':'define_name','name':'a'*200,'formula':'1'}],out='long-name.xlsx'); self.assertTrue(q.exists())

    def test_fill_keeps_sheet_names_strings_and_shifts_whole_row_column_references(self):
        p=self.create({'kind':'spreadsheet','sheets':[{'name':'Data1','rows':[[10],[20]]},{'name':'Data2','rows':[[100],[200]]},{'name':'Calc'}]})
        q=self.edit(p,[{'op':'fill_formula','sheet':'Calc','range':'A1:A2','formula':"='Data1'!A1"},{'op':'fill_formula','sheet':'Calc','range':'B1:B2','formula':'=Data1!A1'},{'op':'fill_formula','sheet':'Calc','range':'C1:C2','formula':'=SUM(Data1!1:1)'},{'op':'fill_formula','sheet':'Calc','range':'D1:E1','formula':'=SUM(Data1!A:A)'},{'op':'fill_formula','sheet':'Calc','range':'F1:F2','formula':'="A1"&Data1!A1'},{'op':'fill_formula','sheet':'Calc','range':'G1:H1','formula':'=XFD1'}])
        c=self.cells(q,'Calc','A1:H2'); self.assertEqual(c['A2']['value'],20); self.assertEqual(c['B2']['value'],20); self.assertEqual(c['C2']['value'],20); self.assertEqual(c['E1']['input'],'=SUM(Data1!B:B)'); self.assertEqual(c['F2']['value'],'A120'); self.assertEqual(c['H1']['value'],'#REF!')
    def test_style_only_keeps_legacy_formula_implicit_intersection(self):
        p=self.create({'kind':'spreadsheet','sheets':[{'name':'Data','rows':[[1],[2]],'cells':{'B1':'=A1:A2'},'legacyFormulas':['B1']}]})
        for operation in [{'op':'set_cell','cell':'B1','style':{'bold':True}},{'op':'set_range','start':'B1','values':[[{'style':{'bold':True}}]]}]:
            q=self.edit(p,[operation],out='legacy'+operation['op']+'.xlsx'); c=self.cells(q,'Data','B1:B2'); self.assertEqual(c['B1']['value'],1); self.assertEqual(c['B2']['type'],'empty')

    def test_default_read_and_dense_export_include_spilled_results(self):
        p=self.create({'kind':'spreadsheet','sheets':[{'name':'Array','cells':{'A1':'=SEQUENCE(2,2)'}}]})
        d=self.runcli('spreadsheet','read',p); self.assertEqual(d['range'],'A1:B2'); self.assertEqual([c['value'] for c in d['cells']],[1,2,3,4])
        out=self.root/'array.csv'; self.runcli('convert',p,'--output',out); self.assertEqual(out.read_text(encoding='utf-8-sig'),'1,2\n3,4\n')
        html=self.root/'array.html'; self.runcli('convert',p,'--output',html); self.assertIn('>4</td>',html.read_text())

    def test_plain_text_input_stays_plain_and_text_that_looks_typed_stays_text(self):
        p=self.create({'kind':'spreadsheet','sheets':[{'name':'Text','rows':[['저장 중인 셀',{'value':'TRUE'},{'value':'#DIV/0!'},{'value':"'quoted"},{'value':'=literal'}]]}]})
        c=self.cells(p,'Text','A1:E1'); self.assertEqual(c['A1']['input'],'저장 중인 셀')
        self.assertEqual([c[a]['value'] for a in ['A1','B1','C1','D1','E1']],['저장 중인 셀','TRUE','#DIV/0!',"'quoted",'=literal'])
        self.assertTrue(all(c[a]['type']=='string' for a in ['A1','B1','C1','D1','E1']))

    def test_invalid_names_and_oversized_ranges_fail_without_output(self):
        for name in ['bad/name','a'*32,'']:
            dest=self.root/'bad.xlsx'; self.runcli('create','--spec','-','--output',dest,stdin=json.dumps({'kind':'spreadsheet','sheets':[{'name':name}]}),ok=False); self.assertFalse(dest.exists())
        p=self.create(); self.edit(p,[{'op':'set_range','start':'XFD1','values':[[1,2]]}],ok=False)
if __name__=='__main__':unittest.main()
