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
  const items=[['cli','CLI only','Terminal commands and MCP tools'],['gui','GUI only','Desktop app; minimal setup launcher remains'],['all','GUI + CLI','Desktop app and terminal commands']];
  return new Promise((resolve,reject)=>{
    let selected=0; const wasRaw=Boolean(input.isRaw); const wasPaused=input.isPaused(); let done=false;
    const draw=()=> { output.write('\r\u001b[JChoose HanX components (↑/↓, Enter; Esc cancels)\n'); for (let i=0;i<items.length;i++) output.write(`${i===selected?'❯':' '} ${items[i][1].padEnd(12)} ${items[i][2]}\n`); output.write('\u001b[4A'); };
    const cleanup=()=>{ if(done) return; done=true; input.removeListener('keypress',onKey); input.removeListener('end',onEnd); input.removeListener('error',onError); process.removeListener('SIGTERM',onTerminate); input.setRawMode(wasRaw); if(wasPaused) input.pause(); output.write('\r\u001b[J\u001b[?25h'); };
    const cancel=()=>{cleanup(); reject(new Error('HanX setup cancelled; no components changed.'));};
    const onEnd=()=>cancel(); const onError=error=>{cleanup();reject(error);}; const onTerminate=()=>cancel();
    const onKey=(str,key={})=>{ if(key.name==='up') selected=(selected+2)%3; else if(key.name==='down') selected=(selected+1)%3; else if(key.name==='return') { const value=items[selected][0]; cleanup(); resolve(value); return; } else if(key.name==='escape'||(key.ctrl&&key.name==='c')) {cancel();return;} else return; draw(); };
    readline.emitKeypressEvents(input); input.setRawMode(true); input.resume(); output.write('\u001b[?25l'); draw(); input.on('keypress',onKey); input.on('end',onEnd); input.on('error',onError); process.once('SIGTERM',onTerminate);
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
async function installGUI(components='gui', yes=false) {
  const state=readState();
  if(state.gui && fs.existsSync(state.gui)) return state.gui;
  const file=await download(selectAsset(await releaseManifest(),'gui'));
  let installed;
  if(process.platform==='darwin') {
    const parent=path.join(os.homedir(),'Applications'); const destination=path.join(parent,'HanX.app');
    if(fs.existsSync(destination)) throw new Error(`Refusing to overwrite ${destination}. Move the existing app before installing this version.`);
    fs.mkdirSync(parent,{recursive:true}); const staging=fs.mkdtempSync(path.join(paths().downloads,'gui-'));
    try {await extract(file,staging); const app=fs.existsSync(path.join(staging,'HanX.app'))?path.join(staging,'HanX.app'):null; if(!app) throw new Error('GUI archive does not contain HanX.app.'); await run('/usr/bin/ditto',[app,destination]); installed=destination;} finally {fs.rmSync(staging,{recursive:true,force:true});}
  } else if(process.platform==='win32') {
    // NSIS waits for the user's per-user component wizard unless --yes was supplied by its caller.
    await run(file,[`/COMPONENTS=${components}`, ...(yes?['/S']:[])]); installed=path.join(process.env.LOCALAPPDATA||path.join(os.homedir(),'AppData','Local'),'Programs','HanX','HanX.exe');
    if(!fs.existsSync(installed)) throw new Error('The desktop installer did not finish at its default per-user location. Run hanx gui after completing installation.');
  } else {
    const destination=path.join(paths().root,VERSION,platformKey(),'HanX.AppImage');
    fs.mkdirSync(path.dirname(destination),{recursive:true}); fs.copyFileSync(file,destination,fs.constants.COPYFILE_EXCL); fs.chmodSync(destination,0o755); installed=destination;
    const applications=path.join(os.homedir(),'.local','share','applications'); fs.mkdirSync(applications,{recursive:true});
    const desktop=path.join(applications,'hanx.desktop'); if(!fs.existsSync(desktop)) fs.writeFileSync(desktop,`[Desktop Entry]\nType=Application\nName=HanX\nComment=Local document editor\nExec="${installed.replace(/["\\`$]/g,'\\$&')}" %F\nTerminal=false\nCategories=Office;\n`,{flag:'wx'});
  }
  saveState({...readState(),gui:installed}); return installed;
}
function pdfGuide() {
  console.log('PDF rendering uses optional local LibreOffice (soffice) and Poppler (pdfinfo/pdftotext). HanX does not install them automatically.');
  console.log(process.platform==='darwin'?'Optional install: brew install --cask libreoffice; brew install poppler':process.platform==='linux'?'Optional Debian/Ubuntu install: sudo apt-get install libreoffice poppler-utils':'Optional install: winget install --id TheDocumentFoundation.LibreOffice; install Poppler from a trusted distribution and add its bin directory to your user PATH.');
  console.log('Run hanx capabilities --pretty to check availability, then retry PDF export.');
}
async function setup(args=[],context={}) {
  const options=parseOptions(args); const components=options.components || (options.yes?'cli':await chooseComponents());
  const state=readState(); const root=context.packageRoot||path.resolve(__dirname,'..');
  if(components==='cli'||components==='all') {
    let bundled=false; try {require('../bin/hanx.js').resolveBinary(root,process.platform,process.arch);bundled=true;} catch {}
    if(!bundled && !optionalBinary()) await installCLI();
  }
  if(components==='gui'||components==='all') await installGUI(components,options.yes);
  if(components==='gui') fs.rmSync(paths().cli,{recursive:true,force:true});
  saveState({...readState(),components,version:VERSION});
  console.log(`HanX ${VERSION}: ${components==='all'?'GUI + CLI':components.toUpperCase()+' only'} selected.`);
  if(components==='gui') console.log('The hanx setup / hanx gui launcher remains; native terminal commands are disabled. The desktop app contains its own internal engine.');
  if(components==='cli') console.log('Run hanx setup to add the desktop app later.');
  if(options.pdf) pdfGuide();
  return {components};
}
async function launchGUI() {
  const state=readState(); const gui=state.gui && fs.existsSync(state.gui)?state.gui:await installGUI('gui');
  if(process.platform==='darwin') await run('/usr/bin/open',[gui]);
  else { const child=spawn(gui,[],{detached:true,stdio:'ignore',shell:false}); await new Promise((resolve,reject)=>{child.once('spawn',resolve);child.once('error',reject);}); child.unref(); }
}
module.exports={VERSION,RELEASE,paths,readState,parseOptions,chooseComponents,validateManifest,selectAsset,expectedName,verifyFile,writeExclusive,platformKey,optionalBinary,installCLI,setup,launchGUI,pdfGuide,releaseManifest};
