import hashlib, json, os, pathlib, subprocess, tempfile, unittest, zipfile
import xml.etree.ElementTree as ET

BIN = pathlib.Path(os.environ.get('HANX_BIN', 'build/hanx-cli')).resolve()
class CLI(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='HanX CLI '); self.root=pathlib.Path(self.temp.name)
    def tearDown(self): self.temp.cleanup()
    def spec(self,name,value):
        p=self.root/name; p.write_text(json.dumps(value,ensure_ascii=False)); return p
    def runcli(self,*args,ok=True,stdin=None):
        p=subprocess.run([str(BIN),*map(str,args)],input=stdin,text=True,capture_output=True)
        self.assertEqual(p.returncode == 0,ok,(p.returncode,p.stdout,p.stderr))
        try: value=json.loads(p.stdout)
        except ValueError: self.fail('CLI must emit JSON: '+p.stdout[:300])
        self.assertEqual(value['ok'],ok,value); return value.get('data') if ok else value['error']
    def make_doc(self,ext='docx'):
        spec=self.spec('doc.json',{'kind':'document','title':'보고서','blocks':[
            {'type':'paragraph','text':'안녕하세요 HanX','style':{'bold':True,'size':18}},
            {'type':'paragraph','runs':[{'text':'빨강','color':'FF0000'},{'text':' 파랑','color':'0000FF'}]},
            {'type':'table','rows':[['이름','값'],['합계','10']]}]})
        out=self.root/('문서.'+ext); self.runcli('create','--spec',spec,'--output',out); return out
    def test_whitespace_only_runs_between_korean_words_survive_docx(self):
        spec=self.spec('spaces.json',{'kind':'document','blocks':[{'type':'paragraph','runs':[{'text':'한글','font':'Apple SD Gothic Neo'},{'text':' ','font':'Arial'},{'text':'사이','font':'Apple SD Gothic Neo'},{'text':'  ','font':'Arial'},{'text':'공백','font':'Apple SD Gothic Neo'}]}]})
        out=self.root/'공백.docx';self.runcli('create','--spec',spec,'--output',out)
        self.assertIn('한글 사이  공백',self.runcli('read',out)['text'])
    def test_docx_literal_xml_inside_cdata_stays_literal(self):
        source=self.make_doc();parts={name:zipfile.ZipFile(source).read(name) for name in zipfile.ZipFile(source).namelist()}
        text=parts['word/document.xml'].decode();start=text.index('<w:body>')+len('<w:body>');text=text[:start]+'<w:p><w:r><w:t><![CDATA[<w:t> </w:t>]]></w:t></w:r></w:p>'+text[start:];parts['word/document.xml']=text.encode()
        out=self.root/'cdata.docx'
        with zipfile.ZipFile(out,'w') as archive:
            for name,data in parts.items():archive.writestr(name,data)
        self.assertIn('<w:t> </w:t>',self.runcli('read',out)['text'])
    def test_capabilities_discover_operations(self):
        d=self.runcli('capabilities'); self.assertIn('hwp',d['formats']['document']); self.assertIn('pptx',d['formats']['presentation']); self.assertIn('replace_text',d['operations']['document'])
    def test_hwp_docx_hwpx_create_read_convert(self):
        for ext in ['hwp','docx','hwpx','hml']:
            with self.subTest(ext=ext):
                p=self.make_doc(ext); d=self.runcli('read',p); self.assertIn('안녕하세요 HanX',d['text']); self.assertIn('합계\t10',d['text'])
                out=self.root/(ext+'-converted.docx'); self.runcli('convert',p,'--output',out); self.assertIn('합계\t10',self.runcli('read',out)['text'])
    def test_document_edits_preserve_other_run_formatting(self):
        p=self.make_doc(); ops=self.spec('ops.json',[{'op':'replace_text','find':'안녕하세요','replace':'반갑습니다'},{'op':'set_cell','section':0,'block':2,'row':1,'column':1,'text':'20'},{'op':'append_paragraph','text':'추가 문단'}]); out=self.root/'수정.docx'
        self.runcli('edit',p,'--ops',ops,'--output',out); text=self.runcli('read',out)['text']; self.assertIn('반갑습니다 HanX',text); self.assertIn('합계\t20',text); self.assertIn('추가 문단',text)
        root=ET.fromstring(zipfile.ZipFile(out).read('word/document.xml')); ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
        colors=[x.get('{'+ns['w']+'}val') for x in root.findall('.//w:color',ns)]; self.assertIn('FF0000',colors); self.assertIn('0000FF',colors)
    def test_refuses_overwrite_and_invalid_batch_preserves_files(self):
        p=self.make_doc(); original=p.read_bytes(); err=self.runcli('create','--spec',self.root/'doc.json','--output',p,ok=False); self.assertEqual(err['code'],'output_exists'); self.assertEqual(original,p.read_bytes())
        ops=self.spec('bad.json',[{'op':'append_paragraph','text':'should not commit'},{'op':'set_cell','block':999,'row':0,'column':0,'text':'bad'}]); out=self.root/'bad.docx'
        self.runcli('edit',p,'--ops',ops,'--output',out,ok=False); self.assertFalse(out.exists()); self.assertEqual(original,p.read_bytes())
    def test_presentation_objects_notes_transitions_edit(self):
        spec=self.spec('slides.json',{'kind':'presentation','slides':[{'title':'첫 장','body':['본문'],'notes':'발표 노트','transition':{'kind':'cut'},'shapes':[{'kind':'rect','x':50,'y':200,'width':100,'height':80,'text':'상자','fill':'336699'}]}]}); p=self.root/'발표.pptx'
        self.runcli('create','--spec',spec,'--output',p); d=self.runcli('read',p); self.assertIn('첫 장',d['text']); self.assertEqual(d['model']['slides'][0]['notes'],'발표 노트')
        ops=self.spec('slide-ops.json',[{'op':'duplicate_slide','slide':0},{'op':'set_transition','slide':1,'kind':'push','direction':'left','duration':1.3},{'op':'set_notes','slide':1,'text':'수정 노트'},{'op':'update_shape','slide':1,'shapeId':4,'rotation':45}]); out=self.root/'수정.pptx'
        self.runcli('edit',p,'--ops',ops,'--output',out); slides=self.runcli('read',out)['model']['slides']; self.assertEqual(len(slides),2); self.assertEqual(slides[1]['transition']['kind'],'push'); self.assertEqual(slides[1]['notes'],'수정 노트'); self.assertEqual(next(x for x in slides[1]['shapes'] if x['id']==4)['rotation'],45)
    def test_json_model_can_be_exported_and_reimported(self):
        p=self.make_doc('hwp'); doc=self.runcli('read',p); spec=self.spec('model.json',{'kind':doc['kind'],'model':doc['model']}); out=self.root/'model.docx'; self.runcli('create','--spec',spec,'--output',out); self.assertEqual(self.runcli('read',out)['text'],doc['text']+'\n')
    def test_stdin_spec_and_missing_argument_errors(self):
        out=self.root/'stdin.docx'; self.runcli('create','--spec','-','--output',out,stdin=json.dumps({'kind':'document','text':'표준 입력'})); self.assertEqual(self.runcli('read',out)['text'],'표준 입력'); self.runcli('read',ok=False); self.runcli('not-a-command',ok=False)
    def test_generic_xml_xpath_patch_preserves_comment_and_namespace(self):
        p=self.root/'자료.xml'; p.write_text('<r xmlns:x="urn:test"><!--keep--><x:item id="1">old</x:item><x:item id="2"><![CDATA[keep & raw]]></x:item></r>')
        d=self.runcli('xml','read',p,'--xpath',"//*[local-name()='item']"); self.assertEqual(len(d['nodes']),2)
        ops=self.spec('xml-ops.json',[{'op':'set_text','xpath':"//*[@id='1']",'text':'새 값 & <문자>'},{'op':'set_attribute','xpath':"//*[@id='2']",'name':'status','value':'ok'},{'op':'append_xml','xpath':'/r','xml':'<extra>추가</extra>'}]); out=self.root/'patched.xml'
        self.runcli('xml','edit',p,'--ops',ops,'--output',out); root=ET.parse(out).getroot(); self.assertEqual(root[0].text,'새 값 & <문자>'); self.assertEqual(root[1].get('status'),'ok'); self.assertIn('<!--keep-->',out.read_text()); self.assertIn('<![CDATA[keep & raw]]>',out.read_text())
    def test_xml_entity_and_empty_xpath_are_rejected(self):
        secret=self.root/'secret'; secret.write_text('DO NOT READ')
        p=self.root/'entity.xml'; p.write_text(f'<!DOCTYPE r [<!ENTITY x SYSTEM "{secret.as_uri()}">]><r>&x;</r>'); self.runcli('xml','read',p,ok=False)
        p.write_text('<r/>'); ops=self.spec('absent.json',[{'op':'set_text','xpath':'/r/missing','text':'x'}]); out=self.root/'no.xml'; self.runcli('xml','edit',p,'--ops',ops,'--output',out,ok=False); self.assertFalse(out.exists())
    def test_package_patch_preserves_unrelated_entries_and_flat_xml_roundtrip(self):
        p=self.make_doc(); listing=self.runcli('package','list',p); self.assertIn('word/document.xml',[x['name'] for x in listing['parts']])
        ops=self.spec('part-ops.json',[{'op':'set_text','xpath':"//*[local-name()='t'][1]",'text':'바꾼 제목'}]); out=self.root/'package.docx'
        self.runcli('package','patch',p,'--part','word/document.xml','--ops',ops,'--output',out)
        with zipfile.ZipFile(p) as a,zipfile.ZipFile(out) as b:
            self.assertEqual(a.namelist(),b.namelist())
            for name in a.namelist():
                if name != 'word/document.xml': self.assertEqual(a.read(name),b.read(name),name)
        flat=self.root/'package.xml'; rebuilt=self.root/'rebuilt.docx'; self.runcli('convert',out,'--output',flat); self.assertEqual(ET.parse(flat).getroot().tag,'{http://schemas.microsoft.com/office/2006/xmlPackage}package'); self.runcli('convert',flat,'--output',rebuilt)
        self.assertIn('바꾼 제목',self.runcli('read',rebuilt)['text'])
    def test_hwpml_fixture_reads_styles_and_table_without_double_counting(self):
        p=self.root/'fixture.hml'; p.write_text('<HWPML Version="2.8"><HEAD><MAPPINGTABLE><CHARSHAPELIST Count="1"><CHARSHAPE Id="0" Height="1400" TextColor="255"><BOLD/></CHARSHAPE></CHARSHAPELIST></MAPPINGTABLE></HEAD><BODY><SECTION Id="0"><P><TEXT CharShape="0"><CHAR>한글 XML</CHAR></TEXT></P><P><TEXT><TABLE RowCount="1" ColCount="1"><ROW><CELL ColAddr="0" RowAddr="0" ColSpan="1" RowSpan="1" Width="10000"><PARALIST><P><TEXT><CHAR>셀 내용</CHAR></TEXT></P></PARALIST></CELL></ROW></TABLE></TEXT></P></SECTION></BODY></HWPML>')
        d=self.runcli('read',p); self.assertEqual(d['text'].count('셀 내용'),1); out=self.root/'from-hml.hwp'; self.runcli('convert',p,'--output',out); self.assertIn('한글 XML',self.runcli('read',out)['text'])

    def test_document_image_creation_and_hwpml_roundtrip(self):
        import base64
        image=self.root/'tiny.png'; image.write_bytes(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX24AAAAASUVORK5CYII='))
        spec=self.spec('image.json',{'kind':'document','blocks':[{'type':'paragraph','text':'이미지'},{'type':'image','path':'tiny.png','width':60,'height':40}]})
        hml=self.root/'image.hml'; self.runcli('create','--spec',spec,'--output',hml)
        doc=self.runcli('read',hml); self.assertEqual(len(doc['model']['images']),1); self.assertFalse(doc['text'].startswith('\n'))
        out=self.root/'image.docx'; self.runcli('convert',hml,'--output',out)
        with zipfile.ZipFile(out) as z:self.assertTrue(any(n.startswith('word/media/') for n in z.namelist()))
    def test_native_model_bad_dimensions_returns_json_error_without_crashing(self):
        p=self.make_doc(); model=self.runcli('read',p)['model']; model['sections'][0]['page']['width']=1e300
        spec=self.spec('huge.json',{'kind':'document','model':model}); out=self.root/'huge.hwp'
        self.runcli('create','--spec',spec,'--output',out,ok=False); self.assertFalse(out.exists())
    def test_replace_across_runs_and_repeated_matches_retains_untouched_styles(self):
        spec=self.spec('runs.json',{'kind':'document','blocks':[{'type':'paragraph','runs':[{'text':'ab','color':'FF0000'},{'text':'cd ef abcd','color':'0000FF'}]}]})
        p=self.root/'runs.docx'; out=self.root/'replaced.docx'; self.runcli('create','--spec',spec,'--output',p)
        ops=self.spec('replace.json',[{'op':'replace_text','find':'abcd','replace':'X'}]); self.runcli('edit',p,'--ops',ops,'--output',out)
        d=self.runcli('read',out); self.assertEqual(d['text'],'X ef X')
        root=ET.fromstring(zipfile.ZipFile(out).read('word/document.xml')); ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
        values=[(r.find('w:t',ns).text,r.find('w:rPr/w:color',ns).get('{'+ns['w']+'}val')) for r in root.findall('.//w:r',ns) if r.find('w:t',ns) is not None]
        self.assertIn((' ef ','0000FF'),values)
    def test_flat_pptx_and_hwpx_binary_parts_survive(self):
        for ext in ['pptx','hwpx']:
            if ext == 'pptx':
                p=self.root/'deck.pptx'; self.runcli('create','--spec','-','--output',p,stdin=json.dumps({'kind':'presentation','slides':[{'title':'슬라이드','notes':'노트'}]}))
            else:p=self.make_doc('hwpx')
            flat=self.root/(ext+'.xml'); out=self.root/('back.'+ext); self.runcli('convert',p,'--output',flat); self.runcli('convert',flat,'--output',out)
            self.assertIn('슬라이드' if ext == 'pptx' else '안녕하세요',self.runcli('read',out)['text'])
            with zipfile.ZipFile(p) as a,zipfile.ZipFile(out) as b:
                for name in a.namelist():
                    if not name.endswith(('.xml','.rels','.hpf')) and name != '[Content_Types].xml':self.assertEqual(a.read(name),b.read(name))
                if ext == 'hwpx':self.assertEqual(b.infolist()[0].filename,'mimetype'); self.assertEqual(b.infolist()[0].compress_type,0)
    def test_rejects_unknown_operation_properties_instead_of_silent_success(self):
        p=self.make_doc(); ops=self.spec('typo.json',[{'op':'append_paragraph','text':'x','boldness':True}]); out=self.root/'typo.docx'; self.runcli('edit',p,'--ops',ops,'--output',out,ok=False); self.assertFalse(out.exists())

    def test_invalid_native_geometry_and_long_font_never_trap(self):
        p=self.make_doc(); model=self.runcli('read',p)['model']; model['sections'][0]['page']['width']=-1
        spec=self.spec('negative.json',{'kind':'document','model':model}); self.runcli('create','--spec',spec,'--output',self.root/'negative.hwp',ok=False)
        spec=self.spec('font.json',{'kind':'document','blocks':[{'text':'x','style':{'font':'a'*65536}}]}); self.runcli('create','--spec',spec,'--output',self.root/'font.hwp',ok=False)
    def test_hwpml_rejects_overflow_spans_before_allocation(self):
        p=self.root/'span.hml'; p.write_text('<HWPML><BODY><SECTION><P><TEXT><TABLE><ROW><CELL ColAddr="1" ColSpan="9223372036854775807"><PARALIST/></CELL></ROW></TABLE></TEXT></P></SECTION></BODY></HWPML>'); self.runcli('read',p,ok=False)
    def test_flat_opc_rejects_part_names_exceeding_zip_limit(self):
        p=self.root/'long.xml'; p.write_text('<pkg:package xmlns:pkg="http://schemas.microsoft.com/office/2006/xmlPackage"><pkg:part pkg:name="/word/document.xml" pkg:contentType="application/xml"><pkg:xmlData><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body/></w:document></pkg:xmlData></pkg:part><pkg:part pkg:name="/'+('a'*65536)+'"><pkg:binaryData>eA==</pkg:binaryData></pkg:part></pkg:package>'); self.runcli('convert',p,'--output',self.root/'long.docx',ok=False)
    def test_hwpml_uses_official_color_and_margin_spacing(self):
        p=self.root/'style.hml'; p.write_text('<HWPML><HEAD><MAPPINGTABLE><CHARSHAPELIST><CHARSHAPE Id="0" Height="1400" TextColor="255"/></CHARSHAPELIST><PARASHAPELIST><PARASHAPE Id="0"><PARAMARGIN LineSpacingType="Fixed" LineSpacing="1800"/></PARASHAPE></PARASHAPELIST></MAPPINGTABLE></HEAD><BODY><SECTION><P ParaShape="0"><TEXT CharShape="0"><CHAR>빨강</CHAR></TEXT></P></SECTION></BODY></HWPML>')
        model=self.runcli('read',p)['model']; para=model['sections'][0]['blocks'][0]['paragraph']['_0']; self.assertEqual(para['markProps']['color'],{'r':255,'g':0,'b':0}); self.assertEqual(para['props']['lineSpacing'],{'exact':{'_0':18}})
        out=self.root/'styled.hml'; spec=self.spec('styled.json',{'kind':'document','blocks':[{'text':'red','style':{'color':'FF0000'}}]}); self.runcli('create','--spec',spec,'--output',out)
        root=ET.parse(out).getroot(); self.assertEqual(root.get('Style2'),'embed'); self.assertEqual(root.find('.//CHARSHAPE[@TextColor="255"]').get('Height'),'1000'); self.assertIsNotNone(root.find('.//PARAMARGIN[@LineSpacingType]'))

    def test_hwp_rejects_run_and_padding_values_exceeding_binary_fields(self):
        spec=self.spec('runs-limit.json',{'kind':'document','blocks':[{'runs':[{'text':'x','bold':bool(i%2)} for i in range(65536)]}]}); self.runcli('create','--spec',spec,'--output',self.root/'runs-limit.hwp',ok=False)
        p=self.make_doc(); model=self.runcli('read',p)['model']; model['sections'][0]['blocks'][2]['table']['_0']['rows'][0][0]['padding']={'left':1000,'right':0,'top':0,'bottom':0}
        spec=self.spec('padding.json',{'kind':'document','model':model}); self.runcli('create','--spec',spec,'--output',self.root/'padding.hwp',ok=False)

if __name__=='__main__': unittest.main()
