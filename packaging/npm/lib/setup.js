'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const readline = require('node:readline');
const { spawn } = require('node:child_process');
const VERSION = require('../package.json').version;
const RELEASE = `https://github.com/StudentsView/HanX/releases/download/v${VERSION}/`;
function platformKey(platform = process.platform, arch = process.arch) {
  if (!['darwin','linux','win32'].includes(platform) || !['x64','arm64'].includes(arch)) throw new Error(`Unsupported HanX platform: ${platform}-${arch}`);
  return `${platform}-${arch}`;
}
function paths() {
  const base = process.platform === 'win32' ? (process.env.LOCALAPPDATA || path.join(os.homedir(),'AppData','Local')) : (process.env.XDG_DATA_HOME || path.join(os.homedir(),'.local','share'));
  const root = path.join(base,'HanX');
  return { root, state:path.join(root,'setup.json'), cli:path.join(root,VERSION,platformKey(),'cli'), downloads:path.join(root,'downloads') };
}
function readState() { try { return JSON.parse(fs.readFileSync(paths().state,'utf8')); } catch { return {}; } }
function saveState(state) { const file=paths().state; fs.mkdirSync(path.dirname(file),{recursive:true}); fs.writeFileSync(file,JSON.stringify(state,null,2)+'\n',{mode:0o600}); }
function parseOptions(args) {
  const options = {components:undefined,yes:false,pdf:false};
  for (let i=0;i<args.length;i++) {
    if (args[i] === '--yes') options.yes=true;
    else if (args[i] === '--pdf-dependencies') options.pdf=true;
    else if (args[i] === '--components') options.components=args[++i];
    else if (args[i].startsWith('--components=')) options.components=args[i].slice(13);
    else throw new Error(`Unknown setup option: ${args[i]}`);
  }
  if (options.components !== undefined && !['cli','gui','all'].includes(options.components)) throw new Error('Components must be cli, gui, or all.');
  if (args.includes('--components') && options.components === undefined) throw new Error('Components must be cli, gui, or all.');
  return options;
}
async function chooseComponents({input=process.stdin,output=process.stdout}={}) {
  if (!input.isTTY || !output.isTTY || typeof input.setRawMode !== 'function') return 'cli';
  const items=[['cli','CLI만 설치','터미널 명령과 MCP 도구'],['gui','GUI만 설치','문서 편집 앱 · 작은 설정 실행기 유지'],['all','GUI + CLI','문서 편집 앱과 터미널 명령']];
  return new Promise((resolve,reject)=>{
    let selected=0; const wasRaw=Boolean(input.isRaw); const wasPaused=input.isPaused(); let done=false;
    const draw=()=> { output.write('\r\u001b[JHanX 설치 항목 선택 (↑/↓ 이동, Enter 선택, Esc 취소)\n'); for (let i=0;i<items.length;i++) output.write(`${i===selected?'❯':' '} ${items[i][1].padEnd(12)} │ ${items[i][2]}\n`); output.write('\u001b[4A'); };
    const cleanup=()=>{ if(done) return; done=true; input.removeListener('keypress',onKey); input.removeListener('end',onEnd); input.removeListener('error',onError); for(const signal of ['SIGTERM','SIGINT','SIGHUP']) process.removeListener(signal,onTerminate); input.setRawMode(wasRaw); if(wasPaused) input.pause(); output.write('\r\u001b[J\u001b[?25h'); };
    const cancel=()=>{cleanup(); reject(new Error('HanX setup cancelled; no components changed.'));};
    const onEnd=()=>cancel(); const onError=error=>{cleanup();reject(error);}; const onTerminate=()=>cancel();
    const onKey=(str,key={})=>{ if(key.name==='up') selected=(selected+2)%3; else if(key.name==='down') selected=(selected+1)%3; else if(key.name==='return') { const value=items[selected][0]; cleanup(); resolve(value); return; } else if(key.name==='escape'||(key.ctrl&&key.name==='c')) {cancel();return;} else return; draw(); };
    readline.emitKeypressEvents(input); input.setRawMode(true); input.resume(); output.write('\u001b[?25l'); draw(); input.on('keypress',onKey); input.on('end',onEnd); input.on('error',onError); for(const signal of ['SIGTERM','SIGINT','SIGHUP']) process.once(signal,onTerminate);
  });
}
function validateManifest(value,version=VERSION) {
  if (!value || value.version !== version || !Array.isArray(value.assets) || value.assets.length===0) throw new Error('Malformed or wrong-version HanX release manifest.');
  const seen=new Set();
  for (const a of value.assets) {
    if (!a || !['cli','gui'].includes(a.component) || !['darwin','linux','win32'].includes(a.platform) || !['arm64','x64'].includes(a.arch) || typeof a.name!=='string' || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(a.name) || !/^[a-f0-9]{64}$/i.test(a.sha256)) throw new Error('Malformed HanX release asset.');
    const key=`${a.component}-${a.platform}-${a.arch}`; if(seen.has(key)) throw new Error(`Duplicate release asset: ${key}`); seen.add(key);
  }
  return value;
}
function selectAsset(manifest,component,platform=process.platform,arch=process.arch) {
  platformKey(platform,arch); const a=manifest.assets.find(a=>a.component===component&&a.platform===platform&&a.arch===arch);
  if(!a) throw new Error(`No verified ${component} release is available for ${platform}-${arch}.`); return a;
}
function expectedName(component,platform,arch) {
  if(component==='gui') return platform==='darwin'?`HanX-${VERSION}-macOS.zip`:platform==='win32'?`HanX-${VERSION}-win32-${arch}-Setup.exe`:`HanX-${VERSION}-linux-${arch}.AppImage`;
  return platform==='darwin'?`HanX-CLI-${VERSION}-macOS.zip`:`HanX-CLI-${VERSION}-${platform}-${arch}.${platform==='win32'?'zip':'tar.gz'}`;
}
async function remoteText(url) {
  const response=await fetch(url,{signal:AbortSignal.timeout(30000)});
  if(!response.ok) throw Object.assign(new Error(`Release metadata is unavailable (HTTP ${response.status}).`),{status:response.status});
  const body=await response.text(); if(Buffer.byteLength(body)>1024*1024) throw new Error('Release metadata is too large.'); return body;
}
async function releaseManifest() {
  try { return validateManifest(JSON.parse(await remoteText(RELEASE+'hanx-install-manifest.json'))); }
  catch(error) {
    if(error.status!==404) throw error;
    const checksums=await remoteText(RELEASE+'SHA256SUMS'); const assets=[];
    for(const platform of ['darwin','linux','win32']) for(const arch of ['arm64','x64']) for(const component of ['cli','gui']) {
      const name=expectedName(component,platform,arch); const line=checksums.split(/\r?\n/).find(l=>l.trim().split(/\s+\*?/).at(-1)===name);
      if(line) { const sha256=line.trim().split(/\s+/)[0]; assets.push({component,platform,arch,name,sha256}); }
    }
    return validateManifest({version:VERSION,assets});
  }
}
async function verifyFile(file,expected) {
  const hash=crypto.createHash('sha256'); for await (const chunk of fs.createReadStream(file)) hash.update(chunk);
  if(hash.digest('hex')!==expected.toLowerCase()) throw new Error(`SHA256 checksum mismatch for ${path.basename(file)}. Nothing was installed.`);
}
async function writeExclusive(file,bytes) { await fs.promises.writeFile(file,bytes,{flag:'wx',mode:0o600}); }
async function download(asset) {
  const directory=paths().downloads; fs.mkdirSync(directory,{recursive:true}); const destination=path.join(directory,asset.name);
  if(fs.existsSync(destination)) {await verifyFile(destination,asset.sha256); return destination;}
  const temporary=path.join(directory,`.${asset.name}.${crypto.randomUUID()}.part`);
  try {
    const response=await fetch(RELEASE+encodeURIComponent(asset.name),{signal:AbortSignal.timeout(300000)});
    if(!response.ok || !response.body) throw new Error(`Download unavailable (HTTP ${response.status}): ${asset.name}`);
    const handle=await fs.promises.open(temporary,'wx',0o600); let size=0;
    try { for await (const chunk of response.body) { size+=chunk.length; if(size>1024*1024*1024) throw new Error('Release download exceeds 1 GiB.'); await handle.writeFile(chunk); } } finally { await handle.close(); }
    await verifyFile(temporary,asset.sha256);
    // Exclusive link publishes a complete verified file without replacing another installer's download.
    try { await fs.promises.link(temporary,destination); } catch(error) { if(error.code!=='EEXIST') throw error; await verifyFile(destination,asset.sha256); }
    return destination;
  } finally { await fs.promises.rm(temporary,{force:true}); }
}
function run(command,args,options={}) { return new Promise((resolve,reject)=>{ const child=spawn(command,args,{stdio:'inherit',shell:false,...options}); child.once('error',reject); child.once('exit',(code,signal)=>code===0?resolve():reject(new Error(`${path.basename(command)} ${signal?'was interrupted':`exited with code ${code}`}.`))); }); }
async function extract(archive,destination,platform=process.platform) {
  fs.mkdirSync(destination,{recursive:true});
  if(platform==='win32') await run('powershell.exe',['-NoProfile','-NonInteractive','-Command',`Expand-Archive -LiteralPath '${archive.replace(/'/g,"''")}' -DestinationPath '${destination.replace(/'/g,"''")}'`]);
  else if(archive.endsWith('.zip')) await run('/usr/bin/ditto',['-x','-k',archive,destination]);
  else await run('tar',['-xzf',archive,'-C',destination]);
}
function optionalBinary(platform=process.platform,arch=process.arch) {
  try { const root=path.dirname(require.resolve(`@juyoungsuh/hanx-${platformKey(platform,arch)}/package.json`)); const binary=path.join(root,'native',platform==='win32'?'hanx.exe':'hanx'); return fs.existsSync(binary)?binary:null; } catch {return null;}
}
async function installCLI() {
  const destination=paths().cli; const binary=path.join(destination,process.platform==='win32'?'hanx.exe':'hanx');
  if(fs.existsSync(binary)) return binary;
  const file=await download(selectAsset(await releaseManifest(),'cli'));
  const staging=destination+'.'+crypto.randomUUID()+'.tmp';
  try {
    await extract(file,staging);
    if(!fs.existsSync(path.join(staging,path.basename(binary)))) throw new Error('CLI archive does not contain the expected native executable.');
    if(fs.existsSync(destination)) throw new Error(`Refusing to overwrite ${destination}. Remove the incomplete installation and retry.`);
    fs.mkdirSync(path.dirname(destination),{recursive:true}); fs.renameSync(staging,destination);
    return binary;
  } finally { fs.rmSync(staging,{recursive:true,force:true}); }
}
function installedGUI(state=readState()) { return state.guiVersion===VERSION && typeof state.gui==='string' && fs.existsSync(state.gui)?state.gui:null; }
async function installGUI(components='gui', yes=false) {
  const state=readState();
  if(installedGUI(state)&&(process.platform!=='win32'||state.guiComponents===components)) return state.gui;
  const file=await download(selectAsset(await releaseManifest(),'gui'));
  let installed;
  if(process.platform==='darwin') {
    const parent=path.join(os.homedir(),'Applications'); const destination=path.join(parent,'HanX.app');
    const owned=state.gui===destination && typeof state.guiVersion==='string';
    if(fs.existsSync(destination)&&!owned) throw new Error(`Refusing to overwrite unowned ${destination}. Move the existing app before installing this version.`);
    fs.mkdirSync(parent,{recursive:true}); const staging=fs.mkdtempSync(path.join(paths().downloads,'gui-'));
    const replacement=path.join(parent,`.HanX-${crypto.randomUUID()}.app`); const backup=path.join(parent,`.HanX-backup-${crypto.randomUUID()}.app`); let backedUp=false;
    try {
      await extract(file,staging); const app=fs.existsSync(path.join(staging,'HanX.app'))?path.join(staging,'HanX.app'):null;
      if(!app) throw new Error('GUI archive does not contain HanX.app.');
      fs.mkdirSync(replacement); await run('/usr/bin/ditto',[app,replacement]);
      if(fs.existsSync(destination)) { if(!owned) throw new Error(`Refusing to overwrite ${destination}.`); fs.renameSync(destination,backup); backedUp=true; }
      try { fs.renameSync(replacement,destination); } catch(error) {if(backedUp) fs.renameSync(backup,destination); throw error;}
      if(backedUp) fs.rmSync(backup,{recursive:true,force:true}); installed=destination;
    } finally {fs.rmSync(staging,{recursive:true,force:true}); fs.rmSync(replacement,{recursive:true,force:true});}
  } else if(process.platform==='win32') {
    // NSIS waits for the user's per-user component wizard unless --yes was supplied by its caller.
    await run(file,[`/COMPONENTS=${components}`, ...(yes?['/S']:[])]); installed=path.join(process.env.LOCALAPPDATA||path.join(os.homedir(),'AppData','Local'),'Programs','HanX','HanX.exe');
    if(!fs.existsSync(installed)) throw new Error('The desktop installer did not finish at its default per-user location. Run hanx gui after completing installation.');
  } else {
    const destination=path.join(paths().root,VERSION,platformKey(),'HanX.AppImage');
    const applications=path.join(os.homedir(),'.local','share','applications'); fs.mkdirSync(applications,{recursive:true});
    const desktop=path.join(applications,'hanx.desktop');
    const desktopExists=fs.existsSync(desktop);
    const ownedDesktop=state.desktop===desktop && desktopExists && fs.readFileSync(desktop,'utf8').includes('X-HanX-Managed=true');
    if(desktopExists&&!ownedDesktop) throw new Error(`Refusing to overwrite unowned desktop entry: ${desktop}`);
    fs.mkdirSync(path.dirname(destination),{recursive:true}); fs.copyFileSync(file,destination,fs.constants.COPYFILE_EXCL); fs.chmodSync(destination,0o755); installed=destination;
    const contents=`[Desktop Entry]\nType=Application\nName=HanX\nComment=Local document editor\nExec="${installed.replace(/["\\`$]/g,'\\$&')}" %F\nTerminal=false\nCategories=Office;\nX-HanX-Managed=true\n`;
    if(ownedDesktop) {const temporary=desktop+'.'+crypto.randomUUID(); fs.writeFileSync(temporary,contents,{flag:'wx'}); fs.renameSync(temporary,desktop);}
    else fs.writeFileSync(desktop,contents,{flag:'wx'});
    saveState({...readState(),desktop});
  }
  saveState({...readState(),gui:installed,guiVersion:VERSION,guiComponents:components}); return installed;
}
function pdfGuide() {
  console.log('PDF rendering uses optional local LibreOffice (soffice) and Poppler (pdfinfo/pdftotext). HanX does not install them automatically.');
  console.log(process.platform==='darwin'?'Optional install: brew install --cask libreoffice; brew install poppler':process.platform==='linux'?'Optional Debian/Ubuntu install: sudo apt-get install libreoffice poppler-utils':'Optional install: winget install --id TheDocumentFoundation.LibreOffice; install Poppler from a trusted distribution and add its bin directory to your user PATH.');
  console.log('Run hanx capabilities --pretty to check availability, then retry PDF export.');
}
async function installPDF() {
  console.log('선택한 PDF 도구 설치: LibreOffice와 Poppler. 별도 애플리케이션이며 설치 관리자가 권한을 요청할 수 있습니다.');
  if(process.platform==='win32') await run('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'install-pdf.ps1'),'-Install']);
  else if(process.platform==='darwin') { await run('brew',['install','--cask','libreoffice']); await run('brew',['install','poppler']); }
  else {
    const apt=fs.existsSync('/usr/bin/apt-get'); const dnf=fs.existsSync('/usr/bin/dnf');
    if(!apt&&!dnf) { pdfGuide(); throw new Error('이 배포판은 PDF 도구를 직접 설치한 뒤 다시 시도하세요.'); }
    const args=apt?['apt-get','install','-y','libreoffice','poppler-utils']:['dnf','install','-y','libreoffice','poppler-utils'];
    if(process.getuid&&process.getuid()===0) await run(args.shift(),args); else await run('sudo',args);
  }
  console.log('PDF 도구 설치를 마쳤습니다. 새 터미널 또는 앱에서 hanx capabilities --pretty로 확인하세요.');
}
async function askPDF() {
  if(!process.stdin.isTTY||!process.stdout.isTTY) return false;
  const rl=readline.createInterface({input:process.stdin,output:process.stdout});
  try {return await new Promise((resolve,reject)=>{rl.once('SIGINT',()=>reject(new Error('HanX setup cancelled.'))); rl.once('close',()=>resolve(false)); rl.question('PDF 변환 도구(LibreOffice, Poppler)도 설치할까요? [y/N] ',answer=>resolve(/^y(es)?$/i.test(answer.trim())));});} finally {rl.close();}
}
async function setup(args=[],context={}) {
  const options=parseOptions(args); const components=options.components || (options.yes?'cli':await chooseComponents());
  const installPDFTools=options.pdf || (!options.yes && !options.components && await askPDF());
  const root=context.packageRoot||path.resolve(__dirname,'..');
  if(components==='cli'||components==='all') {
    let bundled=false; try {require('../bin/hanx.js').resolveBinary(root,process.platform,process.arch);bundled=true;} catch {}
    if(!bundled && !optionalBinary()) await installCLI();
  }
  if(components==='gui'||components==='all') await installGUI(components,options.yes);
  if(components==='gui') fs.rmSync(paths().cli,{recursive:true,force:true});
  saveState({...readState(),components,version:VERSION});
  console.log(`HanX ${VERSION}: ${components==='all'?'GUI + CLI':components==='cli'?'CLI만 설치':'GUI만 설치'} 선택 완료.`);
  if(components==='gui') console.log('작은 hanx setup / hanx gui 실행기만 유지합니다. 터미널 문서 명령은 비활성화되며 GUI는 내부 엔진을 사용합니다.');
  if(components==='cli') console.log('나중에 GUI 앱을 추가하려면 hanx setup을 실행하세요.');
  if(installPDFTools) await installPDF();
  return {components};
}
async function launchGUI() {
  const state=readState(); const gui=installedGUI(state)||await installGUI('gui');
  if(process.platform==='darwin') await run('/usr/bin/open',[gui]);
  else { const child=spawn(gui,[],{detached:true,stdio:'ignore',shell:false}); await new Promise((resolve,reject)=>{child.once('spawn',resolve);child.once('error',reject);}); child.unref(); }
}
module.exports={VERSION,RELEASE,paths,readState,parseOptions,chooseComponents,validateManifest,selectAsset,expectedName,verifyFile,writeExclusive,download,platformKey,optionalBinary,installCLI,installGUI,installedGUI,setup,launchGUI,pdfGuide,installPDF,releaseManifest};
