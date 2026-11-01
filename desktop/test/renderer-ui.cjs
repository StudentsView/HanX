// Run with: desktop/node_modules/.bin/electron desktop/test/renderer-ui.cjs
// Exercises the real browser UI; only the native IPC/engine boundary is replaced.
const {app,BrowserWindow}=require('electron');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const os=require('node:os');
const path=require('node:path');
app.on('window-all-closed',()=>{});
(async()=>{
 await app.whenReady();
 const directory=await fs.mkdtemp(path.join(os.tmpdir(),'hanx-renderer-ui-'));
 const preload=path.join(directory,'preload.cjs');
 await fs.writeFile(preload,`const {contextBridge}=require('electron');
 const p={inlines:[{text:{_0:'본문',_1:{size:12}}}],markProps:{size:12},props:{alignment:'left'}};
 const states={document:{kind:'document',model:{sections:[{page:{width:595,height:842,marginTop:72,marginBottom:72,marginLeft:72,marginRight:72},blocks:[{paragraph:{_0:p}}]}],images:{}},text:'본문'},spreadsheet:{kind:'spreadsheet',model:{sheets:[{name:'Sheet1',cells:{A1:{input:'=1/0'}},merges:[]},{name:'Sheet2',cells:{},merges:[]}]},calculated:[{A1:{display:'#DIV/0!',type:'error'}},{}],formulaErrors:[{cell:'A1',error:'#DIV/0!'}]},presentation:{kind:'presentation',model:{width:960,height:540,images:{},slides:[{background:{r:255,g:255,b:255},shapes:[{id:1,name:'제목',kind:'text',frame:{x:100,y:100,w:300,h:80},paragraphs:[p]}],notes:'',transition:{kind:'fade',duration:.5}}]}}};
 let current=states.document,operations=[];
 contextBridge.exposeInMainWorld('uiTest',{operations:()=>operations,failNext:()=>{current.fail=true;}});
 contextBridge.exposeInMainWorld('hanx',{initial:async()=>current,newFile:async kind=>current=states[kind],edit:async ops=>{if(current.fail){delete current.fail;throw Error('테스트 작업 오류');}operations.push(...ops);return current;},open:async()=>{},save:async()=>{},undo:async()=>{},copySlide:async()=>{},pasteSlide:async()=>current,onAction:()=>{},reportError:async message=>operations.push({error:message}),clipboard:async action=>operations.push({clipboard:action}),help:async topic=>operations.push({help:topic}),connections:async()=>({engine:'/test/hanx'})});`);
 const win=new BrowserWindow({show:false,width:1280,height:900,webPreferences:{preload,contextIsolation:true,nodeIntegration:false,sandbox:true}});
 const errors=[];win.webContents.on('console-message',(_event,...args)=>{const message=typeof args[0]==='object'?args[0].message:args[1];if(String(message).includes('Uncaught'))errors.push(message);});
 const js=code=>win.webContents.executeJavaScript(code);
 const screenshot=async name=>{if(!process.env.HANX_RENDERER_UI_OUTPUT)return;await fs.mkdir(process.env.HANX_RENDERER_UI_OUTPUT,{recursive:true});await js('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))');await fs.writeFile(path.join(process.env.HANX_RENDERER_UI_OUTPUT,name+'.png'),(await win.webContents.capturePage()).toPNG());};
 const wait=async expression=>{for(let i=0;i<100;i++){if(await js(expression))return;await new Promise(r=>setTimeout(r,20));}throw Error('Timed out: '+expression);};
 const click=async label=>{assert.equal(await js(`(()=>{const b=[...document.querySelectorAll('button')].find(b=>b.textContent.trim()===${JSON.stringify(label)}&&!b.closest('[hidden]'));if(!b)return false;b.click();return true;})()`),true,'Missing visible control: '+label);};
 const setField=async(label,value)=>{assert.equal(await js(`(()=>{const input=[...document.querySelectorAll('#tools label')].find(label=>label.querySelector('span')?.textContent===${JSON.stringify(label)})?.querySelector('input,select');if(!input)return false;input.value=${JSON.stringify(value)};input.dispatchEvent(new Event('change'));return true;})()`),true,'Missing ribbon field: '+label);await wait('!busy');};
 const newFile=async kind=>{await js(`document.getElementById('newKind').value=${JSON.stringify(kind)};document.getElementById('new').click()`);await wait(`!busy&&state.kind===${JSON.stringify(kind)}`);};
 try{
  await win.loadFile(path.join(__dirname,'../index.html'));await wait('Boolean(state&&!busy)');
  assert.equal(await js("getComputedStyle(document.querySelector('.navigation')).display"),'none','Document navigation should leave room for paper');
  assert.equal(await js("getComputedStyle(document.getElementById('inspector')).display"),'none','Document formatting belongs in ribbon');
  await screenshot('document');
  await js("(()=>{const p=document.querySelector('.rich-paragraph');p.focus();const range=document.createRange();range.selectNodeContents(p);const selection=getSelection();selection.removeAllRanges();selection.addRange(range);const copy=[...document.querySelectorAll('#tools button')].find(b=>b.textContent==='복사');copy.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true}));copy.click();})()");await wait('!busy');
  assert.equal(await js("document.activeElement.className"),'rich-paragraph','Clipboard commands retain the editor focus');
  assert.equal(await js("uiTest.operations().at(-1).clipboard"),'copy');
  await js("document.activeElement.blur()");
  await click('삽입');await click('표 삽입');await wait('!busy');
  assert.equal(await js("uiTest.operations().at(-1).op"),'append_block');
  await click('홈');await click('굵게');await wait('!busy');
  assert.equal(await js("uiTest.operations().at(-1).style.bold"),true);
  await setField('글꼴','Arial');assert.equal(await js("uiTest.operations().at(-1).style.font"),'Arial');
  await js("uiTest.failNext();edit({op:'test_failure'})");await wait('!busy');
  assert.equal(await js("document.body.textContent.includes('테스트 작업 오류')"),false,'Operation errors must not become inline prose');
  assert.equal(await js("document.getElementById('status').textContent"),'준비됨');
  assert.equal(await js("uiTest.operations().at(-1).error"),'테스트 작업 오류','Local failures must reach popup presentation');
  await js("document.querySelector('[role=tab][aria-selected=true]').dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowRight',bubbles:true}))");
  assert.equal(await js("document.querySelector('[role=tab][aria-selected=true]').textContent"),'글자 모양');
  assert.equal(await js("document.activeElement.getAttribute('role')"),'tab');
  await newFile('spreadsheet');
  assert.equal(await js("document.querySelector('[aria-label=\"A1\"]').value"),'#DIV/0!','Formula error remains cell data');
  assert.equal(await js("document.querySelector('.formula-errors')"),null,'No persistent formula error list');
  assert.equal(await js("document.getElementById('outline').parentElement.id"),'sheetTabs','Worksheets belong below grid');
  await screenshot('spreadsheet');
  await js("(()=>{const input=[...document.querySelectorAll('#tools label')].find(label=>label.querySelector('span')?.textContent==='셀 또는 범위').querySelector('input');input.value='A1:B3';input.dispatchEvent(new Event('change'));document.getElementById('formula').value='42';document.getElementById('formula').dispatchEvent(new Event('change'));})()");await wait('!busy');
  assert.equal(await js("uiTest.operations().at(-1).cell"),'A1','Formatting range must not replace the active formula cell');
  await setField('셀 또는 범위','A1:B3');
  for(const [label,value,key] of [['글꼴','Arial','fontName'],['글자 크기 (pt)','18','fontSize']]){await setField(label,value);assert.equal(await js(`uiTest.operations().at(-1).style.${key}`),key==='fontSize'?18:value);assert.equal(await js('uiTest.operations().at(-1).range'),'A1:B3');}
  for(const [label,key] of [['기울임','italic'],['밑줄','underline']]){await click(label);await wait('!busy');assert.equal(await js(`uiTest.operations().at(-1).style.${key}`),true);assert.equal(await js('uiTest.operations().at(-1).range'),'A1:B3');}
  await setField('셀 정렬','center');assert.equal(await js('uiTest.operations().at(-1).style.align'),'center');
  await click('셀 서식');await setField('글자 색','#123456');assert.equal(await js('uiTest.operations().at(-1).style.color'),'123456');
  await setField('채우기','#e7effa');assert.equal(await js('uiTest.operations().at(-1).style.fill'),'e7effa');
  await js("state.model.sheets[0].cells.A1.style={fontName:'Arial',fontSize:18,italic:true,underline:true,align:'center',color:'123456',fill:'E7EFFA'};render()");
  assert.deepEqual(await js("(()=>{const s=getComputedStyle(document.querySelector('[aria-label=\"A1\"]'));return {font:s.fontFamily,size:s.fontSize,italic:s.fontStyle,underline:s.textDecorationLine,align:s.textAlign,color:s.color,fill:s.backgroundColor};})()"),{font:'Arial',size:'24px',italic:'italic',underline:'underline',align:'center',color:'rgb(18, 52, 86)',fill:'rgb(231, 239, 250)'});
  await click('Sheet2');assert.equal(await js('selected'),1);
  await newFile('presentation');await click('전환');
  assert.equal(await js("Boolean(document.querySelector('#tools select'))"),true,'Transition controls belong to ribbon');
  await js("(()=>{const input=document.querySelector('#tools select');input.value='wipe';input.dispatchEvent(new Event('change'));})()");await wait('!busy');
  assert.equal(await js("uiTest.operations().at(-1).kind"),'wipe');
  assert.equal(await js("document.querySelector('#properties p')"),null,'No permanent slide instructions');
  await js("document.querySelector('.slide-shape').click()");
  assert.ok(await js("document.querySelector('#properties input[type=number]')!==null"),'Geometry remains contextual');
  await screenshot('presentation');
  await js("document.querySelector('[role=tab][aria-selected=true]').dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowLeft',bubbles:true}))");await wait('!busy');
  assert.notEqual(await js("uiTest.operations().at(-1)?.op"),'update_shape','Ribbon navigation must not move the selected shape');
  win.setSize(900,700);await screenshot('presentation-narrow');
  assert.deepEqual(errors,[]);console.log('HANX_RENDERER_UI_OK');
 }finally{win.destroy();await fs.rm(directory,{recursive:true,force:true});app.quit();}
})().catch(error=>{console.error(error);app.exit(1);});
