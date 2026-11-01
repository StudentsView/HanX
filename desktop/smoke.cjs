const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const path=require('node:path');
const {dialog}=require('electron');
const {runEngine}=require('./engine.cjs');
module.exports=async function smoke(win,session){
 const js=code=>win.webContents.executeJavaScript(code);
 const shownNotices=[];dialog.showMessageBox=async(_parent,options)=>{shownNotices.push(options);return {response:0};};
 async function click(id){await js("(()=>{document.getElementById("+JSON.stringify(id)+").click();return new Promise(resolve=>setTimeout(()=>pending.then(resolve),0));})()");}
 async function waitFor(expression){for(let i=0;i<150;i++){if(await js(expression))return;await new Promise(r=>setTimeout(r,100));}throw Error('Timed out: '+expression+'\n'+await js("document.getElementById('status').textContent"));}
 const screenshotDir=process.env.HANX_SMOKE_OUTPUT_DIR;if(screenshotDir)await fs.mkdir(screenshotDir,{recursive:true});
 async function settle(){await js('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))');}
 async function screenshot(name){await settle();if(screenshotDir)await fs.writeFile(path.join(screenshotDir,name+'.png'),(await win.webContents.capturePage()).toPNG());}
 async function saveAs(filename){const target=path.join(session.directory,filename);dialog.showSaveDialog=async()=>({canceled:false,filePath:target});await click('saveAs');await waitFor('!busy');await fs.access(target);return target;}
 async function open(filename){dialog.showOpenDialog=async()=>({canceled:false,filePaths:[filename]});await click('open');await waitFor(`!busy && state.path===${JSON.stringify(filename)}`);}
 async function newFile(kind){await js(`document.getElementById('newKind').value=${JSON.stringify(kind)};document.getElementById('new').click()`);await waitFor(`!busy && state.kind===${JSON.stringify(kind)} && !state.path`);}
 async function drag(selector,dx,dy){const p=await js(`(()=>{const r=document.querySelector(${JSON.stringify(selector)}).getBoundingClientRect();return {x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)}})()`);await settle();win.focus();win.webContents.sendInputEvent({type:'mouseMove',...p});await new Promise(r=>setTimeout(r,50));win.webContents.sendInputEvent({type:'mouseDown',button:'left',clickCount:1,...p});await new Promise(r=>setTimeout(r,50));win.webContents.sendInputEvent({type:'mouseMove',modifiers:['leftButtonDown'],x:p.x+dx,y:p.y+dy});await new Promise(r=>setTimeout(r,50));win.webContents.sendInputEvent({type:'mouseUp',button:'left',clickCount:1,x:p.x+dx,y:p.y+dy});}
 await waitFor('Boolean(state && !busy)');win.show();win.focus();await settle();assert.equal(await js('document.documentElement.lang'),'ko');
 await js("document.getElementById('connections').click()");await waitFor("document.getElementById('connectionDialog').open");assert.match(await js("document.getElementById('mcpCommand').value"),/mcp$/);await js("document.getElementById('connectionDialog').close()");
 await js("edit({op:'set_paragraph',section:0,block:0,runs:[{text:'데스크톱 문서',bold:true},{text:' 편집',italic:true}]})");await waitFor("!busy && document.querySelector('.rich-paragraph span')?.textContent==='데스크톱 문서'");
 await js("(()=>{const p=document.querySelector('.rich-paragraph');p.focus();p.querySelector('span').textContent='문서 편집 확인';p.blur();p.dispatchEvent(new FocusEvent('blur'));})()");await waitFor("!busy && state.text.includes('문서 편집 확인')");
 await js("edit({op:'append_paragraph',section:0,text:'분기 매출 보고서',style:{size:20,bold:true,color:'1659A7'}},{op:'append_paragraph',section:0,text:'2026년 3분기 문서 처리 현황'},{op:'append_block',section:0,block:{type:'table',rows:[['작업','진행 상황'],['문서 편집','완료'],['데이터 계산','확인 중']]}})");await waitFor('!busy && state.model.sections[0].blocks.length===4');
 const doc=await saveAs('gui.docx');await open(doc);assert.match(await js('state.text'),/문서 편집 확인/);await screenshot('document');
 const protectedModel=(await session.read()).model,protectedTable=protectedModel.sections[0].blocks[3].table._0,nested=structuredClone(protectedTable),imageID='protected-cell-image';
 protectedModel.images[imageID]={name:'cell.png',data:'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lZ8AAAAASUVORK5CYII='};
 protectedTable.rows[0][0].blocks[0].paragraph._0.inlines.push({image:{id:imageID,width:20,height:20}});
 protectedTable.rows[1][0].blocks[0].paragraph._0.inlines.push({field:{_0:'page',_1:structuredClone(protectedTable.rows[1][0].blocks[0].paragraph._0.markProps)}});
 protectedTable.rows[2][0].blocks.push({table:{_0:nested}});
 const protectedFile=path.join(session.directory,'protected-table.json');await runEngine(session.executable,['create','--spec','-','--output',protectedFile],{kind:'document',model:protectedModel});await open(protectedFile);
 assert.equal(await js("document.querySelector('.paper .doc-table').rows[0].cells[0].getAttribute('aria-readonly')"),'true');
 await js("(()=>{const table=document.querySelector('.paper .doc-table');for(const row of table.rows)row.cells[0].dispatchEvent(new MouseEvent('dblclick',{bubbles:true}));})()");
 assert.equal(await js("document.querySelectorAll('.paper .doc-table textarea').length"),0);assert.equal(await js("document.querySelectorAll('.paper .doc-table img').length"),1);
 await js("(()=>{const td=document.querySelector('.paper .doc-table').rows[0].cells[1];td.dispatchEvent(new MouseEvent('dblclick',{bubbles:true}));const input=td.querySelector('textarea');input.value='편집한 일반 셀';input.dispatchEvent(new Event('change'));})()");
 await waitFor("!busy && state.model.sections[0].blocks[3].table._0.rows[0][1].blocks[0].paragraph._0.inlines[0].text._0==='편집한 일반 셀'");
 assert.equal(await js("document.querySelectorAll('.paper .doc-table img').length"),1);
 await newFile('spreadsheet');
 await js("edit({op:'set_range',sheet:0,start:'A1',values:[[{input:'7'},{input:'=A1*6'}]]})");await waitFor("!busy && document.querySelector('[aria-label=\"B1\"]')?.value==='42'");
 await js("document.querySelector('[aria-label=\"A1\"]').focus();document.getElementById('formula').value='8';document.getElementById('formula').dispatchEvent(new Event('change'))");await waitFor("!busy && state.calculated[0].B1.display==='48'");
 await js("edit({op:'set_range',sheet:0,start:'A3',values:[['항목','수량','단가','금액'],['노트',12,2500,{input:'=B4*C4'}],['펜',8,1200,{input:'=B5*C5'}],['합계','','',{input:'=SUM(D4:D5)'}]]},{op:'style_range',sheet:0,range:'A3:D3',style:{bold:true,fill:'1659A7',color:'FFFFFF'}},{op:'style_range',sheet:0,range:'A6:D6',style:{bold:true,fill:'D9EFF0'}})");await waitFor("!busy && state.calculated[0].D6.display==='39600'");
 const sheet=await saveAs('gui.xlsx');await open(sheet);await screenshot('spreadsheet');
 await newFile('presentation');
 await js("edit({op:'add_shape',slide:0,value:{kind:'rect',x:400,y:300,width:160,height:80,rotation:30,fill:'008B94'}},{op:'set_transition',slide:0,kind:'fade',duration:0.4})");await waitFor('!busy && state.model.slides[0].shapes.length===3');
 await js("document.querySelector('.slide-shape:last-child').click()");assert.ok(await js("Boolean(document.querySelector('.resize-handle'))"));
 await drag('.resize-handle.se',20,15);await waitFor('!busy && state.model.slides[0].shapes[2].frame.w>160');
 await js('duplicateSlide()');await waitFor('!busy && state.model.slides.length===2');
 const slides=await saveAs('gui.pptx');await open(slides);assert.equal(await js('state.model.slides[0].transition.kind'),'fade');await screenshot('presentation');
 const pdf=await saveAs('gui.pdf');assert.equal((await fs.readFile(pdf)).subarray(0,4).toString(),'%PDF');
 await open(pdf);assert.ok(shownNotices.some(n=>n.type==='warning'&&n.detail.includes('PDF')));const warningCount=shownNotices.length;
 await js("edit({op:'append_paragraph',section:0,text:'알림 반복 확인'})");await waitFor('!busy');assert.equal(shownNotices.length,warningCount);
 assert.equal(await js("Boolean(document.getElementById('error')||document.getElementById('notices')||document.querySelector('.local-note'))"),false);
 await js("run(()=>hanx.edit([{op:'not-supported'}]))");await waitFor('!busy');assert.equal(shownNotices.length,warningCount+1);assert.equal(shownNotices.at(-1).type,'error');
 await js("run(()=>{throw Error('로컬 화면 오류 확인')})");await waitFor('!busy');assert.equal(shownNotices.length,warningCount+2);assert.ok(shownNotices.at(-1).detail.includes('로컬 화면 오류 확인'));
 await click('help');assert.equal(shownNotices.at(-1).type,'info');
 console.log('HANX_GUI_SMOKE_OK: native renderer open/edit/calculation/resize/save/docx/xlsx/pptx/pdf');
};
