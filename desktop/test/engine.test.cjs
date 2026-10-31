const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const path=require('node:path');
const {Session,validateOperations,engineCandidates}=require('../engine.cjs');
const M=require('../model.js');
const executable=process.env.HANX_CLI_PATH||path.resolve(__dirname,'../../build/hanx-cli');
test('renderer operations reject nested paths and non-finite input',()=>{
 assert.throws(()=>validateOperations([{op:'add_shape',slide:0,value:{kind:'image',imagePath:'/etc/passwd'}}]));
 assert.throws(()=>validateOperations([{op:'append_block',block:{path:'/etc/passwd'}}]));
 assert.throws(()=>validateOperations([{op:'update_shape',width:NaN}]));
});
test('packaged engine cannot be replaced by an environment path',()=>assert.ok(!engineCandidates({resourcesPath:'/app/resources',appPath:'/app',packaged:true,env:{HANX_CLI_PATH:'/tmp/unsafe'}}).includes('/tmp/unsafe')));
test('model exposes safe images and preserves rich run styles',()=>{
 assert.equal(M.imageSource({name:'x.svg',data:'PHN2Zz4='}),null);
 assert.equal(M.imageSource({name:'x.png',data:'YWJj'}),'data:image/png;base64,YWJj');
 assert.equal(M.runStyle({size:18,bold:true,color:{r:1,g:2,b:3}}).color,'#010203');
});
test('native session edits rich documents, undo/redo and Office conversion',async()=>{
 const s=await new Session(executable).init();try{
 await s.create('document');await s.edit([{op:'set_paragraph',section:0,block:0,runs:[{text:'한글 ',bold:true},{text:'HanX',italic:true}],alignment:'center'}]);
 let d=await s.read();assert.match(d.text,/한글 HanX/);assert.equal(d.model.sections[0].blocks[0].paragraph._0.inlines[0].text._1.bold,true);
 await s.edit([{op:'append_block',section:0,block:{type:'table',rows:[['A','B'],['1','2']]}}]);await s.undo();assert.equal((await s.read()).model.sections[0].blocks.length,1);await s.undo(true);
 const output=path.join(s.directory,'roundtrip.docx');await s.save(output);await s.open(output);assert.match((await s.read()).text,/한글 HanX/);
 const pdf=path.join(s.directory,'document.pdf');await s.save(pdf);assert.equal((await fs.readFile(pdf)).subarray(0,4).toString(),'%PDF');
 }finally{await s.close();}
});
test('native session returns calculated spreadsheet display and formula inputs',async()=>{
 const s=await new Session(executable).init();try{await s.create('spreadsheet');await s.edit([{op:'set_range',sheet:0,start:'A1',values:[[{input:'4'},{input:'=A1*3'}]]}]);const d=await s.read();assert.equal(d.model.sheets[0].cells.B1.input,'=A1*3');assert.equal(d.calculated[0].B1.display,'12');
 const output=path.join(s.directory,'sheet.xlsx');await s.save(output);await s.open(output);assert.equal((await s.read()).calculated[0].B1.display,'12');
 }finally{await s.close();}
});
test('native slide duplication, geometry, notes and transitions survive PPTX',async()=>{
 const s=await new Session(executable).init();try{await s.create('presentation');await s.edit([{op:'add_shape',slide:0,value:{kind:'rect',x:30,y:40,width:120,height:60,rotation:25,fill:'008C95'}},{op:'set_notes',slide:0,text:'발표 메모'},{op:'set_transition',slide:0,kind:'fade',duration:0.6},{op:'duplicate_slide',slide:0}]);
 const output=path.join(s.directory,'slides.pptx');await s.save(output);await s.open(output);const d=await s.read();assert.equal(d.model.slides.length,2);assert.equal(d.model.slides[0].notes,'발표 메모');assert.equal(d.model.slides[0].transition.kind,'fade');assert.equal(d.model.slides[0].shapes.at(-1).rotation,25);
 }finally{await s.close();}
});
test('slide clipboard remains usable after deleting its source',async()=>{
 const s=await new Session(executable).init();try{await s.create('presentation');await s.edit([{op:'set_notes',slide:0,text:'복사한 슬라이드'}]);await s.copySlide(0);await s.edit([{op:'delete_slide',slide:0}]);await s.pasteSlide(0);assert.equal((await s.read()).model.slides[0].notes,'복사한 슬라이드');await s.undo();assert.equal((await s.read()).model.slides.length,0);}finally{await s.close();}
});
test('text edits preserve paragraph layout and reject edits that would remove embedded objects',async()=>{
 const {runEngine}=require('../engine.cjs');const s=await new Session(executable).init();try{await s.create('document');const d=await s.read(),p=d.model.sections[0].blocks[0].paragraph._0;p.props.spaceBefore=18;p.props.firstLine=12;p.props.alignment='right';await runEngine(executable,['create','--spec','-','--output',s.file,'--force'],{kind:'document',model:d.model});await s.edit([{op:'set_paragraph',section:0,block:0,text:'서식 유지'}]);assert.equal((await s.read()).model.sections[0].blocks[0].paragraph._0.props.spaceBefore,18);assert.equal((await s.read()).model.sections[0].blocks[0].paragraph._0.props.alignment,'right');
 const original=await s.read();original.model.sections[0].blocks[0].paragraph._0.inlines.push({image:{id:'fixture',width:20,height:20}});original.model.images.fixture={name:'fixture.png',data:'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lZ8AAAAASUVORK5CYII='};await runEngine(executable,['create','--spec','-','--output',s.file,'--force'],{kind:'document',model:original.model});await assert.rejects(()=>s.edit([{op:'set_paragraph',section:0,block:0,text:'loses image'}]),/그림|object/);
 }finally{await s.close();}
});
test('technical conversion warnings have a short Korean summary',()=>{
 assert.match(M.warningSummary(['Spreadsheet model editing preserves supported cells']),/Excel/);
 assert.match(M.warningSummary(['PDF selectable text has no layout reconstruction']),/PDF/);
 assert.equal(M.warningSummary([]),'');
});
