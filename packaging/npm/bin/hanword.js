#!/usr/bin/env node
'use strict';
const path = require('node:path');
const fs = require('node:fs');
const { spawn } = require('node:child_process');
function fail(code, message) {
  process.stderr.write(JSON.stringify({ ok: false, error: { code, message } }) + '\n');
  process.exitCode = 1;
}
const binary = path.resolve(__dirname, '..', 'native', 'hanword');
if (process.platform !== 'darwin' || !['arm64', 'x64'].includes(process.arch)) {
  fail('unsupported_platform', 'HanWord requires macOS on Apple Silicon or Intel.');
} else if (!fs.existsSync(binary)) {
  fail('native_binary_missing', 'The HanWord native executable is missing. Reinstall the package.');
} else {
  const child = spawn(binary, process.argv.slice(2), { stdio: 'inherit', shell: false });
  const handlers = new Map();
  for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
    const handler = () => { if (!child.killed) child.kill(signal); };
    handlers.set(signal, handler);
    process.on(signal, handler);
  }
  function cleanup() { for (const [signal, handler] of handlers) process.removeListener(signal, handler); }
  child.once('error', error => { cleanup(); fail('native_launch_failed', error.message); });
  child.once('exit', (code, signal) => {
    cleanup();
    if (signal) process.kill(process.pid, signal);
    else process.exitCode = code === null ? 1 : code;
  });
}
