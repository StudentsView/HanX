#!/usr/bin/env node
'use strict';
// Run only after the corresponding real, smoke-tested native trees have been staged.
const fs=require('node:fs'); const path=require('node:path');
const root=__dirname; const version=require('./package.json').version;
const output=path.resolve(process.argv[2]||path.join(root,'..','..','build','npm-platforms'));
fs.mkdirSync(output,{recursive:true});
for(const platform of ['darwin','linux','win32']) for(const arch of ['arm64','x64']) {
  const key=`${platform}-${arch}`; const native=path.join(root,'native',key);
  if(!fs.existsSync(path.join(native,platform==='win32'?'hanx.exe':'hanx'))) continue;
  const destination=path.join(output,key);
  if(fs.existsSync(destination)) throw new Error(`Refusing to overwrite ${destination}`);
  fs.mkdirSync(destination);
  fs.cpSync(native,path.join(destination,'native'),{recursive:true,errorOnExist:true,force:false});
  for(const file of ['LICENSE','NOTICE']) fs.copyFileSync(path.join(root,file),path.join(destination,file),fs.constants.COPYFILE_EXCL);
  fs.writeFileSync(path.join(destination,'package.json'),JSON.stringify({name:`@juyoungsuh/hanx-${key}`,version,description:`HanX native runtime for ${key}`,license:'MIT',os:[platform],cpu:[arch],files:['native/','LICENSE','NOTICE'],publishConfig:{access:'public'}},null,2)+'\n',{flag:'wx'});
  console.log(destination);
}
