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
const {runEngine}=require('../engine.cjs');
const {deflateSync}=require('node:zlib');
function pngPixel(red,green,blue){
 const chunk=(type,data)=>{const name=Buffer.from(type),payload=Buffer.concat([name,data]);let crc=0xffffffff;for(const byte of payload){crc^=byte;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}const size=Buffer.alloc(4),sum=Buffer.alloc(4);size.writeUInt32BE(data.length);sum.writeUInt32BE((crc^0xffffffff)>>>0);return Buffer.concat([size,payload,sum]);};
 const header=Buffer.alloc(13);header.writeUInt32BE(1,0);header.writeUInt32BE(1,4);header[8]=8;header[9]=6;
 return Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',header),chunk('IDAT',deflateSync(Buffer.from([0,red,green,blue,255]))),chunk('IEND',Buffer.alloc(0))]).toString('base64');
}
async function writeModel(s,kind,model){await runEngine(executable,['create','--spec','-','--output',s.file,'--force'],{kind,model});}
for(const object of ['image','field','nested table'])test(`table cell ${object} survives a rejected text edit without changing session history`,async()=>{
 const s=await new Session(executable).init();try{await s.create('document');await s.edit([{op:'append_block',section:0,block:{type:'table',rows:[['그림 설명']]} }]);const d=await s.read(),table=d.model.sections[0].blocks[1].table._0,cell=table.rows[0][0],p=cell.blocks[0].paragraph._0;
 if(object==='image'){p.inlines.push({image:{id:'caption-image',width:20,height:20}});d.model.images['caption-image']={name:'caption.png',data:pngPixel(20,90,170)};}
 else if(object==='field')p.inlines.push({field:{_0:'page',_1:structuredClone(p.markProps)}});
 else cell.blocks.push({table:{_0:structuredClone(table)}});
 await writeModel(s,'document',d.model);const before=await s.read(),file=s.file,history=[...s.history];
 await assert.rejects(()=>s.edit([{op:'set_cell',section:0,block:1,row:0,column:0,text:'새 설명'}]),/읽기 전용/);
 assert.equal(s.file,file);assert.deepEqual(s.history,history);assert.deepEqual((await s.read()).model,before.model);
 }finally{await s.close();}
});
test('cross-deck slide paste remaps colliding image IDs and preserves both images through PPTX',async()=>{
 const s=await new Session(executable).init();try{await s.create('presentation');const source=await s.read();source.model.images={'image1.png':{name:'image1.png',data:pngPixel(255,0,0)},'unused.png':{name:'unused.png',data:pngPixel(0,255,0)}};
 Object.assign(source.model.slides[0].shapes[0],{kind:'image',imageID:'image1.png',paragraphs:[]});source.model.slides[0].notes='source';await writeModel(s,'presentation',source.model);await s.copySlide(0);
 await s.create('presentation');const destination=await s.read();destination.model.images={'image1.png':{name:'image1.png',data:pngPixel(0,0,255)}};Object.assign(destination.model.slides[0].shapes[0],{kind:'image',imageID:'image1.png',paragraphs:[]});destination.model.slides[0].notes='destination';await writeModel(s,'presentation',destination.model);
 await s.pasteSlide(1);const pasted=await s.read(),oldID=pasted.model.slides[0].shapes[0].imageID,newID=pasted.model.slides[1].shapes[0].imageID;assert.equal(oldID,'image1.png');assert.notEqual(newID,oldID);assert.equal(pasted.model.images[oldID].data,destination.model.images['image1.png'].data);assert.equal(pasted.model.images[newID].data,source.model.images['image1.png'].data);assert.equal(Object.keys(pasted.model.images).length,2);
 const output=path.join(s.directory,'two-decks.pptx');await s.save(output);await s.open(output);const roundtrip=await s.read();const first=roundtrip.model.slides.find(slide=>slide.notes==='destination'),second=roundtrip.model.slides.find(slide=>slide.notes==='source');assert.equal(roundtrip.model.images[first.shapes[0].imageID].data,destination.model.images['image1.png'].data);assert.equal(roundtrip.model.images[second.shapes[0].imageID].data,source.model.images['image1.png'].data);
 }finally{await s.close();}
});
