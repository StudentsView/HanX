#!/usr/bin/env node
'use strict';
// npm commonly pipes lifecycle stdio even when its parent was launched in a terminal.
// Never open /dev/tty, read from a pipe, or promise an interactive npm prompt.
const path=require('node:path');
const { setup, readState, optionalBinary, installCLI } = require('../lib/setup.js');
console.log('HanX 설치 항목 선택: `hanx setup` (↑/↓ 이동, Enter 선택).');
async function postinstall() {
  if(process.stdin.isTTY&&process.stdout.isTTY) { await setup([]); return; }
  const previous=readState().components;
  if(previous==='gui') {
    console.log('GUI만 설치 설정을 유지합니다. 작은 hanx setup / hanx gui 실행기만 남습니다.');
  } else if(previous==='all') {
    // Updating the npm launcher must not implicitly download a desktop app.
    try { require('./hanx.js').resolveBinary(path.resolve(__dirname,'..'),process.platform,process.arch); }
    catch(error) { if(error.code!=='native_binary_missing') throw error; if(!optionalBinary()) await installCLI(); }
    console.log('CLI 준비 완료. 기존 GUI 선택을 유지합니다. GUI 갱신은 hanx setup에서 선택하세요.');
  } else await setup(['--components','cli','--yes']);
}
postinstall().catch(error=>{
  console.error(`HanX 설치를 마치지 못했습니다: ${error.message}`);
  console.error('`hanx setup --components cli --yes`로 다시 시도하세요.');
  process.exitCode=1;
});
