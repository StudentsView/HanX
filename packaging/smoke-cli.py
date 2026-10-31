#!/usr/bin/env python3
"""Native release gate: format conversions, restricted formula IO, PDF and MCP."""
import argparse, json, pathlib, subprocess, tempfile
parser = argparse.ArgumentParser()
parser.add_argument('binary')
parser.add_argument('--pdf', action='store_true', help='Require local LibreOffice and Poppler and test PDF import/export')
args = parser.parse_args()
binary = str(pathlib.Path(args.binary).resolve())
def run(*words, stdin=None, ok=True):
    result = subprocess.run([binary, *map(str, words)], input=stdin, capture_output=True,
                            encoding='utf-8', timeout=180)
    assert (result.returncode == 0) == ok, (words, result.returncode, result.stderr, result.stdout)
    payload = json.loads(result.stdout)
    assert payload['ok'] == ok, payload
    return payload['data'] if ok else payload['error']
def create(root, name, spec):
    output = root / name
    run('create', '--spec', '-', '--output', output, stdin=json.dumps(spec, ensure_ascii=False))
    assert output.stat().st_size > 0
    return output
assert run('--version')['version'] == '2.9.0'
capabilities = run('capabilities')
marker = 'HanX portable 한글 290'
with tempfile.TemporaryDirectory(prefix='HanX release 한글 ') as temp:
    root = pathlib.Path(temp)
    for extension in ['hwp', 'hwpx', 'docx']:
        document = create(root, 'created.' + extension, {'kind':'document', 'blocks':[{'text':marker}]})
        assert marker in run('read', document)['text']
        for target in ['hwp', 'hwpx', 'docx', 'xml', 'txt', 'md']:
            output = root / (extension + '-roundtrip.' + target)
            run('convert', document, '--output', output)
            assert marker in run('read', output)['text'], (extension, target)
    sheet = create(root, 'workbook.xlsx', {'kind':'spreadsheet', 'sheets':[
        {'name':'Budget', 'rows':[['Amount'], [20], [22], ['=SUM(A2:A3)']]}]})
    assert run('spreadsheet', 'eval', sheet, '--formula', '=Budget!A4')['value'] == 42
    assert run('spreadsheet', 'eval', sheet, '--formula', '=SEQUENCE(2,2)')['value'] == [[1,2],[3,4]]
    secret = root / 'private.txt'
    secret.write_text('PORTABLE_PRIVATE_SENTINEL', encoding='utf-8')
    assert run('spreadsheet', 'eval', sheet, '--formula', '=IMPORTTEXT("' + secret.as_uri() + '")')['value'] == '#BLOCKED!'
    for extension in ['xlsx', 'csv', 'tsv', 'json', 'xml']:
        output = root / ('sheet.' + extension)
        run('convert', sheet, '--output', output)
        assert run('read', output)['kind'] in ['spreadsheet', 'xml']
    presentation = create(root, 'slides.pptx', {'kind':'presentation', 'slides':[{'title':marker, 'body':['Portable presentation']} ]})
    assert marker in run('read', presentation)['text']
    for extension in ['json', 'xml']:
        output = root / ('slides.' + extension)
        run('convert', presentation, '--output', output)
        assert marker in run('read', output)['text']
    xml = root / 'generic.xml'
    xml.write_text('<root><value>portable XML</value></root>', encoding='utf-8')
    assert 'portable XML' in run('read', xml)['text']
    if args.pdf:
        assert capabilities['pdf']['inputAvailable'] and capabilities['pdf']['outputAvailable'], capabilities['pdf']
        # ASCII markers avoid depending on the runner's optional Korean fonts.
        plain = create(root, 'pdf-document.docx', {'kind':'document','blocks':[{'text':'Portable PDF document'}]})
        slides = create(root, 'pdf-slides.pptx', {'kind':'presentation','slides':[{'title':'Portable slide'}]})
        for source, expected in [(plain,'Portable PDF document'), (sheet,'42'), (slides,'Portable slide')]:
            output = root / (source.stem + '.pdf')
            run('convert', source, '--output', output)
            assert output.read_bytes().startswith(b'%PDF-')
            assert expected in run('read', output)['text']
            editable = root / (source.stem + '-pdf-import.docx')
            run('convert', output, '--output', editable)
            assert expected in run('read', editable)['text']
        blocked = create(root, 'external.xlsx', {'kind':'spreadsheet','sheets':[{'name':'External', 'rows':[
            ['=IMPORTTEXT("' + secret.as_uri() + '")'], ['=WEBSERVICE("http://127.0.0.1:9/private")'], [42]]}]})
        blocked_pdf = root / 'external.pdf'
        run('convert', blocked, '--output', blocked_pdf)
        extracted = run('read', blocked_pdf)['text']
        assert '42' in extracted and 'PORTABLE_PRIVATE_SENTINEL' not in extracted
    requests = [
        {'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'release-smoke','version':'1'}}},
        {'jsonrpc':'2.0','method':'notifications/initialized'},
        {'jsonrpc':'2.0','id':2,'method':'tools/list'},
        {'jsonrpc':'2.0','id':3,'method':'tools/call','params':{'name':'hanx_sheet_eval','arguments':{'input':str(sheet),'formula':'=SUM(Budget!A2:A3)'}}},
    ]
    server = subprocess.run([binary,'mcp'], input=''.join(json.dumps(x)+'\n' for x in requests),
                            capture_output=True,encoding='utf-8',timeout=60)
    assert server.returncode == 0, (server.returncode,server.stderr)
    responses = {x['id']:x for x in map(json.loads,server.stdout.splitlines()) if 'id' in x}
    assert 'result' in responses[1]
    assert any(t['name'] == 'hanx_sheet_eval' for t in responses[2]['result']['tools'])
    result = responses[3]['result']
    assert not result.get('isError'), result
    assert json.loads(result['content'][0]['text'])['data']['value'] == 42, result
print('Native CLI HWP/HWPX/DOCX/XLSX/PPTX/XML, formula isolation, MCP' + (' and PDF' if args.pdf else '') + ' passed.')
