'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { resolveBinary } = require('../bin/hanx.js');
const root = path.resolve('/tmp/HanX package');
test('selects exact platform binary, including executable suffix', () => {
  for (const [platform, arch, file] of [['win32','x64','hanx.exe'],['linux','arm64','hanx'],['darwin','x64','hanx']]) {
    const expected = path.join(root, 'native', `${platform}-${arch}`, file);
    assert.equal(resolveBinary(root, platform, arch, p => p === expected), expected);
  }
});
test('preserves legacy mac universal binary fallback only on macOS', () => {
  const legacy = path.join(root, 'native', 'hanx');
  assert.equal(resolveBinary(root,'darwin','arm64',p => p === legacy), legacy);
  assert.throws(() => resolveBinary(root,'linux','x64',p => p === legacy), {code:'native_binary_missing'});
});
test('missing binary identifies precise expected path', () => {
  assert.throws(() => resolveBinary(root,'win32','x64',() => false), error => error.code === 'native_binary_missing' && error.message.includes(path.join(root,'native','win32-x64','hanx.exe')));
});
test('unsupported architectures and OS fail without falling back', () => {
  for (const [platform,arch] of [['freebsd','x64'],['linux','ia32']]) {
    assert.throws(() => resolveBinary(root,platform,arch,() => true), {code:'unsupported_platform'});
  }
});
