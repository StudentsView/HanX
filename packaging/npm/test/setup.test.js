'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { parseOptions, validateManifest, selectAsset, verifyFile, chooseComponents, writeExclusive, platformKey } = require('../lib/setup.js');
const version = '2.9.0';
const asset = { component:'cli', platform:'linux', arch:'x64', name:'hanx-cli-linux-x64.tar.gz', sha256:'a'.repeat(64) };
test('automation and noninteractive defaults never select GUI implicitly', async () => {
  assert.equal(parseOptions([]).components, undefined);
  assert.equal(await chooseComponents({ input:{isTTY:false}, output:{isTTY:false} }), 'cli');
  assert.deepEqual(parseOptions(['--components','gui','--yes']), {components:'gui',yes:true,pdf:false});
  assert.throws(() => parseOptions(['--components','everything']), /cli, gui, or all/);
  assert.throws(() => parseOptions(['--yes','--unexpected']), /Unknown/);
});
test('manifest rejects malformed data, traversal, wrong release and duplicate platforms', () => {
  assert.equal(validateManifest({version,assets:[asset]},version).assets.length,1);
  for (const invalid of [null,{}, {version:'2.8.0',assets:[asset]}, {version,assets:[{...asset,name:'../x'}]}, {version,assets:[{...asset,sha256:'oops'}]}, {version,assets:[asset,asset]}]) assert.throws(() => validateManifest(invalid,version));
});
test('matches exact platform and architecture and rejects unsupported hosts', () => {
  const manifest = validateManifest({version,assets:[asset,{...asset,arch:'arm64'}]}, version);
  assert.equal(selectAsset(manifest,'cli','linux','arm64').arch, 'arm64');
  assert.throws(() => selectAsset(manifest,'gui','linux','x64'), /No verified/);
  assert.throws(() => platformKey('freebsd','x64'), /Unsupported/);
});
test('checksum and no-overwrite checks happen before installer execution', async t => {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'hanx-install-')); t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
  const file=path.join(dir,'asset');
  await writeExclusive(file,Buffer.from('trusted bytes'));
  await assert.rejects(writeExclusive(file,Buffer.from('bad bytes')), /exist/i);
  assert.equal(fs.readFileSync(file,'utf8'),'trusted bytes');
  const hash=crypto.createHash('sha256').update('trusted bytes').digest('hex');
  await verifyFile(file,hash);
  await assert.rejects(verifyFile(file,'f'.repeat(64)),/checksum/i);
});
test('interactive arrow selection restores raw mode and cursor on accept and cancellation', async () => {
  const { PassThrough } = require('node:stream');
  for (const [key,expected] of [['\u001b[B\r','gui'],['\u0003',null]]) {
    const input=new PassThrough(); input.isTTY=true; input.isRaw=false;
    const raw=[]; input.setRawMode=v=>{ raw.push(v); input.isRaw=v; };
    const output=new PassThrough(); output.isTTY=true; let printed=''; output.on('data',b=>printed+=b);
    const pending=chooseComponents({input,output});
    process.nextTick(()=>input.write(key));
    if (expected) assert.equal(await pending,expected); else await assert.rejects(pending,/cancel/i);
    assert.deepEqual(raw,[true,false]);
    assert.ok(printed.includes('\u001b[?25h'));
  }
});
test('GUI-only retains bootstrap, disables native commands and removes downloaded CLI', async t => {
  const { setup, paths } = require('../lib/setup.js');
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'hanx-components-'));
  const old=process.env.XDG_DATA_HOME; const oldLocal=process.env.LOCALAPPDATA; process.env.XDG_DATA_HOME=dir; process.env.LOCALAPPDATA=dir;
  t.after(()=>{ if(old===undefined) delete process.env.XDG_DATA_HOME; else process.env.XDG_DATA_HOME=old; if(oldLocal===undefined) delete process.env.LOCALAPPDATA; else process.env.LOCALAPPDATA=oldLocal; fs.rmSync(dir,{recursive:true,force:true}); });
  const locations=paths(); const gui=path.join(dir,'HanX.app'); fs.mkdirSync(gui);
  fs.mkdirSync(locations.cli,{recursive:true}); fs.writeFileSync(path.join(locations.cli,'hanx'),'downloaded native');
  fs.writeFileSync(locations.state,JSON.stringify({gui,guiVersion:version,guiComponents:'gui'}));
  await setup(['--components','gui','--yes']);
  assert.equal(fs.existsSync(locations.cli),false);
  assert.equal(JSON.parse(fs.readFileSync(locations.state)).components,'gui');
  assert.equal(fs.existsSync(path.join(__dirname,'..','bin','hanx.js')),true);
  const result=require('node:child_process').spawnSync(process.execPath,[path.join(__dirname,'..','bin','hanx.js'),'--version'],{encoding:'utf8'});
  assert.equal(result.status,1); assert.match(result.stderr,/cli_not_selected/);
});
test('nonTTY postinstall exits without hanging or fetching a GUI', t => {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'hanx-postinstall-')); t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
  const child=require('node:child_process').spawnSync(process.execPath,[path.join(__dirname,'..','bin','postinstall.js')],{input:'',encoding:'utf8',timeout:10000,env:{...process.env,XDG_DATA_HOME:dir,LOCALAPPDATA:dir}});
  assert.equal(child.status,0,child.stderr);
  assert.match(child.stdout,/hanx setup/); assert.match(child.stdout,/CLI만 설치/);
  assert.equal(JSON.parse(fs.readFileSync(path.join(dir,'HanX','setup.json'))).components,'cli');
});
test('GUI version is independent from a newly upgraded CLI version', t => {
  const { installedGUI }=require('../lib/setup.js');
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'hanx-version-')); t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
  assert.equal(installedGUI({gui:dir,version:'2.9.0',guiVersion:'2.8.0'}),null);
  assert.equal(installedGUI({gui:dir,version:'2.8.0',guiVersion:'2.9.0'}),dir);
  assert.equal(installedGUI({gui:dir,version:'2.9.0'}),null);
});
test('owned macOS GUI upgrade replaces staged app and refuses unowned app', {skip:process.platform!=='darwin'}, async t => {
  const { installGUI, paths }=require('../lib/setup.js'); const cp=require('node:child_process');
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'hanx-upgrade-'));
  const old={HOME:process.env.HOME,XDG_DATA_HOME:process.env.XDG_DATA_HOME}; const fetchOriginal=global.fetch;
  process.env.HOME=directory; process.env.XDG_DATA_HOME=directory;
  t.after(()=>{global.fetch=fetchOriginal; for(const [key,value] of Object.entries(old)) {if(value===undefined) delete process.env[key]; else process.env[key]=value;} fs.rmSync(directory,{recursive:true,force:true});});
  const source=path.join(directory,'source'); fs.mkdirSync(path.join(source,'HanX.app'),{recursive:true}); fs.writeFileSync(path.join(source,'HanX.app','version'),'new');
  const archive=path.join(directory,'fixture.zip'); assert.equal(cp.spawnSync('/usr/bin/ditto',['-c','-k','--keepParent',path.join(source,'HanX.app'),archive]).status,0);
  const bytes=fs.readFileSync(archive); const sha256=crypto.createHash('sha256').update(bytes).digest('hex');
  global.fetch=async url=>new Response(url.endsWith('hanx-install-manifest.json')?JSON.stringify({version,assets:[{component:'gui',platform:'darwin',arch:process.arch,name:'HanX-2.9.0-macOS.zip',sha256}]}):bytes,{status:200});
  const destination=path.join(directory,'Applications','HanX.app'); fs.mkdirSync(destination,{recursive:true}); fs.writeFileSync(path.join(destination,'version'),'old');
  await assert.rejects(installGUI('gui',true),/unowned/);
  assert.equal(fs.readFileSync(path.join(destination,'version'),'utf8'),'old');
  fs.mkdirSync(path.dirname(paths().state),{recursive:true}); fs.writeFileSync(paths().state,JSON.stringify({gui:destination,guiVersion:'2.8.0',version:'2.9.0'}));
  assert.equal(await installGUI('gui',true),destination);
  assert.equal(fs.readFileSync(path.join(destination,'version'),'utf8'),'new');
  assert.equal(JSON.parse(fs.readFileSync(paths().state)).guiVersion,'2.9.0');
  assert.equal(fs.readdirSync(path.dirname(destination)).some(name=>name.startsWith('.HanX-')),false);
});
test('missing manifest uses SHA256SUMS, but malformed published manifest fails closed', async t => {
  const { releaseManifest,expectedName }=require('../lib/setup.js'); const original=global.fetch; t.after(()=>global.fetch=original);
  const name=expectedName('cli',process.platform,process.arch);
  global.fetch=async url=>url.endsWith('hanx-install-manifest.json')?new Response('',{status:404}):new Response('b'.repeat(64)+'  '+name+'\n');
  assert.equal((await releaseManifest()).assets.find(a=>a.component==='cli'&&a.platform===process.platform&&a.arch===process.arch).sha256,'b'.repeat(64));
  global.fetch=async()=>new Response('{broken json');
  await assert.rejects(releaseManifest(),/JSON|Unexpected|property/i);
});
test('download verifies bytes, preserves existing files, and removes failed partial files', async t => {
  const { download, paths }=require('../lib/setup.js'); const original=global.fetch;
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'hanx-download-'));
  const old={XDG_DATA_HOME:process.env.XDG_DATA_HOME,LOCALAPPDATA:process.env.LOCALAPPDATA}; process.env.XDG_DATA_HOME=directory; process.env.LOCALAPPDATA=directory;
  t.after(()=>{global.fetch=original;for(const [key,value] of Object.entries(old)){if(value===undefined)delete process.env[key];else process.env[key]=value;}fs.rmSync(directory,{recursive:true,force:true});});
  const bytes=Buffer.from('real download bytes');const sha256=crypto.createHash('sha256').update(bytes).digest('hex'); let requests=0;
  global.fetch=async()=>{requests++;return new Response(bytes);};
  const downloaded=await download({...asset,name:'fixture.tar.gz',sha256});
  assert.deepEqual(fs.readFileSync(downloaded),bytes);
  assert.equal(await download({...asset,name:'fixture.tar.gz',sha256}),downloaded);assert.equal(requests,1);
  await assert.rejects(download({...asset,name:'fixture.tar.gz',sha256:'c'.repeat(64)}),/checksum/i);
  assert.deepEqual(fs.readFileSync(downloaded),bytes);
  await assert.rejects(download({...asset,name:'wrong.tar.gz',sha256:'c'.repeat(64)}),/checksum/i);
  assert.equal(fs.readdirSync(paths().downloads).some(name=>name.endsWith('.part')),false);
  assert.equal(fs.existsSync(path.join(paths().downloads,'wrong.tar.gz')),false);
});
