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
