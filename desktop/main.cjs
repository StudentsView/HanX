const {app,BrowserWindow,ipcMain,dialog,Menu}=require('electron');
const path=require('node:path');
const {pathToFileURL}=require('node:url');
const {Session,resolveEngine,formats}=require('./engine.cjs');
let win,session,queue=Promise.resolve(),quitting=false;
const smoke=process.argv.includes('--smoke-test');
const page=pathToFileURL(path.join(__dirname,'index.html')).href;
async function confirmDiscard(){if(smoke||!session?.dirty)return true;const {response}=await dialog.showMessageBox(win,{type:'question',message:'저장하지 않은 변경 사항을 버릴까요?',detail:'계속 편집하려면 돌아가서 저장하세요.',buttons:['계속 편집','변경 사항 버리기'],defaultId:0,cancelId:0});return response===1;}
function handle(name,fn){ipcMain.handle(name,(event,...args)=>{if(event.sender!==win.webContents || event.senderFrame!==win.webContents.mainFrame || event.senderFrame.url!==page)throw Error('Untrusted editor request.');const result=queue.then(()=>fn(...args));queue=result.catch(()=>{});return result;});}
app.whenReady().then(async()=>{
 win=new BrowserWindow({width:1320,height:900,minWidth:900,minHeight:640,backgroundColor:'#e9edf3',title:'HanX',webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,sandbox:true,nodeIntegration:false,webSecurity:true}});
 win.webContents.setWindowOpenHandler(()=>({action:'deny'}));
 win.webContents.on('will-navigate',e=>e.preventDefault());
 win.webContents.session.setPermissionRequestHandler((_contents,_permission,callback)=>callback(false));
 win.webContents.session.webRequest.onBeforeRequest((details,callback)=>callback({cancel:!details.url.startsWith('file://')}));
 let engineError;
 try{session=await new Session(await resolveEngine({resourcesPath:process.resourcesPath,appPath:__dirname,packaged:app.isPackaged})).init();}catch(e){engineError=e.message;}
 handle('hanx:initial',async()=>{if(engineError)throw Error(engineError);return session.create('document');});
 handle('hanx:new',async kind=>{if(!await confirmDiscard())return null;return session.create(kind);});
 handle('hanx:open',async()=>{if(!await confirmDiscard())return null;const result=await dialog.showOpenDialog(win,{properties:['openFile'],filters:[{name:'Office files',extensions:['hwp','hwpx','docx','pptx','xlsx','csv','tsv','txt','md','hml','json','pdf']}]});return result.canceled?null:session.open(result.filePaths[0]);});
 handle('hanx:edit',ops=>session.edit(ops));
 handle('hanx:copy-slide',index=>session.copySlide(index));
 handle('hanx:paste-slide',index=>session.pasteSlide(index));
 handle('hanx:connections',()=>({version:app.getVersion(),engine:session.executable,command:'mcp',transport:'stdio',local:true}));
 handle('hanx:undo',redo=>session.undo(redo===true));
 handle('hanx:save',async as=>{if(typeof as!=='boolean')throw Error('Invalid save request.');let destination=session.source;if(as||!destination||path.extname(destination).toLowerCase()==='.pdf'){const result=await dialog.showSaveDialog(win,{defaultPath:destination||`새 파일.${formats[session.kind][0]}`,filters:formats[session.kind].map(ext=>({name:ext.toUpperCase(),extensions:[ext]}))});if(result.canceled)return null;destination=result.filePath;}return session.save(destination);});
 Menu.setApplicationMenu(Menu.buildFromTemplate([{label:'파일',submenu:[{label:'열기…',accelerator:'CmdOrCtrl+O',click:()=>win.webContents.send('hanx:action','open')},{label:'저장',accelerator:'CmdOrCtrl+S',click:()=>win.webContents.send('hanx:action','save')},{label:'다른 이름으로 저장…',accelerator:'CmdOrCtrl+Shift+S',click:()=>win.webContents.send('hanx:action','saveAs')},{type:'separator'},{role:'quit'}]},{label:'편집',submenu:[{label:'실행 취소',accelerator:'CmdOrCtrl+Z',click:()=>win.webContents.send('hanx:action','undo')},{label:'다시 실행',accelerator:'CmdOrCtrl+Shift+Z',click:()=>win.webContents.send('hanx:action','redo')},{type:'separator'},{role:'cut'},{role:'copy'},{role:'paste'},{role:'selectAll'}]},{label:'보기',submenu:[{role:'resetZoom'},{role:'zoomIn'},{role:'zoomOut'},{role:'togglefullscreen'}]}]));
 win.on('close',e=>{if(!quitting&&session?.dirty){e.preventDefault();queue.then(async()=>{if(await confirmDiscard()){quitting=true;win.close();}});}});
 await win.loadFile(path.join(__dirname,'index.html'));
 if(smoke){try{await require('./smoke.cjs')(win,session);quitting=true;await session.close();app.exit(0);}catch(error){console.error('HANX_GUI_SMOKE_FAILED',error);quitting=true;app.exit(1);}}
});
app.on('window-all-closed',()=>app.quit());
app.on('will-quit',()=>{session?.close();});
