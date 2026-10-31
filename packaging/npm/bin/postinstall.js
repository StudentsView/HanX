#!/usr/bin/env node
'use strict';
// npm commonly pipes lifecycle stdio even when its parent was launched in a terminal.
// Never open /dev/tty, read from a pipe, or promise an interactive npm prompt.
const { setup, readState } = require('../lib/setup.js');
const args = process.stdin.isTTY && process.stdout.isTTY ? [] : ['--components', readState().components || 'cli', '--yes'];
console.log('HanX setup: run `hanx setup` for the arrow-key GUI / CLI / both selector.');
// Respect a previous GUI-only choice without reinstalling a GUI during npm maintenance.
if (readState().components === 'gui' && !process.stdin.isTTY) {
  console.log('GUI-only preference retained. The minimal hanx setup / hanx gui launcher remains.');
} else {
  setup(args).catch(error => {
    console.error(`HanX native payload setup could not finish: ${error.message}`);
    console.error('Run `hanx setup --components cli --yes` to retry. No GUI was installed.');
    process.exitCode=1;
  });
}
