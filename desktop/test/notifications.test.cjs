const {test}=require('node:test');
const assert=require('node:assert/strict');
const {NoticeCenter}=require('../notifications.cjs');

const pdfWarning='PDF import extracts selectable text; original layout and OCR are not supported.';
test('a document warning opens once and is shown again for a newly opened document',async()=>{
 const shown=[],center=new NoticeCenter(async options=>{shown.push(options);return {response:0};});
 await center.warnings([pdfWarning,pdfWarning]);
 await center.warnings([pdfWarning]);
 assert.equal(shown.length,1);
 assert.equal(shown[0].type,'warning');
 assert.match(shown[0].detail,/PDF/);
 await center.warnings([pdfWarning,'Unsupported chart was omitted.']);
 assert.equal(shown.length,2);
 center.reset();
 await center.warnings([pdfWarning]);
 assert.equal(shown.length,3);
});
test('empty new documents do not show an alert',async()=>{
 const shown=[],center=new NoticeCenter(async options=>{shown.push(options);return {response:0};});
 await center.warnings([]);await center.warnings(null);await center.warnings(['',null,'   ']);
 assert.equal(shown.length,0);
});
test('warning details remain accessible in a separate dialog',async()=>{
 const shown=[],center=new NoticeCenter(async options=>{shown.push(options);return {response:shown.length===1?1:0};});
 await center.warnings([pdfWarning,'한글 표의 일부 개체를 읽지 못했습니다.']);
 assert.equal(shown.length,2);
 assert.ok(shown[1].detail.includes(pdfWarning));
 assert.ok(shown[1].detail.includes('한글 표'));
});
test('repeated operation failures remain visible and do not share the warning suppression cache',async()=>{
 const shown=[],center=new NoticeCenter(async options=>{shown.push(options);return {response:0};});
 await center.error(new Error('파일을 읽을 수 없습니다.'));await center.error(new Error('파일을 읽을 수 없습니다.'));
 assert.equal(shown.length,2);assert.ok(shown.every(o=>o.type==='error'&&o.detail.includes('파일을 읽을 수 없습니다.')));
});
test('notification dialogs wait for an existing dialog to close',async()=>{
 const shown=[];let closeFirst;
 const center=new NoticeCenter(async options=>{shown.push(options);if(shown.length===1)return new Promise(resolve=>{closeFirst=resolve;});return {response:0};});
 const first=center.warnings([pdfWarning]),second=center.error(new Error('저장 실패'));
 await new Promise(resolve=>setImmediate(resolve));
 assert.equal(shown.length,1);closeFirst({response:0});await Promise.all([first,second]);
 assert.equal(shown.length,2);assert.equal(shown[1].type,'error');
});
test('a dialog failure does not suppress an unacknowledged warning',async()=>{
 let fail=true;const shown=[],center=new NoticeCenter(async options=>{if(fail)throw Error('dialog unavailable');shown.push(options);return {response:0};});
 await assert.rejects(center.warnings([pdfWarning]),/dialog unavailable/);fail=false;
 await center.warnings([pdfWarning]);assert.equal(shown.length,1);
});
test('document-supplied control characters and large errors cannot overwhelm the popup',async()=>{
 const shown=[],center=new NoticeCenter(async options=>{shown.push(options);return {response:0};});
 await center.error(new Error('\u0000'+ 'x'.repeat(100000)));
 assert.ok(shown[0].detail.length<20000);assert.ok(!shown[0].detail.includes('\u0000'));
});
test('help accepts only supported document types',async()=>{
 const shown=[],center=new NoticeCenter(async options=>{shown.push(options);return {response:0};});
 await center.help('spreadsheet');assert.equal(shown.length,1);assert.equal(shown[0].type,'info');
 await assert.rejects(center.help('constructor'));assert.equal(shown.length,1);
});
