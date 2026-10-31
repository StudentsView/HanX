'use strict';
// Runs only on disposable native CI users after release assets and npm are public.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const {spawnSync}=require('node:child_process');
const version=require('./npm/package.json').version;
if(process.env.GITHUB_ACTIONS!=='true')throw new Error('Published installation verification requires a disposable CI user.');
const npmRoot=path.resolve(process.argv[2]);
const cli=path.join(npmRoot,'node_modules','@juyoungsuh','hanx','bin','hanx.js');
function run(command,args,options={}){
  const result=spawnSync(command,args,{encoding:'utf8',timeout:300000,...options});
  if(result.error)throw result.error;
  if(result.status!==0)throw new Error(`${path.basename(command)} failed (${result.status}):\n${result.stdout}\n${result.stderr}`);
  if(result.stdout)process.stdout.write(result.stdout);
  return result.stdout;
}
const call=(...args)=>run(process.execPath,[cli,...args]);
function state(){
  const base=process.platform==='win32'?process.env.LOCALAPPDATA:(process.env.XDG_DATA_HOME||path.join(os.homedir(),'.local','share'));
  return JSON.parse(fs.readFileSync(path.join(base,'HanX','setup.json'),'utf8'));
}
assert.equal(JSON.parse(call('--version')).data.version,version);
call('setup','--components','cli','--yes');
assert.equal(state().components,'cli');
call('setup','--components','all','--yes');
assert.equal(state().components,'all');
const gui=state().gui;
assert.ok(fs.existsSync(gui),'The public GUI asset must install at its recorded location.');
const guiArgs=['--smoke-test'];
if(process.platform==='linux'){
  // AppImage runtime extraction avoids depending on runner FUSE mount permissions.
  run('xvfb-run',['-a',gui,'--appimage-extract-and-run','--no-sandbox',...guiArgs]);
}else run(gui,guiArgs);
call('setup','--components','gui','--yes');
assert.equal(state().components,'gui');
const disabled=spawnSync(process.execPath,[cli,'--version'],{encoding:'utf8',timeout:30000});
assert.notEqual(disabled.status,0);
assert.equal(JSON.parse(disabled.stderr).error.code,'cli_not_selected');
call('setup','--components','cli','--yes');
assert.equal(JSON.parse(call('--version')).data.version,version);
const native=process.platform==='win32'
  ?path.join(process.env.LOCALAPPDATA,'HanX',version,`${process.platform}-${process.arch}`,'cli','hanx.exe')
  :path.join(process.env.XDG_DATA_HOME||path.join(os.homedir(),'.local','share'),'HanX',version,`${process.platform}-${process.arch}`,'cli','hanx');
run(process.env.PYTHON||'python',['packaging/smoke-cli.py',native,'--pdf']);
console.log('Published npm, verified GUI download, CLI/GUI/both choices, installed renderer, PDF and MCP passed.');
