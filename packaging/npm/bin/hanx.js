#!/usr/bin/env node
'use strict';
const path = require('node:path');
const fs = require('node:fs');
const { spawn } = require('node:child_process');
function fail(code, message) {
  process.stderr.write(JSON.stringify({ ok: false, error: { code, message } }) + '\n');
  process.exitCode = 1;
}
function resolveBinary(root, platform, arch, exists = fs.existsSync) {
  if (!['darwin','linux','win32'].includes(platform) || !['arm64','x64'].includes(arch)) {
    throw Object.assign(new Error(`Unsupported HanX platform: ${platform}-${arch}.`), { code: 'unsupported_platform' });
  }
  const binary = path.join(root, 'native', `${platform}-${arch}`, platform === 'win32' ? 'hanx.exe' : 'hanx');
  if (exists(binary)) return binary;
  const legacy = path.join(root, 'native', 'hanx');
  if (platform === 'darwin' && exists(legacy)) return legacy;
  throw Object.assign(new Error(`HanX native executable is missing for ${platform}-${arch}: ${binary}. This package must include a native build for your platform; reinstall a matching package or use the standalone CLI archive.`), { code: 'native_binary_missing' });
}
function main() {
  let binary;
  try { binary = resolveBinary(path.resolve(__dirname, '..'), process.platform, process.arch); }
  catch (error) { fail(error.code, error.message); return; }
  const child = spawn(binary, process.argv.slice(2), { stdio: 'inherit', shell: false });
  const handlers = new Map();
  for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
    const handler = () => { if (!child.killed) child.kill(signal); };
    handlers.set(signal, handler);
    process.on(signal, handler);
  }
  function cleanup() { for (const [signal, handler] of handlers) process.removeListener(signal, handler); }
  child.once('error', error => { cleanup(); fail('native_launch_failed', `${binary}: ${error.message}`); });
  child.once('exit', (code, signal) => {
    cleanup();
    if (signal) process.kill(process.pid, signal);
    else process.exitCode = code === null ? 1 : code;
  });
}
module.exports = { resolveBinary };
if (require.main === module) main();
