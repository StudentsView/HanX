const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const path=require('node:path');
module.exports=async function smoke(win,session){
 const js=code=>win.webContents.executeJavaScript(code);
 async function waitFor(expression){for(let i=0;i<150;i++){if(await js(expression))return;await new Promise(r=>setTimeout(r,100));}throw Error('Timed out: '+expression);}
 await waitFor('Boolean(state && !busy)');
 assert.equal(await js("document.documentElement.lang"),'ko');
 assert.ok(await js("Boolean(document.querySelector('#connections'))"));
 await js("edit({op:'set_paragraph',section:0,block:0,runs:[{text:'데스크톱 문서',bold:true},{text:' 편집',italic:true}]})");
 await waitFor("!busy && document.querySelector('.rich-paragraph span')?.textContent==='데스크톱 문서'");
 const doc=path.join(session.directory,'gui.docx');await session.save(doc);await session.open(doc);await js('run(()=>hanx.undo(false))');await waitFor('!busy');
 await js("run(()=>hanx.newFile('spreadsheet'))");await waitFor("!busy && state.kind==='spreadsheet'");
 await js("edit({op:'set_range',sheet:0,start:'A1',values:[[{input:'7'},{input:'=A1*6'}]]})");
 await waitFor("!busy && document.querySelector('[aria-label=\"B1\"]')?.value==='42'");
 await js("document.querySelector('[aria-label=\"A1\"]').focus(); document.querySelector('#formula').value='8'; document.querySelector('#formula').dispatchEvent(new Event('change'))");
 await waitFor("!busy && state.calculated[0].B1.display==='48'");
 await session.save(path.join(session.directory,'gui.xlsx'));
 await js("run(()=>hanx.newFile('presentation'))");await waitFor("!busy && state.kind==='presentation'");
 await js("edit({op:'add_shape',slide:0,value:{kind:'rect',x:40,y:50,width:160,height:80,rotation:30}},{op:'set_transition',slide:0,kind:'fade',duration:0.4})");await waitFor('!busy');
 await js("document.querySelector('.slide-shape').click()");assert.ok(await js("Boolean(document.querySelector('.resize-handle'))"));
 await js("duplicateSlide()");await waitFor('!busy && state.model.slides.length===2');
 await session.save(path.join(session.directory,'gui.pptx'));
 const pdf=path.join(session.directory,'gui.pdf');await session.save(pdf);assert.equal((await fs.readFile(pdf)).subarray(0,4).toString(),'%PDF');
 await win.webContents.capturePage().then(image=>fs.writeFile(path.join(session.directory,'smoke.png'),image.toPNG()));
 console.log('HANX_GUI_SMOKE_OK: native renderer open/edit/calculation/save/docx/xlsx/pptx/pdf');
};
