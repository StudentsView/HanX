import base64
import json
import os
import pathlib
import subprocess
import tempfile
import unittest


BIN = pathlib.Path(os.environ.get('HANX_BIN', 'build/hanx-cli')).resolve()


def pdf_fixture(pages):
    """Small independent fixture: (width, height, text or None) per page."""
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>', b'',
               b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>']
    kids = []
    for width, height, text in pages:
        page_id = len(objects) + 1
        kids.append(f'{page_id} 0 R')
        content = (f'BT /F1 18 Tf 36 {height - 50} Td ({text}) Tj ET'.encode()
                   if text is not None else b'0.8 g 36 36 120 120 re f')
        objects.extend([
            (f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width} {height}] '
             f'/Resources << /Font << /F1 3 0 R >> >> /Contents {page_id + 1} 0 R >>').encode(),
            f'<< /Length {len(content)} >>\nstream\n'.encode() + content + b'\nendstream'])
    objects[1] = f'<< /Type /Pages /Count {len(kids)} /Kids [{" ".join(kids)}] >>'.encode()
    out = bytearray(b'%PDF-1.4\n')
    offsets = [0]
    for i, value in enumerate(objects, 1):
        offsets.append(len(out))
        out.extend(f'{i} 0 obj\n'.encode() + value + b'\nendobj\n')
    xref = len(out)
    out.extend(f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'.encode())
    for offset in offsets[1:]:
        out.extend(f'{offset:010d} 00000 n \n'.encode())
    out.extend((f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\n'
                f'startxref\n{xref}\n%%EOF\n').encode())
    return bytes(out)


class PDF(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='HanX PDF ')
        self.root = pathlib.Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def cli(self, *args, ok=True):
        p = subprocess.run([str(BIN), *map(str, args)], text=True, capture_output=True)
        self.assertEqual(p.returncode == 0, ok, (p.returncode, p.stdout, p.stderr))
        result = json.loads(p.stdout)
        self.assertEqual(result['ok'], ok, result)
        return result['data'] if ok else result['error']

    def create(self, name, spec):
        source = self.root / (name + '.json')
        source.write_text(json.dumps(spec, ensure_ascii=False))
        output = self.root / (name + '.pdf')
        self.cli('create', '--spec', source, '--output', output)
        self.assertTrue(output.read_bytes().startswith(b'%PDF-'))
        return output

    def test_pdf_text_import_keeps_page_sizes_and_reports_extraction_limits(self):
        source = self.root / 'source.pdf'
        source.write_bytes(pdf_fixture([(612, 792, 'First page'), (420, 595, 'Second page')]))
        result = self.cli('read', source)
        self.assertEqual(result['kind'], 'document')
        self.assertIn('First page', result['text'])
        self.assertIn('Second page', result['text'])
        sections = result['model']['sections']
        self.assertEqual(len(sections), 2)
        self.assertEqual([(s['page']['width'], s['page']['height']) for s in sections],
                         [(612, 792), (420, 595)])
        self.assertTrue(any('PDF' in w and 'OCR' in w for w in result['warnings']))
        converted = self.root / 'editable.docx'
        self.cli('convert', source, '--output', converted)
        self.assertIn('Second page', self.cli('read', converted)['text'])

    def test_pdf_signature_import_does_not_depend_on_filename(self):
        source = self.root / 'document.bin'
        source.write_bytes(pdf_fixture([(612, 792, 'Signature detection')]))
        self.assertIn('Signature detection', self.cli('read', source)['text'])

    def test_image_only_pdf_rejected_with_ocr_explanation_without_output(self):
        source = self.root / 'scan.pdf'
        source.write_bytes(pdf_fixture([(612, 792, None)]))
        output = self.root / 'scan.docx'
        result = self.cli('convert', source, '--output', output, ok=False)
        self.assertIn('OCR', result['message'])
        self.assertFalse(output.exists())

    def test_mixed_pdf_keeps_empty_page_and_identifies_missing_text(self):
        source = self.root / 'mixed.pdf'
        source.write_bytes(pdf_fixture([(612, 792, 'Visible text'), (612, 792, None)]))
        result = self.cli('read', source)
        self.assertEqual(len(result['model']['sections']), 2)
        self.assertTrue(any('2' in w and 'OCR' in w for w in result['warnings']))

    def test_password_protected_pdf_returns_actionable_error(self):
        # Independent encrypted one-page PDF; no optional Python PDF library is
        # needed to exercise the CLI's password handling.
        encoded = (
            'JVBERi0xLjQKJeLjz9MKMSAwIG9iago8PAovUHJvZHVjZXIgPDU2ZWNiNDdhNjI+Cj4+CmVuZG9iagoyIDAgb2JqCjw8Ci9UeXBlIC9QYWdlcwovQ291bnQgMQovS2lkcyBbIDQgMCBSIF0KPj4KZW5kb2JqCjMgMCBvYmoKPDwKL1R5cGUgL0NhdGFsb2cKL1BhZ2VzIDIgMCBSCi9PdXRsaW5lcyA3IDAgUgo+PgplbmRvYmoKNCAwIG9iago8PAovVHlwZSAvUGFnZQovTWVkaWFCb3ggWyAwIDAgNjEyIDc5MiBdCi9SZXNvdXJjZXMgPDwKL0ZvbnQgPDwKL0YxIDUgMCBSCj4+Cj4+Ci9Db250ZW50cyA2IDAgUgovUGFyZW50IDIgMCBSCj4+CmVuZG9iago1IDAgb2JqCjw8Ci9UeXBlIC9Gb250Ci9TdWJ0eXBlIC9UeXBlMQovQmFzZUZvbnQgL0hlbHZldGljYQo+PgplbmRvYmoKNiAwIG9iago8PAovTGVuZ3RoIDQyCj4+CnN0cmVhbQqkr4s/RhSPtSTyWGSqEDKiOsQoaLNl469WCPS1M4idBzBGo84u5qyzlUIKZW5kc3RyZWFtCmVuZG9iago3IDAgb2JqCjw8Cj4+CmVuZG9iago4IDAgb2JqCjw8Ci9WIDIKL1IgMwovTGVuZ3RoIDEyOAovUCA0Mjk0OTY3MjkyCi9GaWx0ZXIgL1N0YW5kYXJkCi9PIDwzN2UzYWY4ZTE5YjdhNDE3NmZjMzllZjZjNmYwYmVmYWM1YTU0OGNkZTQwYzZhYzIyMTdiMGZlNjdiZDMwMTZlPgovVSA8ZTBjOThhZDQyZGQ2NTFkNTQ3Yzc2NDc5ZjY2NmEzZmQyOGJmNGU1ZTRlNzU4YTQxNjQwMDRlNTZmZmZhMDEwOD4KPj4KZW5kb2JqCnhyZWYKMCA5CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAxNSAwMDAwMCBuIAowMDAwMDAwMDU5IDAwMDAwIG4gCjAwMDAwMDAxMTggMDAwMDAgbiAKMDAwMDAwMDE4MyAwMDAwMCBuIAowMDAwMDAwMzExIDAwMDAwIG4gCjAwMDAwMDAzODEgMDAwMDAgbiAKMDAwMDAwMDQ3MyAwMDAwMCBuIAowMDAwMDAwNDk0IDAwMDAwIG4gCnRyYWlsZXIKPDwKL1NpemUgOQovUm9vdCAzIDAgUgovSW5mbyAxIDAgUgovSUQgWyA8Mzg2NTMxMzgzODMxNjIzNTMxMzk2MTM4MzkzODM4MzYzMjYzMzkzMTM1NjE2NjMyNjI2MjYxMzEzMjM5MzAzMT4gPDM4NjUzMTM4MzgzMTYyMzUzMTM5NjEzODM5MzgzODM2MzI2MzM5MzEzNTYxNjYzMjYyNjI2MTMxMzIzOTMwMzE+IF0KL0VuY3J5cHQgOCAwIFIKPj4Kc3RhcnR4cmVmCjcwOQolJUVPRgo=')
        source = self.root / 'locked.pdf'
        source.write_bytes(base64.b64decode(encoded))
        error = self.cli('read', source, ok=False)
        self.assertIn('password', error['message'].lower())

    def test_long_document_pdf_paginates_without_losing_final_paragraph(self):
        source = self.create('long', {'kind': 'document',
                                      'blocks': [{'text': f'Paragraph number {i:03d}'} for i in range(160)]})
        result = self.cli('read', source)
        self.assertGreaterEqual(len(result['model']['sections']), 3)
        self.assertIn('Paragraph number 000', result['text'])
        self.assertIn('Paragraph number 159', result['text'])

    def test_document_pdf_exports_tables_and_independent_section_sizes(self):
        source = self.create('document', {'kind': 'document', 'sections': [
            {'page': {'width': 612, 'height': 792}, 'blocks': [
                {'text': 'HanX PDF document', 'style': {'bold': True, 'size': 20}},
                {'type': 'table', 'rows': [['Item', 'Value'], ['Total', '42']]}]},
            {'page': {'width': 595, 'height': 420}, 'text': 'Landscape section'}]})
        result = self.cli('read', source)
        for text in ['HanX PDF document', 'Item', 'Value', 'Total', '42', 'Landscape section']:
            self.assertIn(text, result['text'])
        self.assertEqual([(s['page']['width'], s['page']['height']) for s in result['model']['sections']],
                         [(612, 792), (595, 420)])

    def test_spreadsheet_pdf_exports_every_sheet_and_calculated_values(self):
        source = self.create('workbook', {'kind': 'spreadsheet', 'sheets': [
            {'name': 'Budget', 'rows': [['Amount'], [20], [22], ['=SUM(A2:A3)']]},
            {'name': 'Notes', 'rows': [['Second worksheet']], 'columnWidths': {'A': 200}}]})
        result = self.cli('read', source)
        self.assertIn('42', result['text'])
        self.assertIn('Second worksheet', result['text'])
        self.assertEqual(len(result['model']['sections']), 2)

    def test_presentation_pdf_has_one_page_per_slide(self):
        source = self.create('slides', {'kind': 'presentation', 'width': 960, 'height': 540,
                                      'slides': [{'title': 'Slide one', 'body': ['First body']},
                                                 {'title': 'Slide two', 'body': ['Second body']}]})
        result = self.cli('read', source)
        self.assertIn('Slide one', result['text'])
        self.assertIn('Second body', result['text'])
        self.assertEqual([(s['page']['width'], s['page']['height']) for s in result['model']['sections']],
                         [(960, 540), (960, 540)])

    def test_spreadsheet_pdf_blocks_formula_file_reads(self):
        secret = self.root / 'private.txt'
        secret.write_text('PDF_PRIVATE_FILE_SENTINEL')
        formula = '=IMPORTTEXT("' + secret.as_uri() + '")'
        source = self.create('blocked', {'kind': 'spreadsheet', 'sheets': [
            {'name': 'External data', 'rows': [[formula]], 'columnWidths': {'A': 350}}]})
        text = self.cli('read', source)['text']
        self.assertIn('#BLOCKED!', text)
        self.assertNotIn('PDF_PRIVATE_FILE_SENTINEL', text)

    def test_spreadsheet_pdf_includes_charts_beyond_used_cells_and_view(self):
        source = self.create('far-chart', {'kind': 'spreadsheet', 'sheets': [
            {'name': 'Chart', 'rows': [['Item', 'Value'], ['Alpha', 20], ['Beta', 22]],
             'charts': [{'kind': 'column', 'title': 'Far chart', 'range': 'A1:B3',
                         'x': 3000, 'y': 0, 'width': 300, 'height': 220}]}]})
        result = self.cli('read', source)
        self.assertIn('Far chart', result['text'])
        self.assertGreaterEqual(len(result['model']['sections']), 5)

    def test_spreadsheet_pdf_rejects_unbounded_chart_pagination(self):
        spec = self.root / 'huge-chart.json'
        spec.write_text(json.dumps({'kind': 'spreadsheet', 'sheets': [
            {'name': 'Chart', 'rows': [[1]],
             'charts': [{'kind': 'column', 'title': 'Huge chart', 'range': 'A1:A1',
                         'x': 100000, 'y': 100000, 'width': 100000, 'height': 100000}]}]}))
        output = self.root / 'huge-chart.pdf'
        error = self.cli('create', '--spec', spec, '--output', output, ok=False)
        self.assertIn('PDF', error['message'])
        self.assertIn('limit', error['message'].lower())
        self.assertFalse(output.exists())

    def test_spreadsheet_pdf_keeps_chart_on_sheet_without_cells(self):
        source = self.create('chart-only', {'kind': 'spreadsheet', 'sheets': [
            {'name': 'Chart', 'charts': [{'kind': 'column', 'title': 'Chart only',
                                         'range': 'A1:A1', 'x': 3000, 'y': 100,
                                         'width': 300, 'height': 220}]}]})
        self.assertIn('Chart only', self.cli('read', source)['text'])


if __name__ == '__main__':
    unittest.main()
